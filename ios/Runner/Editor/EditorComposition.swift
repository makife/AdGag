import AVFoundation
import CoreImage
import UIKit

// The iOS counterpart of the Android preview/export pipeline — but here ONE
// pipeline serves both: the AVMutableComposition + AVMutableVideoComposition
// (custom compositor) + AVMutableAudioMix built below go into an AVPlayerItem
// for the live preview and into an AVAssetExportSession for the export, so
// the preview is exactly what gets exported (transitions, effects, slow
// motion, music mixed with the clips' own audio).
//
// Time model (same as Android): clip trims and speed ranges are SOURCE time;
// each slow-motion range of the composition is stretched by 1/speed, so
// everything the viewer sees — transitions, music placement, the 30s cap —
// is OUTPUT time (SpeedMap converts).

// MARK: - Kernels

enum AdGagKernels {
  private static var cache: [String: CIKernel] = [:]
  private static let lock = NSLock()
  private static let library: Data? = {
    guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else { return nil }
    return try? Data(contentsOf: url)
  }()

  /// The Core Image kernel for `filter` (AdGagFilters.metal), or nil for NONE / if loading failed.
  static func kernel(for filter: VideoFilter) -> CIKernel? {
    guard let name = filter.kernelName, let library else { return nil }
    lock.lock()
    defer { lock.unlock() }
    if let k = cache[name] { return k }
    guard let k = try? CIKernel(functionName: name, fromMetalLibraryData: library) else {
      NSLog("AdGag: couldn't load kernel %@", name)
      return nil
    }
    cache[name] = k
    return k
  }
}

// MARK: - Per-frame rendering

enum AdGagRenderer {
  /// Applies a look effect to an image whose extent starts at (0,0).
  static func applyFilter(_ filter: VideoFilter, to image: CIImage, timeSeconds: Double) -> CIImage {
    guard let kernel = AdGagKernels.kernel(for: filter) else { return image }
    let rect = image.extent
    let out = kernel.apply(
      extent: rect,
      roiCallback: { _, _ in rect },
      arguments: [image, CIVector(x: rect.width, y: rect.height), Float(timeSeconds)])
    return out ?? image
  }

  /// Rotation implied by a track's preferredTransform, as an image orientation.
  static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
    let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    switch (degrees + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  /// The user's clockwise quarter-turns, as an image orientation.
  static func orientation(forUserRotation degrees: Int) -> CGImagePropertyOrientation {
    switch (degrees % 360 + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  static func render(source: CIImage, instruction: AdGagInstruction, renderSize: CGSize,
                     compositionTime: CMTime) -> CIImage {
    let renderRect = CGRect(origin: .zero, size: renderSize)
    let black = CIImage(color: .black).cropped(to: renderRect)

    // 1. Upright: the clip's own recorded orientation, then the user's rotation.
    var image = source
      .oriented(orientation(for: instruction.preferredTransform))
      .oriented(orientation(forUserRotation: instruction.userRotation))
    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

    // 2. Fit into the render size (clips can differ in size/orientation).
    let scale = min(renderSize.width / image.extent.width, renderSize.height / image.extent.height)
    image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    image = image.transformed(by: CGAffineTransform(
      translationX: (renderSize.width - image.extent.width) / 2 - image.extent.minX,
      y: (renderSize.height - image.extent.height) / 2 - image.extent.minY))
    image = image.composited(over: black).cropped(to: renderRect)

    // 3. Look effect — before the transition, matching Android.
    let seconds = CMTimeGetSeconds(compositionTime)
    image = applyFilter(instruction.filter, to: image, timeSeconds: seconds.isFinite ? seconds : 0)

    // 4. Transition pose (OUTPUT time).
    let localMs = Int64(max(0, CMTimeGetSeconds(CMTimeSubtract(compositionTime, instruction.timeRange.start))) * 1000)
    let pose = TransitionMath.clipPose(entry: instruction.entry, exit: instruction.exit,
                                       keptMs: instruction.keptOutMs, localMs: localMs)
    if pose.scale != 1 || pose.rotationDegrees != 0 || pose.translateX != 0 || pose.translateY != 0 {
      let cx = renderSize.width / 2
      let cy = renderSize.height / 2
      var t = CGAffineTransform(translationX: -cx, y: -cy)
      t = t.concatenating(CGAffineTransform(scaleX: pose.scale, y: pose.scale))
      // Pose rotation is screen-clockwise; Core Image is y-up.
      t = t.concatenating(CGAffineTransform(rotationAngle: -pose.rotationDegrees * .pi / 180))
      t = t.concatenating(CGAffineTransform(translationX: cx, y: cy))
      // Pose y is screen-down; Core Image y is up.
      t = t.concatenating(CGAffineTransform(translationX: pose.translateX * renderSize.width,
                                            y: -pose.translateY * renderSize.height))
      image = image.transformed(by: t).composited(over: black).cropped(to: renderRect)
    }
    if pose.brightness < 1 {
      let b = CGFloat(pose.brightness)
      image = image.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
      ]).cropped(to: renderRect)
    }

    // 5. Captions — composition level, so transitions never move them (as on Android).
    if let overlay = instruction.textOverlay,
       let text = overlay.image(size: renderSize, tMs: Int64((seconds.isFinite ? seconds : 0) * 1000)) {
      image = text.composited(over: image).cropped(to: renderRect)
    }
    return image
  }
}

// MARK: - Video composition instruction + compositor

/// One instruction per clip: which track, how its frames are oriented, and
/// the transitions/effect to apply over its output time range.
final class AdGagInstruction: NSObject, AVVideoCompositionInstructionProtocol {
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = true
  let requiredSourceTrackIDs: [NSValue]?
  let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

  let trackID: CMPersistentTrackID
  let preferredTransform: CGAffineTransform
  let userRotation: Int
  let entry: TransitionSpec?
  let exit: TransitionSpec?
  let keptOutMs: Int64
  let filter: VideoFilter
  /// Captions, drawn over everything (export only — the preview draws them in SwiftUI so edits are instant).
  let textOverlay: TextOverlayRenderer?

  init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, preferredTransform: CGAffineTransform,
       userRotation: Int, entry: TransitionSpec?, exit: TransitionSpec?, keptOutMs: Int64, filter: VideoFilter,
       textOverlay: TextOverlayRenderer?) {
    self.timeRange = timeRange
    self.trackID = trackID
    self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
    self.preferredTransform = preferredTransform
    self.userRotation = userRotation
    self.entry = entry
    self.exit = exit
    self.keptOutMs = keptOutMs
    self.filter = filter
    self.textOverlay = textOverlay
  }
}

final class AdGagCompositor: NSObject, AVVideoCompositing {
  private static let pixelAttributes: [String: any Sendable] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferMetalCompatibilityKey as String: true,
  ]
  let sourcePixelBufferAttributes: [String: any Sendable]? = AdGagCompositor.pixelAttributes
  let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = AdGagCompositor.pixelAttributes

  private let queue = DispatchQueue(label: "com.adgag.compositor")
  private let context = CIContext(options: [.cacheIntermediates: false])
  private let colorSpace = CGColorSpaceCreateDeviceRGB()

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    queue.async { [context, colorSpace] in
      autoreleasepool {
        guard let instruction = request.videoCompositionInstruction as? AdGagInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let output = request.renderContext.newPixelBuffer()
        else {
          request.finish(with: NSError(domain: "AdGagCompositor", code: 1, userInfo: nil))
          return
        }
        let size = request.renderContext.size
        let image = AdGagRenderer.render(source: CIImage(cvPixelBuffer: source), instruction: instruction,
                                         renderSize: size, compositionTime: request.compositionTime)
        context.render(image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: output)
      }
    }
  }

  func cancelAllPendingVideoCompositionRequests() {}
}

// MARK: - Building the composition

struct BuiltComposition {
  let asset: AVMutableComposition
  let videoComposition: AVMutableVideoComposition
  let audioMix: AVMutableAudioMix
  /// With music re-timed, keep its pitch; otherwise let slow motion lower the pitch like Android's.
  let pitchAlgorithm: AVAudioTimePitchAlgorithm
  let outputDurationMs: Int64
  /// Width / height of the rendered frame — the rectangle captions are laid out in.
  let renderAspect: Double
}

enum EditorCompositionBuilder {
  static func ms(_ value: Int64) -> CMTime { CMTime(value: value, timescale: 1000) }

  /// Each play of the selected music part: (OUTPUT start ms, length ms) — same as Android's musicRepetitions().
  static func musicRepetitions(state: EditorSessionState, outputDurationMs: Int64) -> [(Int64, Int64)] {
    let unit = state.musicPlayDurationMs
    guard state.musicOriginalPath != nil, unit > 0 else { return [] }
    let covered = state.musicLoop ? max(outputDurationMs - state.musicStartOffsetMs, unit) : unit
    let end = state.musicStartOffsetMs + covered
    var result: [(Int64, Int64)] = []
    var start = state.musicStartOffsetMs
    while start < end && result.count < 200 {
      let len = min(unit, end - start)
      if len < 100 && !result.isEmpty { break }
      result.append((start, len))
      start += unit
    }
    return result
  }

  /// `includeText`: burn the captions in (export). The preview leaves them out and draws them itself.
  static func build(state: EditorSessionState, includeText: Bool = false) throws -> BuiltComposition {
    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid),
          let clipAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw NSError(domain: "AdGag", code: 10, userInfo: [NSLocalizedDescriptionKey: "Couldn't create tracks"]) }

    var cursor = CMTime.zero
    var clipStarts: [CMTime] = []
    var transforms: [CGAffineTransform] = []
    var firstDisplaySize = CGSize(width: 1080, height: 1920)
    var hasClipAudio = false

    for (index, clip) in state.clips.enumerated() {
      let asset = AVURLAsset(url: URL(fileURLWithPath: clip.path))
      guard let sourceVideo = asset.tracks(withMediaType: .video).first else { continue }
      let range = CMTimeRange(start: ms(clip.trimStartMs), duration: ms(clip.keptDurationMs))
      try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
      if let sourceAudio = asset.tracks(withMediaType: .audio).first {
        try clipAudioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
        hasClipAudio = true
      }
      clipStarts.append(cursor)
      transforms.append(sourceVideo.preferredTransform)
      if index == 0 {
        let natural = sourceVideo.naturalSize
        let rotated = AdGagRenderer.orientation(for: sourceVideo.preferredTransform)
        var size = (rotated == .right || rotated == .left) ? CGSize(width: natural.height, height: natural.width) : natural
        if state.rotationDegrees % 180 == 90 { size = CGSize(width: size.height, height: size.width) }
        firstDisplaySize = CGSize(width: (Int(size.width) / 2) * 2, height: (Int(size.height) / 2) * 2)
      }
      cursor = CMTimeAdd(cursor, range.duration)
    }
    let sourceTotal = cursor
    guard sourceTotal > .zero else {
      throw NSError(domain: "AdGag", code: 11, userInfo: [NSLocalizedDescriptionKey: "No playable clips"])
    }

    // Slow motion: stretch each speed range (video + the clips' own audio).
    // Last range first, so stretching one never moves the ones still to do.
    let sourceTotalMs = Int64((CMTimeGetSeconds(sourceTotal) * 1000).rounded())
    let ranges = state.speedRanges
      .filter { $0.lengthMs > 0 && $0.startMs < sourceTotalMs }
      .sorted { $0.startMs > $1.startMs }
    for r in ranges {
      let length = min(r.endMs, sourceTotalMs) - r.startMs
      guard length > 0 else { continue }
      let span = CMTimeRange(start: ms(r.startMs), duration: ms(length))
      let stretched = CMTimeMultiplyByFloat64(ms(length), multiplier: 1 / r.speed)
      videoTrack.scaleTimeRange(span, toDuration: stretched)
      if hasClipAudio { clipAudioTrack.scaleTimeRange(span, toDuration: stretched) }
    }
    let outputTotal = videoTrack.timeRange.end
    let outputDurationMs = Int64((CMTimeGetSeconds(outputTotal) * 1000).rounded())
    let map = SpeedMap(state.speedRanges)

    let textOverlay: TextOverlayRenderer? = includeText
      ? { let r = TextOverlayRenderer(layers: state.textLayers, stickers: state.stickerLayers); return r.isEmpty ? nil : r }()
      : nil

    // One instruction per clip, tiling the whole output timeline exactly.
    var instructions: [AdGagInstruction] = []
    let outStarts = clipStarts.map { ms(map.toOutput(Int64((CMTimeGetSeconds($0) * 1000).rounded()))) }
    for i in clipStarts.indices {
      let start = i == 0 ? CMTime.zero : outStarts[i]
      let end = i == clipStarts.count - 1 ? outputTotal : outStarts[i + 1]
      let keptOut = Int64((CMTimeGetSeconds(CMTimeSubtract(end, start)) * 1000).rounded())
      instructions.append(AdGagInstruction(
        timeRange: CMTimeRange(start: start, end: end),
        trackID: videoTrack.trackID,
        preferredTransform: transforms[i],
        userRotation: state.rotationDegrees,
        entry: i > 0 && i - 1 < state.transitions.count ? state.transitions[i - 1] : nil,
        exit: i < state.transitions.count ? state.transitions[i] : nil,
        keptOutMs: keptOut,
        filter: state.videoFilter,
        textOverlay: textOverlay))
    }

    let videoComposition = AVMutableVideoComposition()
    videoComposition.customVideoCompositorClass = AdGagCompositor.self
    videoComposition.renderSize = firstDisplaySize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = instructions

    // Audio: the clips' own sound (muted = volume 0) + the music, if any.
    var mixParameters: [AVMutableAudioMixInputParameters] = []
    let clipParams = AVMutableAudioMixInputParameters(track: clipAudioTrack)
    clipParams.setVolume(state.isMuted ? 0 : 1, at: .zero)
    mixParameters.append(clipParams)

    var musicRetimed = false
    let repetitions = musicRepetitions(state: state, outputDurationMs: outputDurationMs)
    if let musicPath = state.musicOriginalPath, !repetitions.isEmpty,
       let songTrack = AVURLAsset(url: URL(fileURLWithPath: musicPath)).tracks(withMediaType: .audio).first,
       let musicTrack = composition.addMutableTrack(withMediaType: .audio,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid) {
      // Music placement is in the re-timed song's time (song / musicSpeed),
      // like Android's baked file; here the re-timing is a time scale.
      let musicSpeed = state.musicSpeed
      musicRetimed = musicSpeed != 1
      for (startOut, lenOut) in repetitions {
        let sourceStart = CMTimeMultiplyByFloat64(ms(state.musicSourceStartMs), multiplier: musicSpeed)
        let sourceDuration = CMTimeMultiplyByFloat64(ms(lenOut), multiplier: musicSpeed)
        let at = ms(startOut)
        try musicTrack.insertTimeRange(CMTimeRange(start: sourceStart, duration: sourceDuration), of: songTrack, at: at)
        if musicRetimed {
          musicTrack.scaleTimeRange(CMTimeRange(start: at, duration: sourceDuration), toDuration: ms(lenOut))
        }
      }
      let covered = repetitions.reduce(Int64(0)) { $0 + $1.1 }
      let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)
      let start = state.musicStartOffsetMs
      musicParams.setVolume(1, at: .zero)
      if state.musicFadeInMs > 0 {
        let d = min(state.musicFadeInMs, covered)
        musicParams.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                                  timeRange: CMTimeRange(start: ms(start), duration: ms(d)))
      }
      if state.musicFadeOutMs > 0 {
        let d = min(state.musicFadeOutMs, covered)
        musicParams.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                                  timeRange: CMTimeRange(start: ms(start + covered - d), duration: ms(d)))
      }
      mixParameters.append(musicParams)
    }

    // Sound effects: effects that don't overlap share a track; overlapping
    // ones get another. Each is cut at the Ad's end.
    var lanes: [[(SoundLayer, SfxDef)]] = []
    let placed = state.soundLayers
      .compactMap { l in SfxStore.shared.byId(l.sfxId).map { (l, $0) } }
      .filter { $0.0.startMs < outputDurationMs }
      .sorted { $0.0.startMs < $1.0.startMs }
    for p in placed {
      if let i = lanes.firstIndex(where: { lane in lane.last.map { $0.0.startMs + $0.1.durationMs <= p.0.startMs } ?? true }) {
        lanes[i].append(p)
      } else {
        lanes.append([p])
      }
    }
    for lane in lanes {
      guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { continue }
      for (layer, def) in lane {
        guard let url = SfxStore.shared.url(def),
              let source = AVURLAsset(url: url).tracks(withMediaType: .audio).first else { continue }
        let len = min(def.durationMs, outputDurationMs - layer.startMs)
        try? track.insertTimeRange(CMTimeRange(start: .zero, duration: ms(len)), of: source, at: ms(layer.startMs))
      }
      let params = AVMutableAudioMixInputParameters(track: track)
      params.setVolume(1, at: .zero)
      mixParameters.append(params)
    }

    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = mixParameters

    return BuiltComposition(
      asset: composition, videoComposition: videoComposition, audioMix: audioMix,
      pitchAlgorithm: musicRetimed ? .spectral : .varispeed, outputDurationMs: outputDurationMs,
      renderAspect: Double(firstDisplaySize.width / max(firstDisplaySize.height, 1)))
  }
}
