import Foundation

// Mirror of android/.../editor/EditorModels.kt — same constants, same
// session JSON keys, so both platforms describe an edit the same way.

enum EditorLimits {
  /// Hard cap on the finished Ad (OUTPUT time) — Dart's VideoConstraints.max, the ads.duration_range CHECK.
  static let maxTotalMs: Int64 = 30_000
  /// Shortest clip worth adding; the "+" hides once less than this remains.
  static let minClipMs: Int64 = 1_500
  static let defaultTransitionMs: Int64 = 800
  static let minTransitionMs: Int64 = 200
  static let maxTransitionMs: Int64 = 2_000
  static let maxMusicFadeMs: Int64 = 5_000
  static let minTrimGapMs: Int64 = 500
  static let videoSpeedOptions: [Double] = [0.25, 0.5, 0.75, 1]
  static let musicSpeedOptions: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
}

/// One recorded clip. Trims are in this clip's own SOURCE time.
struct EditorClip: Codable, Equatable {
  var path: String
  var sourceDurationMs: Int64
  var trimStartMs: Int64
  var trimEndMs: Int64

  var keptDurationMs: Int64 { max(0, trimEndMs - trimStartMs) }
}

/// What happens at the boundary between two clips — see TransitionMath.
enum ClipTransition: String, Codable, CaseIterable {
  case NONE, FADE, FADE_OUT, DIP_TO_BLACK
  case SLIDE_FROM_RIGHT, SLIDE_FROM_LEFT, SLIDE_FROM_BOTTOM, SLIDE_FROM_TOP
  case ZOOM_IN, ZOOM_OUT, SPIN

  var label: String {
    switch self {
    case .NONE: return "Cut"
    case .FADE: return "Fade in"
    case .FADE_OUT: return "Fade out"
    case .DIP_TO_BLACK: return "Dip to black"
    case .SLIDE_FROM_RIGHT: return "Slide ←"
    case .SLIDE_FROM_LEFT: return "Slide →"
    case .SLIDE_FROM_BOTTOM: return "Slide ↑"
    case .SLIDE_FROM_TOP: return "Slide ↓"
    case .ZOOM_IN: return "Zoom in"
    case .ZOOM_OUT: return "Zoom out"
    case .SPIN: return "Spin"
    }
  }
}

struct TransitionSpec: Codable, Equatable {
  var type: ClipTransition = .NONE
  var durationMs: Int64 = EditorLimits.defaultTransitionMs
}

/// Whole-video look effects — implemented as Core Image Metal kernels in AdGagFilters.metal.
enum VideoFilter: String, Codable, CaseIterable {
  case NONE, BW, SEPIA, VINTAGE, COOL, WARM, VIVID, INVERT, FISHEYE, OLD_TV, STATIC, VHS
  case GLITCH, PIXELATE, MIRROR, FLOWERS, HEARTS, FILM, IVY, BALLOONS, STARS, CONFETTI

  var label: String {
    switch self {
    case .NONE: return "Original"
    case .BW: return "B&W"
    case .SEPIA: return "Sepia"
    case .VINTAGE: return "Vintage"
    case .COOL: return "Cool"
    case .WARM: return "Warm"
    case .VIVID: return "Vivid"
    case .INVERT: return "Negative"
    case .FISHEYE: return "Fisheye"
    case .OLD_TV: return "Old TV"
    case .STATIC: return "Static"
    case .VHS: return "VHS"
    case .GLITCH: return "Glitch"
    case .PIXELATE: return "Pixel"
    case .MIRROR: return "Mirror"
    case .FLOWERS: return "Flowers"
    case .HEARTS: return "Hearts"
    case .FILM: return "Film"
    case .IVY: return "Ivy"
    case .BALLOONS: return "Balloons"
    case .STARS: return "Stars"
    case .CONFETTI: return "Confetti"
    }
  }

  /// Name of the kernel function in AdGagFilters.metal.
  var kernelName: String? { self == .NONE ? nil : "adgag_" + rawValue.lowercased() }
}

/// Everything needed to rebuild the editor after it closes for another
/// recording. Same JSON keys as the Android EditorSessionState; opaque to Dart.
struct EditorSessionState: Codable {
  var clips: [EditorClip]
  var transitions: [TransitionSpec]
  var musicPath: String?
  var musicOriginalPath: String?
  var musicSpeed: Double
  var musicFadeInMs: Int64
  var musicFadeOutMs: Int64
  var musicLoop: Bool
  var musicStartOffsetMs: Int64
  var musicSourceStartMs: Int64
  var musicPlayDurationMs: Int64
  var rotationDegrees: Int
  var isMuted: Bool
  var videoSpeed: Double
  var videoFilter: VideoFilter
  /// Captions over the whole Ad (EditorText.swift), timed in OUTPUT time.
  var textLayers: [TextLayer] = []

  static func initial(clipPath: String, sourceDurationMs: Int64) -> EditorSessionState {
    EditorSessionState(
      clips: [EditorClip(path: clipPath, sourceDurationMs: sourceDurationMs, trimStartMs: 0,
                         trimEndMs: min(sourceDurationMs, EditorLimits.maxTotalMs))],
      transitions: [], musicPath: nil, musicOriginalPath: nil, musicSpeed: 1, musicFadeInMs: 0,
      musicFadeOutMs: 0, musicLoop: false, musicStartOffsetMs: 0, musicSourceStartMs: 0,
      musicPlayDurationMs: 0, rotationDegrees: 0, isMuted: false, videoSpeed: 1, videoFilter: .NONE)
  }

  func toJSON() -> String {
    let data = (try? JSONEncoder().encode(self)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  /// Tolerant decode: missing keys (older sessions) fall back to defaults.
  static func fromJSON(_ json: String) -> EditorSessionState? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let clipsRaw = obj["clips"] as? [[String: Any]] else { return nil }
    func int64(_ any: Any?) -> Int64 { (any as? NSNumber)?.int64Value ?? 0 }
    let clips = clipsRaw.map {
      EditorClip(path: $0["path"] as? String ?? "", sourceDurationMs: int64($0["sourceDurationMs"]),
                 trimStartMs: int64($0["trimStartMs"]), trimEndMs: int64($0["trimEndMs"]))
    }
    let transitions: [TransitionSpec] = (obj["transitions"] as? [Any] ?? []).map { entry in
      if let o = entry as? [String: Any] {
        let d = (o["durationMs"] as? NSNumber)?.int64Value ?? EditorLimits.defaultTransitionMs
        return TransitionSpec(type: ClipTransition(rawValue: o["type"] as? String ?? "") ?? .NONE,
                              durationMs: min(max(d, EditorLimits.minTransitionMs), EditorLimits.maxTransitionMs))
      }
      return TransitionSpec(type: ClipTransition(rawValue: entry as? String ?? "") ?? .NONE)
    }
    let musicPath = obj["musicPath"] as? String
    return EditorSessionState(
      clips: clips, transitions: transitions, musicPath: musicPath,
      musicOriginalPath: obj["musicOriginalPath"] as? String ?? musicPath,
      musicSpeed: (obj["musicSpeed"] as? NSNumber)?.doubleValue ?? 1,
      musicFadeInMs: int64(obj["musicFadeInMs"]), musicFadeOutMs: int64(obj["musicFadeOutMs"]),
      musicLoop: obj["musicLoop"] as? Bool ?? false,
      musicStartOffsetMs: int64(obj["musicStartOffsetMs"]),
      musicSourceStartMs: int64(obj["musicSourceStartMs"]),
      musicPlayDurationMs: int64(obj["musicPlayDurationMs"]),
      rotationDegrees: (obj["rotationDegrees"] as? NSNumber)?.intValue ?? 0,
      isMuted: obj["isMuted"] as? Bool ?? false,
      videoSpeed: (obj["videoSpeed"] as? NSNumber)?.doubleValue ?? 1,
      videoFilter: VideoFilter(rawValue: obj["videoFilter"] as? String ?? "") ?? .NONE,
      textLayers: (obj["textLayers"] as? [[String: Any]] ?? []).map(TextLayer.from))
  }
}

/// Mirror of the Kotlin TransitionMath: one definition used by the
/// compositor (preview AND export) and the picker thumbnails.
enum TransitionMath {
  struct Pose {
    var translateX: Double = 0   // fraction of width, x right
    var translateY: Double = 0   // fraction of height, y DOWN (screen convention)
    var scale: Double = 1
    var rotationDegrees: Double = 0
    var brightness: Double = 1   // 0 = black
  }

  static let identity = Pose()

  private static func easeOut(_ t: Double) -> Double {
    let inv = 1 - min(max(t, 0), 1)
    return 1 - inv * inv * inv
  }

  private static func entrancePose(_ type: ClipTransition, _ p: Double) -> Pose {
    let r = 1 - p
    switch type {
    case .NONE, .FADE_OUT: return identity
    case .FADE, .DIP_TO_BLACK: return Pose(brightness: p)
    case .SLIDE_FROM_RIGHT: return Pose(translateX: r)
    case .SLIDE_FROM_LEFT: return Pose(translateX: -r)
    case .SLIDE_FROM_BOTTOM: return Pose(translateY: r)
    case .SLIDE_FROM_TOP: return Pose(translateY: -r)
    case .ZOOM_IN: return Pose(scale: 0.5 + 0.5 * p)
    case .ZOOM_OUT: return Pose(scale: 1.6 - 0.6 * p)
    case .SPIN: return Pose(scale: 0.3 + 0.7 * p, rotationDegrees: -180 * r)
    }
  }

  private static func entranceMs(_ spec: TransitionSpec) -> Int64 {
    switch spec.type {
    case .NONE, .FADE_OUT: return 0
    case .DIP_TO_BLACK: return spec.durationMs / 2
    default: return spec.durationMs
    }
  }

  private static func exitMs(_ spec: TransitionSpec) -> Int64 {
    switch spec.type {
    case .FADE_OUT: return spec.durationMs
    case .DIP_TO_BLACK: return spec.durationMs / 2
    default: return 0
    }
  }

  /// A clip's pose at `localMs` into its kept part (`keptMs` long, OUTPUT time).
  static func clipPose(entry: TransitionSpec?, exit: TransitionSpec?, keptMs: Int64, localMs: Int64) -> Pose {
    var pose = identity
    if let entry {
      let d = min(entranceMs(entry), keptMs)
      if d > 0 && localMs >= 0 && localMs < d {
        pose = entrancePose(entry.type, easeOut(Double(localMs) / Double(d)))
      }
    }
    if let exit {
      let d = min(exitMs(exit), keptMs)
      let remaining = keptMs - localMs
      if d > 0 && remaining < d {
        let q = min(max(Double(remaining) / Double(d), 0), 1)
        pose.brightness *= q
      }
    }
    return pose
  }
}

/// The music's volume at `ms` into its covered span — same curve as Android's fadeGain().
func fadeGain(ms: Int64, fadeInMs: Int64, fadeOutMs: Int64, totalMs: Int64) -> Double {
  var g = 1.0
  if fadeInMs > 0 && ms < fadeInMs { g = min(g, Double(ms) / Double(fadeInMs)) }
  let remaining = totalMs - ms
  if fadeOutMs > 0 && remaining < fadeOutMs { g = min(g, Double(remaining) / Double(fadeOutMs)) }
  return min(max(g, 0), 1)
}

func formatSpeed(_ s: Double) -> String {
  s == s.rounded() ? "\(Int(s))x" : "\(s)x"
}

func formatClock(_ ms: Int64) -> String {
  let total = ms / 1000
  return String(format: "%d:%02d", total / 60, total % 60)
}
