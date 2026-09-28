import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Native iOS editor state — the counterpart of the Android EditorViewModel,
/// with the same operations and the same time model:
/// - clip SOURCE time: trims (and the clip strip);
/// - OUTPUT time (speed ranges applied — SpeedMap): the 30s cap, music
///   placement, captions, transitions. The player's own time is OUTPUT time.
///
/// Preview and export share one composition (EditorCompositionBuilder), so
/// every edit is just "update state, rebuild the player item".
///
/// Concurrency: the whole class is @MainActor; AVFoundation callbacks hop
/// back with Task { @MainActor … } and nothing main-actor-isolated is
/// touched from deinit (CI's compiler rejects that).
@MainActor
final class EditorViewModel: ObservableObject {
  let player = AVPlayer()

  @Published private(set) var clips: [EditorClip]
  @Published private(set) var transitions: [TransitionSpec]
  @Published private(set) var selectedClipIndex = 0

  @Published private(set) var musicOriginalPath: String?
  @Published private(set) var musicSpeed: Double
  @Published private(set) var musicFadeInMs: Int64
  @Published private(set) var musicFadeOutMs: Int64
  @Published private(set) var musicLoop: Bool
  @Published private(set) var musicStartOffsetMs: Int64
  @Published private(set) var musicSourceStartMs: Int64
  @Published private(set) var musicPlayDurationMs: Int64
  /// Length of the RE-TIMED song (song / musicSpeed) — the unit music placement is measured in.
  @Published private(set) var musicDurationMs: Int64?

  @Published private(set) var rotationDegrees: Int
  @Published private(set) var isMuted: Bool
  /// Slow-motion ranges (SpeedRange), SOURCE time — part of the Ad, not the whole video.
  @Published private(set) var speedRanges: [SpeedRange]
  /// The range being edited on the timeline's Speed row.
  @Published var selectedSpeedRangeId: String?
  /// A short, non-error message under the tools; clears itself.
  @Published private(set) var notice: String?
  @Published private(set) var videoFilter: VideoFilter
  /// Captions (EditorText.swift). Pure overlay state: changing them never
  /// rebuilds the player — the preview draws them over the video, the
  /// export burns them in through the compositor.
  @Published private(set) var textLayers: [TextLayer]
  /// Animated stickers — overlay state like the captions.
  @Published private(set) var stickerLayers: [StickerLayer]
  /// Sound effects — part of the composition (preview and export mix them).
  @Published private(set) var soundLayers: [SoundLayer]
  /// The caption being edited/dragged in the preview.
  @Published var selectedTextId: String?
  /// Width / height of the rendered frame (the rectangle captions live in).
  @Published private(set) var renderAspect: Double = 9.0 / 16.0

  @Published private(set) var thumbnails: [String: [ThumbnailFrame]] = [:]
  @Published private(set) var filterThumbnails: [VideoFilter: UIImage] = [:]

  @Published private(set) var isPlaying = false
  /// Player position, OUTPUT time.
  @Published private(set) var positionOutMs: Int64 = 0
  @Published private(set) var isExporting = false
  @Published private(set) var exportProgress: Double = 0
  @Published private(set) var exportError: String?
  @Published private(set) var previewError: String?
  @Published private(set) var isAttachingMusic = false

  struct ThumbnailFrame {
    let sourceMs: Int64
    let image: UIImage
  }

  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var outputDurationOfItemMs: Int64 = 0

  init(state: EditorSessionState, newClipPath: String?) {
    clips = state.clips
    transitions = Self.normalized(state.transitions, clipCount: state.clips.count)
    musicOriginalPath = state.musicOriginalPath
    musicSpeed = state.musicSpeed
    musicFadeInMs = state.musicFadeInMs
    musicFadeOutMs = state.musicFadeOutMs
    musicLoop = state.musicLoop
    musicStartOffsetMs = state.musicStartOffsetMs
    musicSourceStartMs = state.musicSourceStartMs
    musicPlayDurationMs = state.musicPlayDurationMs
    rotationDegrees = state.rotationDegrees
    isMuted = state.isMuted
    speedRanges = state.speedRanges.sorted { $0.startMs < $1.startMs }
    videoFilter = state.videoFilter
    textLayers = state.textLayers
    stickerLayers = state.stickerLayers
    soundLayers = state.soundLayers

    if let path = musicOriginalPath, let songMs = Self.durationMs(path: path) {
      musicDurationMs = Int64(Double(songMs) / musicSpeed)
    } else {
      musicOriginalPath = nil
    }

    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    observePlayer()

    var startAt: Int64 = 0
    if let newClipPath, appendClip(path: newClipPath) {
      startAt = max(0, clipStartMs(clips.count - 1) - 1000)
    }
    rebuild(resumeAtSourceMs: startAt, play: true)
    generateThumbnails()
  }

  // MARK: Derived values

  var totalDurationMs: Int64 { clips.reduce(0) { $0 + $1.keptDurationMs } }
  var speedMap: SpeedMap { SpeedMap(speedRanges) }
  func toOutputMs(_ sourceMs: Int64) -> Int64 { speedMap.toOutput(sourceMs) }
  func toSourceMs(_ outputMs: Int64) -> Int64 { speedMap.toSource(outputMs) }
  var outputDurationMs: Int64 { toOutputMs(totalDurationMs) }
  private var outputRemainingMs: Int64 { max(0, EditorLimits.maxTotalMs - outputDurationMs) }
  /// SOURCE time still free — the camera's limit for an extra take (it lands after every range, at 1x).
  var remainingMs: Int64 { outputRemainingMs }
  var canAddClip: Bool { remainingMs >= EditorLimits.minClipMs }

  /// The longest clip `index` may become. Conservative: extra footage could
  /// fall inside the slowest range overlapping this clip.
  func maxKeptMs(for index: Int) -> Int64 {
    guard clips.indices.contains(index) else { return 0 }
    let start = clipStartMs(index)
    let slowest = speedMap.minSpeed(from: start, to: start + clips[index].keptDurationMs)
    return clips[index].keptDurationMs + Int64(Double(outputRemainingMs) * slowest)
  }
  var hasMusic: Bool { musicOriginalPath != nil && musicDurationMs != nil }
  var musicCoveredMs: Int64 {
    musicLoop && musicPlayDurationMs > 0
      ? max(outputDurationMs - musicStartOffsetMs, musicPlayDurationMs)
      : musicPlayDurationMs
  }
  /// Playhead on the clip strip, SOURCE time.
  var globalPositionMs: Int64 { toSourceMs(positionOutMs) }

  func clipStartMs(_ index: Int) -> Int64 { clips.prefix(index).reduce(0) { $0 + $1.keptDurationMs } }

  func sessionState() -> EditorSessionState {
    EditorSessionState(
      clips: clips, transitions: transitions, musicPath: musicOriginalPath, musicOriginalPath: musicOriginalPath,
      musicSpeed: musicSpeed, musicFadeInMs: musicFadeInMs, musicFadeOutMs: musicFadeOutMs, musicLoop: musicLoop,
      musicStartOffsetMs: musicStartOffsetMs, musicSourceStartMs: musicSourceStartMs,
      musicPlayDurationMs: musicPlayDurationMs, rotationDegrees: rotationDegrees, isMuted: isMuted,
      speedRanges: speedRanges, videoFilter: videoFilter, textLayers: textLayers,
      stickerLayers: stickerLayers, soundLayers: soundLayers)
  }

  // MARK: Playback

  func togglePlayPause() {
    if player.timeControlStatus == .playing { player.pause() } else { player.play() }
  }

  func pause() { player.pause() }

  /// Seeks to a SOURCE-time position on the clip strip.
  func seekToGlobal(_ sourceMs: Int64) {
    let clamped = min(max(sourceMs, 0), max(totalDurationMs - 1, 0))
    let outMs = toOutputMs(clamped)
    positionOutMs = outMs
    player.seek(to: EditorCompositionBuilder.ms(outMs), toleranceBefore: .zero, toleranceAfter: .zero)
  }

  private func observePlayer() {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 30), queue: .main
    ) { [weak self] time in
      let ms = Int64(max(0, CMTimeGetSeconds(time)) * 1000)
      Task { @MainActor in self?.positionOutMs = ms }
    }
    statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      let playing = player.timeControlStatus == .playing
      Task { @MainActor in self?.isPlaying = playing }
    }
  }

  /// Rebuilds the composition from the current state and swaps it into the player.
  private func rebuild(resumeAtSourceMs: Int64, play: Bool) {
    previewError = nil
    do {
      let built = try EditorCompositionBuilder.build(state: sessionState())
      let item = AVPlayerItem(asset: built.asset)
      item.videoComposition = built.videoComposition
      item.audioMix = built.audioMix
      item.audioTimePitchAlgorithm = built.pitchAlgorithm
      outputDurationOfItemMs = built.outputDurationMs
      renderAspect = built.renderAspect

      if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          // Loop the whole Ad.
          self?.player.seek(to: .zero)
          self?.player.play()
        }
      }

      player.replaceCurrentItem(with: item)
      seekToGlobal(resumeAtSourceMs)
      if play { player.play() } else { player.pause() }
    } catch {
      previewError = error.localizedDescription
    }
  }

  private func currentSourcePosition() -> Int64 { globalPositionMs }

  // MARK: Clips

  func selectClip(_ index: Int) {
    if clips.indices.contains(index) { selectedClipIndex = index }
  }

  func setClipTrim(index: Int, startMs: Int64, endMs: Int64) {
    guard clips.indices.contains(index) else { return }
    let clip = clips[index]
    let maxKept = max(maxKeptMs(for: index), EditorLimits.minClipMs)
    let start = min(max(startMs, 0), clip.sourceDurationMs)
    let end = min(max(endMs, start), min(clip.sourceDurationMs, start + maxKept))
    // Keep every speed range on the same FOOTAGE: positions inside this clip
    // follow its content, positions after it shift by the change.
    let clipStart = clipStartMs(index)
    let oldKept = clip.keptDurationMs
    clips[index].trimStartMs = start
    clips[index].trimEndMs = end
    speedRanges = speedRanges.remapped(totalMs: totalDurationMs) { g in
      if g < clipStart { return g }
      if g <= clipStart + oldKept {
        return clipStart + (min(max(clip.trimStartMs + (g - clipStart), start), end) - start)
      }
      return g + (end - start) - oldKept
    }
    dropStaleSpeedSelection()
    clampMusicToTimeline()
    rebuild(resumeAtSourceMs: clipStartMs(index), play: isPlaying)
  }

  @discardableResult
  private func appendClip(path: String) -> Bool {
    guard let sourceMs = Self.durationMs(path: path) else { return false }
    let kept = min(sourceMs, remainingMs)
    guard kept > 0 else { return false }
    clips.append(EditorClip(path: path, sourceDurationMs: sourceMs, trimStartMs: 0, trimEndMs: kept))
    transitions = Self.normalized(transitions, clipCount: clips.count)
    selectedClipIndex = clips.count - 1
    return true
  }

  func removeClip(_ index: Int) {
    guard clips.count > 1, clips.indices.contains(index) else { return }
    let clipStart = clipStartMs(index)
    let kept = clips[index].keptDurationMs
    clips.remove(at: index)
    // Ranges on the removed footage collapse (and are dropped); later ones move left.
    speedRanges = speedRanges.remapped(totalMs: totalDurationMs) { g in
      g < clipStart ? g : (g <= clipStart + kept ? clipStart : g - kept)
    }
    dropStaleSpeedSelection()
    if !transitions.isEmpty { transitions.remove(at: max(index - 1, 0)) }
    selectedClipIndex = min(selectedClipIndex, clips.count - 1)
    clampMusicToTimeline()
    rebuild(resumeAtSourceMs: 0, play: isPlaying)
  }

  // MARK: Transitions

  func setTransitionType(_ boundary: Int, _ type: ClipTransition) {
    guard transitions.indices.contains(boundary) else { return }
    transitions[boundary].type = type
    rebuild(resumeAtSourceMs: replayStart(boundary), play: true)
  }

  /// Slider moving — state only; commitTransitionDuration rebuilds.
  func setTransitionDuration(_ boundary: Int, _ durationMs: Int64) {
    guard transitions.indices.contains(boundary) else { return }
    transitions[boundary].durationMs = min(max(durationMs, EditorLimits.minTransitionMs), EditorLimits.maxTransitionMs)
  }

  func commitTransitionDuration(_ boundary: Int) {
    rebuild(resumeAtSourceMs: replayStart(boundary), play: true)
  }

  func replayTransition(_ boundary: Int) {
    seekToGlobal(replayStart(boundary))
    player.play()
  }

  /// A bit before the boundary — far enough back to show a fade-out too (lead is OUTPUT time).
  private func replayStart(_ boundary: Int) -> Int64 {
    guard transitions.indices.contains(boundary) else { return 0 }
    let lead = max(1000, transitions[boundary].durationMs + 500)
    return toSourceMs(max(0, toOutputMs(clipStartMs(boundary + 1)) - lead))
  }

  // MARK: Music

  /// Copies the picked song into app storage (a picker URL is only
  /// temporarily readable) and attaches it.
  func setMusic(url: URL) {
    isAttachingMusic = true
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    do {
      let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
      let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
      let dest = dir.appendingPathComponent("editor_music_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
      try FileManager.default.copyItem(at: url, to: dest)
      guard let songMs = Self.durationMs(path: dest.path) else {
        throw NSError(domain: "AdGag", code: 20, userInfo: [NSLocalizedDescriptionKey: tr("Couldn't read that audio file.")])
      }
      musicOriginalPath = dest.path
      musicSpeed = 1
      musicDurationMs = songMs
      musicFadeInMs = 0
      musicFadeOutMs = 0
      musicStartOffsetMs = 0
      musicSourceStartMs = 0
      musicPlayDurationMs = min(songMs, outputDurationMs)
      // A song shorter than the video starts out looping to fill it.
      musicLoop = songMs < outputDurationMs
      isAttachingMusic = false
      rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
    } catch {
      isAttachingMusic = false
      previewError = error.localizedDescription
    }
  }

  func removeMusic() {
    musicOriginalPath = nil
    musicDurationMs = nil
    musicSpeed = 1
    musicFadeInMs = 0
    musicFadeOutMs = 0
    musicLoop = false
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  /// Music speed with pitch kept. The same stretch of the SONG stays selected,
  /// so in-point and length scale by old/new speed.
  func changeMusicSpeed(_ speed: Double) {
    guard let path = musicOriginalPath, speed != musicSpeed, let songMs = Self.durationMs(path: path) else { return }
    let factor = musicSpeed / speed
    musicSpeed = speed
    let retimed = Int64(Double(songMs) / speed)
    musicDurationMs = retimed
    musicSourceStartMs = min(max(Int64(Double(musicSourceStartMs) * factor), 0), max(retimed - 1, 0))
    musicPlayDurationMs = Int64(Double(musicPlayDurationMs) * factor)
    clampMusicToTimeline()
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  func changeMusicLoop(_ loop: Bool) {
    guard loop != musicLoop else { return }
    musicLoop = loop
    setMusicFade(inMs: musicFadeInMs, outMs: musicFadeOutMs, commit: false)
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  func setMusicFade(inMs: Int64, outMs: Int64, commit: Bool) {
    let covered = max(musicCoveredMs, 0)
    musicFadeInMs = min(max(inMs, 0), min(EditorLimits.maxMusicFadeMs, covered))
    musicFadeOutMs = min(max(outMs, 0), min(EditorLimits.maxMusicFadeMs, covered))
    if commit { rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying) }
  }

  /// Music start on the timeline (OUTPUT), the song in-point and the played length.
  func setMusicPlacement(startOffsetMs: Int64, sourceStartMs: Int64, playDurationMs: Int64) {
    guard let songMs = musicDurationMs else { return }
    let total = outputDurationMs
    let start = min(max(startOffsetMs, 0), total)
    let sourceStart = min(max(sourceStartMs, 0), max(songMs - 1, 0))
    musicStartOffsetMs = start
    musicSourceStartMs = sourceStart
    musicPlayDurationMs = min(max(playDurationMs, 0), min(songMs - sourceStart, total - start))
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  private func clampMusicToTimeline() {
    guard hasMusic else { return }
    let total = outputDurationMs
    musicStartOffsetMs = min(max(musicStartOffsetMs, 0), total)
    musicPlayDurationMs = min(max(musicPlayDurationMs, 0), total - musicStartOffsetMs)
  }

  // MARK: Look

  func rotateNinety() {
    rotationDegrees = (rotationDegrees + 90) % 360
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  func toggleMute() {
    isMuted.toggle()
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: isPlaying)
  }

  // MARK: Speed ranges (slow motion on part of the Ad) — same rules as Android

  /// A 0.5x range at the playhead (fitted between neighbours and under the
  /// 30s cap), or the range the playhead is already in. Nil if there's no room.
  @discardableResult
  func addSpeedRangeAtPlayhead() -> SpeedRange? {
    pause()
    let g = min(max(globalPositionMs, 0), totalDurationMs)
    if let existing = speedRanges.first(where: { g >= $0.startMs && g < $0.endMs }) {
      selectedSpeedRangeId = existing.id
      return existing
    }
    // A full 30s Ad has no room for slow motion: shorten the end of the last
    // clip just enough for a default 0.5x range (and say so) instead of
    // "trim first" — same as Android.
    let needed = EditorLimits.defaultSpeedRangeMs // at 0.5x a range adds its own length
    let room = EditorLimits.maxTotalMs - outputDurationMs
    let cut = room < needed ? shortenEnd(needed - room) : 0
    if cut > 0 { showNotice(tr("Shortened the end by {0} so slow motion fits in 30s.", formatPreciseSeconds(cut))) }
    guard let speed = [0.5, 0.75].first(where: { maxRangeLengthMs(except: nil, speed: $0) >= EditorLimits.minSpeedRangeMs })
    else {
      if cut > 0 { rebuild(resumeAtSourceMs: 0, play: false) }
      return nil
    }
    let gapStart = speedRanges.filter { $0.endMs <= g }.map(\.endMs).max() ?? 0
    let gapEnd = speedRanges.filter { $0.startMs > g }.map(\.startMs).min() ?? totalDurationMs
    let length = min(EditorLimits.defaultSpeedRangeMs, gapEnd - gapStart, maxRangeLengthMs(except: nil, speed: speed))
    guard length >= EditorLimits.minSpeedRangeMs else {
      if cut > 0 { rebuild(resumeAtSourceMs: 0, play: false) }
      return nil
    }
    let start = max(min(g, gapEnd - length), gapStart)
    let range = SpeedRange(startMs: start, endMs: start + length, speed: speed)
    commitSpeedRanges(speedRanges + [range], startAt: start)
    selectedSpeedRangeId = range.id
    return range
  }

  /// Trims up to `outputMs` off the END of the last clip (keeping it at least
  /// minClipMs) without rebuilding — the caller does. Returns what was cut.
  private func shortenEnd(_ outputMs: Int64) -> Int64 {
    guard let index = clips.indices.last else { return 0 }
    let cut = max(min(outputMs, clips[index].keptDurationMs - EditorLimits.minClipMs), 0)
    guard cut > 0 else { return 0 }
    clips[index].trimEndMs -= cut
    speedRanges = speedRanges.remapped(totalMs: totalDurationMs) { $0 }
    dropStaleSpeedSelection()
    return cut
  }

  /// How long a range at `speed` may be without pushing the Ad past 30s
  /// (ignoring range `except`). A range at `speed` adds length × (1/speed − 1).
  func maxRangeLengthMs(except id: String?, speed: Double) -> Int64 {
    let without = SpeedMap(speedRanges.filter { $0.id != id }).toOutput(totalDurationMs)
    return lengthFitting(room: EditorLimits.maxTotalMs - without, speed: speed)
  }

  private func lengthFitting(room: Int64, speed: Double) -> Int64 {
    let extraPerMs = 1 / speed - 1
    guard extraPerMs > 0 else { return totalDurationMs }
    return min(Int64(Double(max(room, 0)) / extraPerMs), totalDurationMs)
  }

  func canUseRangeSpeed(_ id: String, _ speed: Double) -> Bool {
    guard let r = speedRanges.first(where: { $0.id == id }) else { return false }
    return r.lengthMs <= maxRangeLengthMs(except: id, speed: speed)
  }

  func setSpeedRangeSpeed(_ id: String, _ speed: Double) {
    guard let r = speedRanges.first(where: { $0.id == id }), r.speed != speed, canUseRangeSpeed(id, speed) else { return }
    commitSpeedRanges(speedRanges.map { $0.id == id ? SpeedRange(id: id, startMs: $0.startMs, endMs: $0.endMs, speed: speed) : $0 },
                      startAt: r.startMs)
  }

  /// Where range `id` may extend to: the end of the range before it, the start of the one after it.
  func speedRangeLimits(_ id: String) -> (Int64, Int64) {
    guard let r = speedRanges.first(where: { $0.id == id }) else { return (0, totalDurationMs) }
    let lower = speedRanges.filter { $0.id != id && $0.endMs <= r.startMs }.map(\.endMs).max() ?? 0
    let upper = speedRanges.filter { $0.id != id && $0.startMs >= r.endMs }.map(\.startMs).min() ?? totalDurationMs
    return (lower, upper)
  }

  /// Timeline drag of a range's edges (SOURCE time), clamped to neighbours,
  /// a minimum length and the 30s cap — shortened from the edge that moved.
  func setSpeedRangeBounds(_ id: String, startMs: Int64, endMs: Int64, movedStart: Bool) {
    guard let r = speedRanges.first(where: { $0.id == id }) else { return }
    let (lower, upper) = speedRangeLimits(id)
    var s = min(max(startMs, lower), upper)
    var e = min(max(endMs, lower), upper)
    let maxLen = maxRangeLengthMs(except: id, speed: r.speed)
    if e - s > maxLen { if movedStart { s = e - maxLen } else { e = s + maxLen } }
    if e - s < EditorLimits.minSpeedRangeMs {
      if movedStart { s = max(e - EditorLimits.minSpeedRangeMs, lower) } else { e = min(s + EditorLimits.minSpeedRangeMs, upper) }
      if e - s < EditorLimits.minSpeedRangeMs { return }
    }
    guard s != r.startMs || e != r.endMs else { return }
    commitSpeedRanges(speedRanges.map { $0.id == id ? SpeedRange(id: id, startMs: s, endMs: e, speed: r.speed) : $0 }, startAt: s)
  }

  func canApplySpeedToWholeVideo(_ id: String) -> Bool {
    guard let r = speedRanges.first(where: { $0.id == id }) else { return false }
    return totalDurationMs <= lengthFitting(room: EditorLimits.maxTotalMs - totalDurationMs, speed: r.speed)
  }

  /// Stretches range `id` over the whole Ad — the old whole-video slow motion.
  func applySpeedToWholeVideo(_ id: String) {
    guard canApplySpeedToWholeVideo(id), let r = speedRanges.first(where: { $0.id == id }) else { return }
    commitSpeedRanges([SpeedRange(id: id, startMs: 0, endMs: totalDurationMs, speed: r.speed)], startAt: 0)
    selectedSpeedRangeId = id
  }

  func removeSpeedRange(_ id: String) {
    guard let r = speedRanges.first(where: { $0.id == id }) else { return }
    if selectedSpeedRangeId == id { selectedSpeedRangeId = nil }
    commitSpeedRanges(speedRanges.filter { $0.id != id }, startAt: r.startMs)
  }

  private func commitSpeedRanges(_ ranges: [SpeedRange], startAt: Int64) {
    speedRanges = ranges.sorted { $0.startMs < $1.startMs }
    dropStaleSpeedSelection()
    clampMusicToTimeline()
    clampOverlaysToTimeline()
    rebuild(resumeAtSourceMs: max(0, startAt - 500), play: isPlaying)
  }

  private func dropStaleSpeedSelection() {
    if let id = selectedSpeedRangeId, !speedRanges.contains(where: { $0.id == id }) { selectedSpeedRangeId = nil }
  }

  /// Captions/stickers are OUTPUT time: keep them inside a shorter Ad.
  private func clampOverlaysToTimeline() {
    let total = outputDurationMs
    func clamp(_ s: Int64, _ e: Int64) -> (Int64, Int64) {
      let start = min(max(s, 0), max(total - 300, 0))
      return (start, min(max(e, start + 300), max(total, start + 300)))
    }
    for i in textLayers.indices {
      let (s, e) = clamp(textLayers[i].startMs, textLayers[i].endMs)
      if s != textLayers[i].startMs || e != textLayers[i].endMs {
        textLayers[i].startMs = s
        textLayers[i].endMs = e
      }
    }
    for i in stickerLayers.indices {
      let (s, e) = clamp(stickerLayers[i].startMs, stickerLayers[i].endMs)
      if s != stickerLayers[i].startMs || e != stickerLayers[i].endMs {
        stickerLayers[i].startMs = s
        stickerLayers[i].endMs = e
      }
    }
  }

  func showNotice(_ text: String) {
    notice = text
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      if self?.notice == text { self?.notice = nil }
    }
  }

  func changeFilter(_ filter: VideoFilter) {
    guard filter != videoFilter else { return }
    videoFilter = filter
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: true)
  }

  // MARK: Text

  /// Player position right now, OUTPUT time (read per frame by the caption overlay).
  func currentOutputMs() -> Int64 {
    let seconds = CMTimeGetSeconds(player.currentTime())
    return seconds.isFinite ? Int64(max(0, seconds) * 1000) : 0
  }

  func seekToOutput(_ outMs: Int64) {
    seekToGlobal(toSourceMs(outMs))
  }

  @discardableResult
  func addText() -> TextLayer {
    pause()
    let total = max(outputDurationMs, 500)
    let now = min(max(currentOutputMs(), 0), total)
    let start = total - now < 1_000 ? max(total - 3_000, 0) : now
    var layer = TextLayer()
    layer.text = tr("Your text")
    layer.startMs = start
    layer.endMs = min(total, start + 3_000)
    textLayers.append(layer)
    selectedTextId = layer.id
    return layer
  }

  func updateText(_ layer: TextLayer) {
    guard let i = textLayers.firstIndex(where: { $0.id == layer.id }) else { return }
    textLayers[i] = layer
  }

  func removeText(_ id: String) {
    textLayers.removeAll { $0.id == id }
    if selectedTextId == id { selectedTextId = nil }
  }

  func removeTextIfBlank(_ id: String) {
    if let layer = textLayers.first(where: { $0.id == id }),
       layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      removeText(id)
    }
  }

  /// Timeline drag of a caption's or sticker's timing, clamped to the Ad (OUTPUT time), at least 300ms long.
  func setOverlayTiming(_ id: String, startMs: Int64, endMs: Int64) {
    let total = outputDurationMs
    let s = min(max(startMs, 0), max(total - 300, 0))
    let e = min(max(endMs, s + 300), max(total, s + 300))
    if let i = textLayers.firstIndex(where: { $0.id == id }) {
      textLayers[i].startMs = s
      textLayers[i].endMs = e
    }
    if let i = stickerLayers.firstIndex(where: { $0.id == id }) {
      stickerLayers[i].startMs = s
      stickerLayers[i].endMs = e
    }
    // A sound plays its whole length: only its start moves. It's part of the
    // composition, so the preview is rebuilt.
    if let i = soundLayers.firstIndex(where: { $0.id == id }) {
      soundLayers[i].startMs = s
      rebuild(resumeAtSourceMs: currentSourcePosition(), play: false)
    }
  }

  // MARK: Sound effects

  @discardableResult
  func addSound(_ def: SfxDef) -> SoundLayer {
    pause()
    let total = outputDurationMs
    let now = min(max(currentOutputMs(), 0), total)
    // Exactly at the playhead; a tail past the Ad's end is cut (same as Android).
    let layer = SoundLayer(sfxId: def.id, startMs: min(now, max(total - 100, 0)))
    soundLayers.append(layer)
    selectedTextId = layer.id
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: false)
    return layer
  }

  func updateSound(_ layer: SoundLayer) {
    guard let i = soundLayers.firstIndex(where: { $0.id == layer.id }) else { return }
    soundLayers[i] = layer
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: false)
  }

  func removeSound(_ id: String) {
    soundLayers.removeAll { $0.id == id }
    if selectedTextId == id { selectedTextId = nil }
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: false)
  }

  @discardableResult
  func addSticker(_ def: StickerDef) -> StickerLayer {
    pause()
    let total = max(outputDurationMs, 500)
    let now = min(max(currentOutputMs(), 0), total)
    let start = total - now < 1_000 ? max(total - 3_000, 0) : now
    // Staggered a little so several stickers don't land exactly on top of each other.
    let n = stickerLayers.count % 5
    var layer = StickerLayer(stickerId: def.id)
    layer.x = 0.5 + Double(n - 2) * 0.06
    layer.y = 0.32 + Double(n % 2) * 0.05
    layer.startMs = start
    layer.endMs = min(total, start + 3_000)
    stickerLayers.append(layer)
    selectedTextId = layer.id
    return layer
  }

  func updateSticker(_ layer: StickerLayer) {
    guard let i = stickerLayers.firstIndex(where: { $0.id == layer.id }) else { return }
    stickerLayers[i] = layer
  }

  func removeSticker(_ id: String) {
    stickerLayers.removeAll { $0.id == id }
    if selectedTextId == id { selectedTextId = nil }
  }

  // MARK: Thumbnails

  private func generateThumbnails() {
    let paths = clips.map(\.path).filter { thumbnails[$0] == nil }
    guard !paths.isEmpty else { return }
    Task.detached(priority: .utility) {
      for path in paths {
        let frames = Self.extractThumbnails(path: path)
        await MainActor.run { [weak self] in self?.thumbnails[path] = frames }
      }
    }
  }

  nonisolated private static func extractThumbnails(path: String) -> [ThumbnailFrame] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 160, height: 284)
    let totalMs = Int64(CMTimeGetSeconds(asset.duration) * 1000)
    guard totalMs > 0 else { return [] }
    return (0..<10).compactMap { i in
      let ms = totalMs * Int64(i) / 10
      guard let cg = try? generator.copyCGImage(at: CMTime(value: ms, timescale: 1000), actualTime: nil) else {
        return nil
      }
      return ThumbnailFrame(sourceMs: ms, image: UIImage(cgImage: cg))
    }
  }

  /// Picker thumbnails: each effect applied to a frame of the first clip, through the real kernels.
  func ensureFilterThumbnails() {
    guard filterThumbnails.isEmpty,
          let frames = clips.first.flatMap({ thumbnails[$0.path] }),
          let source = frames.isEmpty ? nil : frames[frames.count / 2].image.cgImage
    else { return }
    Task.detached(priority: .userInitiated) {
      let context = CIContext()
      var base = CIImage(cgImage: source)
      let scale = 72 / base.extent.width
      base = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      base = base.transformed(by: CGAffineTransform(translationX: -base.extent.minX, y: -base.extent.minY))
      var result: [VideoFilter: UIImage] = [:]
      for filter in VideoFilter.allCases {
        let out = AdGagRenderer.applyFilter(filter, to: base, timeSeconds: 0.37)
        if let cg = context.createCGImage(out, from: base.extent) {
          result[filter] = UIImage(cgImage: cg)
        }
      }
      let rendered = result
      await MainActor.run { [weak self] in self?.filterThumbnails = rendered }
    }
  }

  // MARK: Export

  func export(to outputURL: URL, completion: @escaping (String?, Int64) -> Void) {
    player.pause()
    exportError = nil
    let built: BuiltComposition
    do {
      built = try EditorCompositionBuilder.build(state: sessionState(), includeText: true)
    } catch {
      exportError = error.localizedDescription
      return
    }
    guard let session = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality) else {
      exportError = tr("Couldn't start the export.")
      return
    }
    try? FileManager.default.removeItem(at: outputURL)
    session.outputURL = outputURL
    session.outputFileType = .mp4
    session.videoComposition = built.videoComposition
    session.audioMix = built.audioMix
    session.audioTimePitchAlgorithm = built.pitchAlgorithm
    session.shouldOptimizeForNetworkUse = true
    isExporting = true
    exportProgress = 0
    let durationMs = built.outputDurationMs

    Task { @MainActor [weak self] in
      while let self, self.isExporting {
        self.exportProgress = Double(session.progress)
        try? await Task.sleep(nanoseconds: 200_000_000)
      }
    }
    session.exportAsynchronously { [weak self] in
      let status = session.status
      let message = session.error?.localizedDescription
      Task { @MainActor in
        guard let self else { return }
        self.isExporting = false
        if status == .completed {
          completion(outputURL.path, durationMs)
        } else {
          self.exportError = message ?? tr("Export failed")
          completion(nil, 0)
        }
      }
    }
  }

  // MARK: Helpers

  private static func normalized(_ list: [TransitionSpec], clipCount: Int) -> [TransitionSpec] {
    (0..<max(clipCount - 1, 0)).map { $0 < list.count ? list[$0] : TransitionSpec() }
  }

  nonisolated static func durationMs(path: String) -> Int64? {
    let seconds = CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: path)).duration)
    guard seconds.isFinite, seconds > 0 else { return nil }
    return Int64(seconds * 1000)
  }
}
