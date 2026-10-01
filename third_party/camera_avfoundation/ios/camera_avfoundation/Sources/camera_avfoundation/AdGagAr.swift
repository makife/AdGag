// ADGAG PATCH — live AR face effects (not part of upstream camera_avfoundation).
// See PATCH_NOTES.md. iOS twin of third_party/camera_android_camerax's
// AdGagAr.kt / ArEffects.kt.

import CoreGraphics
import CoreVideo
import Flutter
import Foundation
import Vision

/// Live AR on iOS: this plugin records by appending the SAME pixel buffers
/// it shows as the preview (AVCaptureVideoDataOutput -> AVAssetWriter), so
/// drawing the effect into each buffer in captureOutput — before it is
/// published to the preview texture and appended to the writer — puts the
/// identical picture in both. No rebind/reopen is ever needed: with no
/// effect picked [process] returns at once.
///
/// Faces: Vision face landmarks, run synchronously on the capture queue on
/// every other frame (before anything is drawn into that frame), smoothed
/// per face. The buffers arrive upright for the device orientation (the
/// plugin sets the connection's videoOrientation; the front camera's is
/// mirrored), so Vision gets `.up` and its points map straight to buffer
/// pixels (after flipping Vision's bottom-left origin).
enum AdGagAr {
  private static let lock = NSLock()
  private static var _currentEffect: String?

  /// Effect to draw now (nil = nothing). Set from the platform thread, read on the capture queue.
  static var currentEffect: String? {
    lock.lock()
    defer { lock.unlock() }
    return _currentEffect
  }

  // Capture-queue state (process() always runs on the plugin's serial capture queue).
  private static var faces: [ArFace] = []
  private static var facesAt: Double = -1
  private static var frameIndex = 0
  private static let colorSpace = CGColorSpaceCreateDeviceRGB()

  static func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "adgag/ar", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setEffect":
        let id = (call.arguments as? [String: Any])?["id"] as? String
        lock.lock()
        _currentEffect = id
        lock.unlock()
        result(nil)
      case "isPipelineBound":
        // Always: every camera frame passes through process().
        result(true)
      case "previewInfo":
        // The preview needs no special transform on iOS.
        result(nil)
      case "lastError":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Called for every video frame on the capture queue.
  static func process(_ buffer: CVPixelBuffer, seconds: Double) {
    guard let effect = currentEffect else {
      if !faces.isEmpty { faces = [] }
      return
    }
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)

    frameIndex &+= 1
    if frameIndex % 2 == 0 || facesAt < 0 {
      detect(buffer, width: width, height: height, seconds: seconds)
    }
    guard !faces.isEmpty, abs(seconds - facesAt) < 0.5 else { return }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let base = CVPixelBufferGetBaseAddress(buffer),
      let ctx = CGContext(
        data: base, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return }
    // y down, like the Android canvas the artwork was written for.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    let t = CGFloat(seconds.truncatingRemainder(dividingBy: 100_000))
    for face in faces {
      ctx.saveGState()
      ctx.concatenate(face.localToBuffer())
      ArEffects.draw(ctx, id: effect, face: face, t: t)
      ctx.restoreGState()
    }
  }

  private static func detect(_ buffer: CVPixelBuffer, width: Int, height: Int, seconds: Double) {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return
    }
    let size = CGSize(width: width, height: height)
    var next: [ArFace] = []
    for observation in (request.results ?? []).prefix(3) {
      guard let raw = ArFace(observation, imageSize: size) else { continue }
      // Smooth against the nearest face of the previous detection.
      let previous = faces.min { $0.distance(to: raw) < $1.distance(to: raw) }
      if let p = previous, p.distance(to: raw) < raw.eyeDistance * 1.5 {
        next.append(p.lerp(raw, 0.55))
      } else {
        next.append(raw)
      }
    }
    faces = next
    facesAt = seconds
  }
}

/// One face in buffer pixels (y down). [localToBuffer] is the face frame
/// the artwork is drawn in: origin between the eyes, x: 1 = eye distance,
/// y: toward the mouth, 1 = the eye distance the face would show head-on
/// (so a turned head narrows effects instead of shrinking them).
struct ArFace {
  var leftEye: CGPoint
  var rightEye: CGPoint
  var nose: CGPoint
  /// Midpoint of the mouth corners (steady whether the mouth is open or not).
  var mouth: CGPoint
  var mouthBottom: CGPoint
  var leftCheek: CGPoint
  var rightCheek: CGPoint
  var yawDeg: CGFloat

  init?(_ o: VNFaceObservation, imageSize size: CGSize) {
    guard let lm = o.landmarks,
      let le = lm.leftEye.map({ Self.points($0, size) }), !le.isEmpty,
      let re = lm.rightEye.map({ Self.points($0, size) }), !re.isEmpty
    else { return nil }
    let box = CGRect(
      x: o.boundingBox.minX * size.width, y: (1 - o.boundingBox.maxY) * size.height,
      width: o.boundingBox.width * size.width, height: o.boundingBox.height * size.height)
    let l = Self.centroid(le)
    let r = Self.centroid(re)
    let nosePts = lm.nose.map { Self.points($0, size) } ?? []
    let nose = nosePts.isEmpty ? CGPoint(x: box.midX, y: box.midY) : Self.centroid(nosePts)
    let lips = lm.outerLips.map { Self.points($0, size) } ?? []
    let mouth: CGPoint
    let mouthBottom: CGPoint
    if lips.count >= 3 {
      // Corners = the extreme points along the eye line; bottom = farthest down the face.
      let ex = CGVector(dx: r.x - l.x, dy: r.y - l.y)
      let along = { (p: CGPoint) in p.x * ex.dx + p.y * ex.dy }
      let a = lips.min { along($0) < along($1) }!
      let b = lips.max { along($0) < along($1) }!
      mouth = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
      let down = CGVector(dx: -ex.dy, dy: ex.dx)  // perpendicular to the eye line
      let mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
      let sign: CGFloat = ((mouth.x - mid.x) * down.dx + (mouth.y - mid.y) * down.dy) >= 0 ? 1 : -1
      let depth = { (p: CGPoint) in sign * (p.x * down.dx + p.y * down.dy) }
      mouthBottom = lips.max { depth($0) < depth($1) }!
    } else {
      mouth = CGPoint(x: box.midX, y: box.maxY - box.height * 0.2)
      mouthBottom = mouth
    }
    self.leftEye = l
    self.rightEye = r
    self.nose = nose
    self.mouth = mouth
    self.mouthBottom = mouthBottom
    // Vision has no cheek landmarks: between the eye and the mouth corner, like Android's fallback.
    self.leftCheek = CGPoint(x: l.x + (mouth.x - l.x) * 0.3, y: l.y + (mouth.y - l.y) * 0.6)
    self.rightCheek = CGPoint(x: r.x + (mouth.x - r.x) * 0.3, y: r.y + (mouth.y - r.y) * 0.6)
    self.yawDeg = CGFloat(o.yaw?.doubleValue ?? 0) * 180 / .pi
  }

  private init(
    _ l: CGPoint, _ r: CGPoint, _ n: CGPoint, _ m: CGPoint, _ mb: CGPoint, _ lc: CGPoint,
    _ rc: CGPoint, _ yaw: CGFloat
  ) {
    leftEye = l
    rightEye = r
    nose = n
    mouth = m
    mouthBottom = mb
    leftCheek = lc
    rightCheek = rc
    yawDeg = yaw
  }

  private static func points(_ region: VNFaceLandmarkRegion2D, _ size: CGSize) -> [CGPoint] {
    region.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: size.height - $0.y) }
  }

  private static func centroid(_ pts: [CGPoint]) -> CGPoint {
    let n = CGFloat(pts.count)
    return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
  }

  var eyeDistance: CGFloat { max(1, hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)) }

  private var eyeMid: CGPoint { CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2) }

  func distance(to other: ArFace) -> CGFloat {
    hypot(eyeMid.x - other.eyeMid.x, eyeMid.y - other.eyeMid.y)
  }

  func lerp(_ to: ArFace, _ t: CGFloat) -> ArFace {
    func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    return ArFace(
      mix(leftEye, to.leftEye), mix(rightEye, to.rightEye), mix(nose, to.nose), mix(mouth, to.mouth),
      mix(mouthBottom, to.mouthBottom), mix(leftCheek, to.leftCheek), mix(rightCheek, to.rightCheek),
      yawDeg + (to.yawDeg - yawDeg) * t)
  }

  func localToBuffer() -> CGAffineTransform {
    let m = eyeMid
    let e = eyeDistance
    // The eye distance shrinks as the head turns; the face's height doesn't.
    let ey = e / min(1, max(0.55, cos(yawDeg * .pi / 180)))
    var dx = mouth.x - m.x
    var dy = mouth.y - m.y
    let dl = max(1e-3, hypot(dx, dy))
    dx /= dl
    dy /= dl
    // Right vector = down rotated -90°, so the frame is a pure rotation (no flip).
    let rx = dy
    let ry = -dx
    return CGAffineTransform(a: rx * e, b: ry * e, c: dx * ey, d: dy * ey, tx: m.x, ty: m.y)
  }

  /// [p] (buffer pixels) in this face's units.
  func toLocal(_ p: CGPoint) -> CGPoint { p.applying(localToBuffer().inverted()) }

  /// 0 = mouth closed … 1 = wide open (lip gap relative to the face).
  func mouthOpen() -> CGFloat {
    let corners = toLocal(mouth)
    let bottom = toLocal(mouthBottom)
    return min(1, max(0, (bottom.y - corners.y - 0.18) / 0.32))
  }
}
