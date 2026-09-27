import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Native iOS editor state — the counterpart of the Android EditorViewModel,
/// with the same operations and the same time model:
/// - clip SOURCE time: trims (and the clip strip);
/// - OUTPUT time (source / videoSpeed): the 30s cap, music placement,
///   transitions. The player's own time is OUTPUT time.
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
  @Published private(set) var videoSpeed: Double
  @Published private(set) var videoFilter: VideoFilter

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
    videoSpeed = state.videoSpeed
    videoFilter = state.videoFilter

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
  var outputDurationMs: Int64 { Int64(Double(totalDurationMs) / videoSpeed) }
  var sourceBudgetMs: Int64 { Int64(Double(EditorLimits.maxTotalMs) * videoSpeed) }
  var remainingMs: Int64 { max(0, sourceBudgetMs - totalDurationMs) }
  var canAddClip: Bool { remainingMs >= EditorLimits.minClipMs }
  func canUseVideoSpeed(_ speed: Double) -> Bool { Int64(Double(totalDurationMs) / speed) <= EditorLimits.maxTotalMs }
  var hasMusic: Bool { musicOriginalPath != nil && musicDurationMs != nil }
  var musicCoveredMs: Int64 {
    musicLoop && musicPlayDurationMs > 0
      ? max(outputDurationMs - musicStartOffsetMs, musicPlayDurationMs)
      : musicPlayDurationMs
  }
  /// Playhead on the clip strip, SOURCE time.
  var globalPositionMs: Int64 { Int64(Double(positionOutMs) * videoSpeed) }

  func clipStartMs(_ index: Int) -> Int64 { clips.prefix(index).reduce(0) { $0 + $1.keptDurationMs } }

  func sessionState() -> EditorSessionState {
    EditorSessionState(
      clips: clips, transitions: transitions, musicPath: musicOriginalPath, musicOriginalPath: musicOriginalPath,
      musicSpeed: musicSpeed, musicFadeInMs: musicFadeInMs, musicFadeOutMs: musicFadeOutMs, musicLoop: musicLoop,
      musicStartOffsetMs: musicStartOffsetMs, musicSourceStartMs: musicSourceStartMs,
      musicPlayDurationMs: musicPlayDurationMs, rotationDegrees: rotationDegrees, isMuted: isMuted,
      videoSpeed: videoSpeed, videoFilter: videoFilter)
  }

  // MARK: Playback

  func togglePlayPause() {
    if player.timeControlStatus == .playing { player.pause() } else { player.play() }
  }

  func pause() { player.pause() }

  /// Seeks to a SOURCE-time position on the clip strip.
  func seekToGlobal(_ sourceMs: Int64) {
    let clamped = min(max(sourceMs, 0), max(totalDurationMs - 1, 0))
    let outMs = Int64(Double(clamped) / videoSpeed)
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
    let others = totalDurationMs - clip.keptDurationMs
    let maxKept = max(sourceBudgetMs - others, EditorLimits.minClipMs)
    let start = min(max(startMs, 0), clip.sourceDurationMs)
    let end = min(max(endMs, start), min(clip.sourceDurationMs, start + maxKept))
    clips[index].trimStartMs = start
    clips[index].trimEndMs = end
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
    clips.remove(at: index)
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
    let lead = Int64(Double(max(1000, transitions[boundary].durationMs + 500)) * videoSpeed)
    return max(0, clipStartMs(boundary + 1) - lead)
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
        throw NSError(domain: "AdGag", code: 20, userInfo: [NSLocalizedDescriptionKey: "Couldn't read that audio file."])
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

  func changeVideoSpeed(_ speed: Double) {
    guard speed != videoSpeed, canUseVideoSpeed(speed) else { return }
    videoSpeed = speed
    clampMusicToTimeline()
    rebuild(resumeAtSourceMs: 0, play: true)
  }

  func changeFilter(_ filter: VideoFilter) {
    guard filter != videoFilter else { return }
    videoFilter = filter
    rebuild(resumeAtSourceMs: currentSourcePosition(), play: true)
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
      built = try EditorCompositionBuilder.build(state: sessionState())
    } catch {
      exportError = error.localizedDescription
      return
    }
    guard let session = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality) else {
      exportError = "Couldn't start the export."
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
          self.exportError = message ?? "Export failed"
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
