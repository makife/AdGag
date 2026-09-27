import CoreGraphics
import CoreImage
import CoreText
import Foundation
import UIKit

// Mirror of android/.../editor/TextLayers.kt + TextRenderer.kt: captions over
// the whole Ad, same model, same JSON keys, same fonts, styles and motions.
// One renderer (Core Graphics, per glyph) draws them for the live preview
// (SwiftUI Canvas) and the export (the compositor's text overlay), so what's
// previewed is exported. Geometry is resolution-independent: position = the
// block's centre as a frame fraction, size = a fraction of the frame HEIGHT.

// MARK: - Model

enum TextLayerAlign: String, Codable, CaseIterable {
  case LEFT, CENTER, RIGHT
  var label: String { String(rawValue.prefix(1)) + rawValue.dropFirst().lowercased() }
}

enum TextStyleEffect: String, Codable, CaseIterable {
  case NONE, OUTLINE, SHADOW, GLOW, NEON, BOX, PILL, HIGHLIGHT, HOLLOW, EXTRUDE, REFLECTION
  case COMIC, RETRO, GLITCH, GOLD, SUNSET, OCEAN, RAINBOW_FILL

  var label: String {
    switch self {
    case .NONE: return "Plain"
    case .OUTLINE: return "Outline"
    case .SHADOW: return "Shadow"
    case .GLOW: return "Glow"
    case .NEON: return "Neon"
    case .BOX: return "Box"
    case .PILL: return "Pill"
    case .HIGHLIGHT: return "Marker"
    case .HOLLOW: return "Hollow"
    case .EXTRUDE: return "3D"
    case .REFLECTION: return "Mirror"
    case .COMIC: return "Comic"
    case .RETRO: return "Retro"
    case .GLITCH: return "Glitch"
    case .GOLD: return "Gold"
    case .SUNSET: return "Sunset"
    case .OCEAN: return "Ocean"
    case .RAINBOW_FILL: return "Rainbow"
    }
  }
}

enum TextAnimation: String, Codable, CaseIterable {
  case NONE, FADE, POP, BOUNCE, ZOOM, SPIN, SLIDE_UP, SLIDE_DOWN, SLIDE_LEFT, SLIDE_RIGHT
  case TYPEWRITER, RISE, DROP, WAVE, JUMP, SHAKE, PULSE, SWING, FLICKER, RAINBOW

  var label: String {
    switch self {
    case .NONE: return "None"
    case .FADE: return "Fade"
    case .POP: return "Pop"
    case .BOUNCE: return "Bounce"
    case .ZOOM: return "Zoom"
    case .SPIN: return "Spin"
    case .SLIDE_UP: return "Slide up"
    case .SLIDE_DOWN: return "Slide down"
    case .SLIDE_LEFT: return "Slide left"
    case .SLIDE_RIGHT: return "Slide right"
    case .TYPEWRITER: return "Typewriter"
    case .RISE: return "Rise"
    case .DROP: return "Drop in"
    case .WAVE: return "Wave"
    case .JUMP: return "Jump"
    case .SHAKE: return "Shake"
    case .PULSE: return "Pulse"
    case .SWING: return "Swing"
    case .FLICKER: return "Flicker"
    case .RAINBOW: return "Rainbow"
    }
  }
}

/// Colours are ARGB in a signed 32-bit int — exactly what the Kotlin side stores.
struct TextLayer: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var text: String = "Your text"
  var fontId: String = TextFonts.defaultId
  var sizeFrac: Double = 0.06
  var color: Int32 = -1
  /// Second colour: outline / shadow / glow / box / 3D depth, depending on style.
  var accentColor: Int32 = Int32(bitPattern: 0xFFFF_3D9E)
  var opacity: Double = 1
  var style: TextStyleEffect = .OUTLINE
  var animation: TextAnimation = .POP
  var align: TextLayerAlign = .CENTER
  var letterSpacing: Double = 0
  var x: Double = 0.5
  var y: Double = 0.45
  var rotationDeg: Double = 0
  var scale: Double = 1
  var startMs: Int64 = 0
  var endMs: Int64 = 3_000

  /// Tolerant decode from a JSONSerialization dictionary (session JSON written by either platform).
  static func from(_ o: [String: Any]) -> TextLayer {
    func d(_ key: String, _ fallback: Double) -> Double { (o[key] as? NSNumber)?.doubleValue ?? fallback }
    func i64(_ key: String, _ fallback: Int64) -> Int64 { (o[key] as? NSNumber)?.int64Value ?? fallback }
    func i32(_ key: String, _ fallback: Int32) -> Int32 {
      guard let n = o[key] as? NSNumber else { return fallback }
      return Int32(truncatingIfNeeded: n.int64Value)
    }
    var t = TextLayer()
    t.id = o["id"] as? String ?? UUID().uuidString
    t.text = o["text"] as? String ?? ""
    t.fontId = o["fontId"] as? String ?? TextFonts.defaultId
    t.sizeFrac = d("sizeFrac", 0.06)
    t.color = i32("color", -1)
    t.accentColor = i32("accentColor", Int32(bitPattern: 0xFFFF_3D9E))
    t.opacity = d("opacity", 1)
    t.style = TextStyleEffect(rawValue: o["style"] as? String ?? "") ?? .NONE
    t.animation = TextAnimation(rawValue: o["animation"] as? String ?? "") ?? .NONE
    t.align = TextLayerAlign(rawValue: o["align"] as? String ?? "") ?? .CENTER
    t.letterSpacing = d("letterSpacing", 0)
    t.x = d("x", 0.5)
    t.y = d("y", 0.45)
    t.rotationDeg = d("rotationDeg", 0)
    t.scale = d("scale", 1)
    t.startMs = i64("startMs", 0)
    t.endMs = i64("endMs", 3_000)
    return t
  }
}

struct TextFont {
  let id: String
  let label: String
  let file: String
  var weight: Int? = nil
}

/// The bundled fonts (Editor/AdGagFonts — the same Google Fonts files as
/// Android, OFL/Apache, licences alongside; all have ğ ş ı İ ç ö ü).
enum TextFonts {
  static let defaultId = "montserrat_black"

  static let all: [TextFont] = [
    TextFont(id: "montserrat_black", label: "Montserrat", file: "Montserrat-Variable", weight: 900),
    TextFont(id: "montserrat", label: "Montserrat Light", file: "Montserrat-Variable", weight: 400),
    TextFont(id: "anton", label: "Anton", file: "Anton-Regular"),
    TextFont(id: "bebas", label: "Bebas Neue", file: "BebasNeue-Regular"),
    TextFont(id: "oswald", label: "Oswald", file: "Oswald-Variable", weight: 700),
    TextFont(id: "poppins", label: "Poppins", file: "Poppins-Bold"),
    TextFont(id: "archivo", label: "Archivo Black", file: "ArchivoBlack-Regular"),
    TextFont(id: "russo", label: "Russo One", file: "RussoOne-Regular"),
    TextFont(id: "bangers", label: "Bangers", file: "Bangers-Regular"),
    TextFont(id: "luckiest", label: "Luckiest Guy", file: "LuckiestGuy-Regular"),
    TextFont(id: "bungee", label: "Bungee", file: "Bungee-Regular"),
    TextFont(id: "rubikmono", label: "Rubik Mono", file: "RubikMonoOne-Regular"),
    TextFont(id: "blackops", label: "Black Ops", file: "BlackOpsOne-Regular"),
    TextFont(id: "righteous", label: "Righteous", file: "Righteous-Regular"),
    TextFont(id: "audiowide", label: "Audiowide", file: "Audiowide-Regular"),
    TextFont(id: "pressstart", label: "Pixel", file: "PressStart2P-Regular"),
    TextFont(id: "monoton", label: "Monoton", file: "Monoton-Regular"),
    TextFont(id: "shrikhand", label: "Shrikhand", file: "Shrikhand-Regular"),
    TextFont(id: "abril", label: "Abril Fatface", file: "AbrilFatface-Regular"),
    TextFont(id: "playfair", label: "Playfair", file: "PlayfairDisplay-Variable", weight: 800),
    TextFont(id: "specialelite", label: "Typewriter", file: "SpecialElite-Regular"),
    TextFont(id: "lobster", label: "Lobster", file: "Lobster-Regular"),
    TextFont(id: "pacifico", label: "Pacifico", file: "Pacifico-Regular"),
    TextFont(id: "kaushan", label: "Kaushan", file: "KaushanScript-Regular"),
    TextFont(id: "dancing", label: "Dancing", file: "DancingScript-Variable", weight: 700),
    TextFont(id: "greatvibes", label: "Great Vibes", file: "GreatVibes-Regular"),
    TextFont(id: "caveat", label: "Caveat", file: "Caveat-Variable", weight: 700),
  ]

  static func byId(_ id: String) -> TextFont { all.first { $0.id == id } ?? all[0] }
}

/// Colour swatches for the text colour and the accent colour (same as Android).
let textPalette: [Int32] = ([
  0xFFFF_FFFF, 0xFF00_0000, 0xFFFF_3D9E, 0xFFFF_1744, 0xFFFF_9100, 0xFFFF_D600, 0xFFC6_FF00, 0xFF00_E676,
  0xFF1D_E9B6, 0xFF00_E5FF, 0xFF29_79FF, 0xFF65_1FFF, 0xFFD5_00F9, 0xFFFF_80AB, 0xFF8D_6E63, 0xFF9E_9E9E,
] as [UInt32]).map { Int32(bitPattern: $0) }

func argbComponents(_ argb: Int32) -> (a: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat) {
  let v = UInt32(bitPattern: argb)
  return (CGFloat((v >> 24) & 0xFF) / 255, CGFloat((v >> 16) & 0xFF) / 255,
          CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

func argbFrom(r: CGFloat, g: CGFloat, b: CGFloat) -> Int32 {
  func c(_ x: CGFloat) -> UInt32 { UInt32(max(0, min(255, (x * 255).rounded()))) }
  return Int32(bitPattern: 0xFF00_0000 | (c(r) << 16) | (c(g) << 8) | c(b))
}

// MARK: - Fonts / glyphs

/// Loads the bundled fonts (once) and caches sized fonts and glyph outlines.
/// Thread-safe: used on the main thread (preview) and the compositor queue.
final class TextFontCache: @unchecked Sendable {
  static let shared = TextFontCache()

  struct Glyph {
    /// Outline in glyph space (y up, baseline at 0); nil for glyphs without outlines (colour emoji).
    let path: CGPath?
    let advance: CGFloat
    /// Drawn as a line instead when there's no outline.
    let line: CTLine
  }

  private let lock = NSLock()
  private var descriptors: [String: CTFontDescriptor] = [:]
  private var fonts: [String: CTFont] = [:]
  private var glyphs: [String: Glyph] = [:]

  func font(_ font: TextFont, size: CGFloat) -> CTFont {
    lock.lock()
    defer { lock.unlock() }
    return fontLocked(font, size: size)
  }

  private func fontLocked(_ font: TextFont, size: CGFloat) -> CTFont {
    let key = "\(font.id)@\(Int((size * 4).rounded()))"
    if let f = fonts[key] { return f }
    var descriptor = descriptorLocked(file: font.file)
    if let weight = font.weight {
      // 'wght' variation axis.
      descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x7767_6874) as CFNumber,
                                                           CGFloat(weight))
    }
    let f = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    if fonts.count > 300 { fonts.removeAll() }
    fonts[key] = f
    return f
  }

  private func descriptorLocked(file: String) -> CTFontDescriptor {
    if let d = descriptors[file] { return d }
    var result = CTFontDescriptorCreateWithNameAndSize("HelveticaNeue-Bold" as CFString, 0)
    if let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "AdGagFonts") {
      _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      if let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
         let first = list.first {
        result = first
      }
    } else {
      NSLog("AdGag: font %@ not bundled", file)
    }
    descriptors[file] = result
    return result
  }

  func glyph(_ character: String, font: TextFont, size: CGFloat) -> Glyph {
    lock.lock()
    defer { lock.unlock() }
    let key = "\(font.id)@\(Int((size * 4).rounded()))|\(character)"
    if let g = glyphs[key] { return g }
    let ctFont = fontLocked(font, size: size)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: attributes))
    let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let path = CGMutablePath()
    var complete = true
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      let attrs = CTRunGetAttributes(run) as NSDictionary
      let runFont: CTFont
      if let value = attrs[kCTFontAttributeName as String] {
        runFont = value as! CTFont
      } else {
        runFont = ctFont
      }
      var ids = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
      CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
      for i in 0..<count {
        if let outline = CTFontCreatePathForGlyph(runFont, ids[i], nil) {
          path.addPath(outline, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
        } else {
          complete = false
        }
      }
    }
    let glyph = Glyph(path: complete ? path : nil, advance: advance, line: line)
    if glyphs.count > 4000 { glyphs.removeAll() }
    glyphs[key] = glyph
    return glyph
  }
}

// MARK: - Renderer

enum TextRenderer {
  /// How long entrance animations take.
  static let entranceMs: Int64 = 600

  struct Line {
    let glyphs: [TextFontCache.Glyph]
    let advances: [CGFloat]
    let width: CGFloat
  }

  struct Layout {
    let lines: [Line]
    let sizePx: CGFloat
    let lineHeight: CGFloat
    let width: CGFloat
    let height: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
  }

  private struct Motion {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
    var alpha: CGFloat = 1
  }

  static func layout(_ layer: TextLayer, frameH: CGFloat) -> Layout {
    let font = TextFonts.byId(layer.fontId)
    let size = max(1, CGFloat(layer.sizeFrac) * frameH)
    let cache = TextFontCache.shared
    let ctFont = cache.font(font, size: size)
    let spacing = CGFloat(layer.letterSpacing) * size
    let source = layer.text.isEmpty ? " " : layer.text
    let lines: [Line] = source.components(separatedBy: "\n").map { raw in
      let glyphs = raw.map { cache.glyph(String($0), font: font, size: size) }
      let advances = glyphs.map { $0.advance + spacing }
      let total = advances.reduce(0, +) - (glyphs.isEmpty ? 0 : spacing)
      return Line(glyphs: glyphs, advances: advances, width: max(0, total))
    }
    let lineHeight = size * 1.18
    return Layout(lines: lines, sizePx: size, lineHeight: lineHeight,
                  width: lines.map(\.width).max() ?? 0, height: CGFloat(lines.count) * lineHeight,
                  ascent: CTFontGetAscent(ctFont), descent: CTFontGetDescent(ctFont))
  }

  // MARK: Motion

  private static func easeOut(_ t: CGFloat) -> CGFloat {
    let inv = 1 - min(max(t, 0), 1)
    return 1 - inv * inv * inv
  }

  private static func backOut(_ t: CGFloat) -> CGFloat {
    let c1: CGFloat = 1.70158
    let c3 = c1 + 1
    let x = min(max(t, 0), 1) - 1
    return 1 + c3 * x * x * x + c1 * x * x
  }

  private static func bounceOut(_ t0: CGFloat) -> CGFloat {
    let t = min(max(t0, 0), 1)
    let n1: CGFloat = 7.5625
    let d1: CGFloat = 2.75
    if t < 1 / d1 { return n1 * t * t }
    if t < 2 / d1 { let u = t - 1.5 / d1; return n1 * u * u + 0.75 }
    if t < 2.5 / d1 { let u = t - 2.25 / d1; return n1 * u * u + 0.9375 }
    let u = t - 2.625 / d1
    return n1 * u * u + 0.984375
  }

  /// Whole-block motion at `localMs` into the layer. Offsets are in font-size units.
  private static func blockMotion(_ anim: TextAnimation, _ localMs: Int64) -> Motion {
    var m = Motion()
    let p = min(max(CGFloat(localMs) / CGFloat(entranceMs), 0), 1)
    let e = easeOut(p)
    let t = CGFloat(localMs) / 1000
    switch anim {
    case .FADE: m.alpha = p
    case .POP: m.scale = max(0.01, backOut(p)); m.alpha = min(1, p * 3)
    case .BOUNCE: m.dy = -(1 - bounceOut(p)) * 4; m.alpha = min(1, p * 4)
    case .ZOOM: m.scale = 0.2 + 0.8 * e; m.alpha = p
    case .SPIN: m.rotation = -360 * (1 - e); m.scale = max(0.01, e)
    case .SLIDE_UP: m.dy = (1 - e) * 3; m.alpha = p
    case .SLIDE_DOWN: m.dy = -(1 - e) * 3; m.alpha = p
    case .SLIDE_LEFT: m.dx = (1 - e) * 5; m.alpha = p
    case .SLIDE_RIGHT: m.dx = -(1 - e) * 5; m.alpha = p
    case .SHAKE: m.dx = sin(t * 40) * 0.06; m.rotation = sin(t * 33) * 2
    case .PULSE: m.scale = 1 + 0.08 * sin(t * 2 * .pi * 1.5)
    case .SWING: m.rotation = sin(t * 2 * .pi * 0.8) * 8
    case .FLICKER: m.alpha = sin(t * 23) + sin(t * 37) > 1.2 ? 0.25 : 1
    default: break
    }
    return m
  }

  /// Per-letter motion for glyph `i` of `count`: (dy in font units, alpha), or nil to hide it.
  private static func glyphMotion(_ anim: TextAnimation, _ localMs: Int64, _ i: Int, _ count: Int) -> (CGFloat, CGFloat)? {
    let t = CGFloat(localMs) / 1000
    let ms = CGFloat(localMs)
    switch anim {
    case .TYPEWRITER:
      return localMs >= Int64(i) * 70 ? (0, 1) : nil
    case .RISE:
      let q = min(max((ms - CGFloat(i) * 45) / 350, 0), 1)
      return ((1 - easeOut(q)) * 1, q)
    case .DROP:
      let q = min(max((ms - CGFloat(i) * 50) / 500, 0), 1)
      return (-(1 - bounceOut(q)) * 2.5, min(1, q * 4))
    case .WAVE:
      return (sin(t * 6 - CGFloat(i) * 0.6) * 0.12, 1)
    case .JUMP:
      let period = CGFloat(count) * 120 + 600
      let phase = ms.truncatingRemainder(dividingBy: period) - CGFloat(i) * 120
      return (phase >= 0 && phase <= 300 ? -sin(phase / 300 * .pi) * 0.35 : 0, 1)
    default:
      return (0, 1)
    }
  }

  /// True while this layer looks different from one frame to the next.
  static func isAnimating(_ layer: TextLayer, at tMs: Int64) -> Bool {
    let local = tMs - layer.startMs
    let n = Int64(layer.text.count)
    switch layer.animation {
    case .NONE: return false
    case .WAVE, .JUMP, .SHAKE, .PULSE, .SWING, .FLICKER, .RAINBOW: return true
    case .TYPEWRITER: return local < n * 70 + 100
    case .RISE, .DROP: return local < n * 50 + 600
    default: return local < entranceMs + 50
    }
  }

  /// Output time at which a caption has finished entering (drawn while it's selected and paused).
  static func settledTimeMs(_ layer: TextLayer) -> Int64 {
    let entrance = max(entranceMs + 100, Int64(layer.text.count) * 70 + 600)
    return min(layer.startMs + entrance, layer.endMs - 1)
  }

  // MARK: Drawing helpers

  private static func cg(_ argb: Int32, _ alpha: CGFloat) -> CGColor {
    let c = argbComponents(argb)
    return CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a * min(max(alpha, 0), 1))
  }

  private static func darker(_ argb: Int32, _ f: CGFloat) -> Int32 {
    let c = argbComponents(argb)
    return argbFrom(r: c.r * f, g: c.g * f, b: c.b * f)
  }

  private static func lerp(_ a: Int32, _ b: Int32, _ t: CGFloat) -> Int32 {
    let x = argbComponents(a)
    let y = argbComponents(b)
    return argbFrom(r: x.r + (y.r - x.r) * t, g: x.g + (y.g - x.g) * t, b: x.b + (y.b - x.b) * t)
  }

  private static func hex(_ v: UInt32) -> Int32 { Int32(bitPattern: v) }

  /// Gradient fills: colours, locations and whether it runs vertically (else horizontally).
  private static func gradient(_ style: TextStyleEffect) -> ([Int32], [CGFloat], Bool)? {
    switch style {
    case .GOLD:
      return ([hex(0xFFFF_F3B0), hex(0xFFFF_C837), hex(0xFFB8_860B), hex(0xFFFF_E08A)], [0, 0.45, 0.7, 1], true)
    case .SUNSET:
      return ([hex(0xFFFF_D000), hex(0xFFFF_6A00), hex(0xFFFF_2E93)], [0, 0.5, 1], false)
    case .OCEAN:
      return ([hex(0xFF00_F5D4), hex(0xFF00_BBF9), hex(0xFF3A_0CA3)], [0, 0.5, 1], false)
    case .RAINBOW_FILL:
      return ([hex(0xFFFF_1744), hex(0xFFFF_9100), hex(0xFFFF_EA00), hex(0xFF00_E676), hex(0xFF29_79FF),
               hex(0xFFD5_00F9)], [0, 0.2, 0.4, 0.6, 0.8, 1], false)
    default:
      return nil
    }
  }

  /// Block bounds in the layer's own (unrotated, unscaled) space, centred on 0,0 — plus style padding.
  static func localBounds(_ layout: Layout) -> CGRect {
    let pad = layout.sizePx * 0.3
    return CGRect(x: -layout.width / 2 - pad, y: -layout.height / 2 - pad,
                  width: layout.width + 2 * pad, height: layout.height + 2 * pad)
  }

  /// Is the point (frame units, y down) on this layer? For tap-to-select / drag.
  static func hitTest(_ layer: TextLayer, frameW: CGFloat, frameH: CGFloat, point: CGPoint) -> Bool {
    let layout = layout(layer, frameH: frameH)
    let rad = -CGFloat(layer.rotationDeg) * .pi / 180
    let dx = point.x - CGFloat(layer.x) * frameW
    let dy = point.y - CGFloat(layer.y) * frameH
    let s = CGFloat(layer.scale)
    let lx = (dx * cos(rad) - dy * sin(rad)) / s
    let ly = (dx * sin(rad) + dy * cos(rad)) / s
    return localBounds(layout).contains(CGPoint(x: lx, y: ly))
  }

  // MARK: Draw

  /// Draws `layer` at OUTPUT time `tMs` into a y-DOWN context whose units are the frame's.
  static func draw(_ ctx: CGContext, layer: TextLayer, frameW: CGFloat, frameH: CGFloat, tMs: Int64) {
    guard tMs >= layer.startMs, tMs < layer.endMs,
          !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let local = tMs - layer.startMs
    let layout = layout(layer, frameH: frameH)
    let s = layout.sizePx
    let motion = blockMotion(layer.animation, local)
    let alpha = min(max(CGFloat(layer.opacity) * motion.alpha, 0), 1)
    guard alpha > 0.001 else { return }
    let totalScale = CGFloat(layer.scale) * motion.scale

    ctx.saveGState()
    ctx.translateBy(x: CGFloat(layer.x) * frameW + motion.dx * s, y: CGFloat(layer.y) * frameH + motion.dy * s)
    ctx.rotate(by: (CGFloat(layer.rotationDeg) + motion.rotation) * .pi / 180)
    ctx.scaleBy(x: totalScale, y: totalScale)

    let top0 = -layout.height / 2
    let glyphHeight = layout.ascent + layout.descent
    let baseOffset = (layout.lineHeight - glyphHeight) / 2 + layout.ascent

    func lineStartX(_ line: Line) -> CGFloat {
      switch layer.align {
      case .LEFT: return -layout.width / 2
      case .CENTER: return -line.width / 2
      case .RIGHT: return layout.width / 2 - line.width
      }
    }

    // Per-line backgrounds.
    for (li, line) in layout.lines.enumerated() where line.width > 0 {
      let x0 = lineStartX(line)
      let top = top0 + CGFloat(li) * layout.lineHeight
      switch layer.style {
      case .BOX:
        let r = CGRect(x: x0 - 0.25 * s, y: top + 0.02 * s, width: line.width + 0.5 * s,
                       height: layout.lineHeight - 0.04 * s)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 0.12 * s, cornerHeight: 0.12 * s, transform: nil))
        ctx.setFillColor(cg(layer.accentColor, alpha))
        ctx.fillPath()
      case .PILL:
        let r = CGRect(x: x0 - 0.45 * s, y: top + 0.04 * s, width: line.width + 0.9 * s,
                       height: layout.lineHeight - 0.08 * s)
        let radius = min(r.height / 2, r.width / 2)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(cg(layer.accentColor, alpha))
        ctx.fillPath()
      case .HIGHLIGHT:
        ctx.setFillColor(cg(layer.accentColor, alpha * 0.85))
        ctx.fill(CGRect(x: x0 - 0.1 * s, y: top + layout.lineHeight * 0.45, width: line.width + 0.2 * s,
                        height: layout.lineHeight * 0.47))
      default:
        break
      }
    }

    drawGlyphs(ctx, layer: layer, layout: layout, local: local, alpha: alpha, lineStartX: lineStartX,
               top0: top0, baseOffset: baseOffset, mirror: false, shadowScale: totalScale)

    if layer.style == .REFLECTION {
      let bottom = top0 + layout.height
      let gap = 0.04 * s
      let region = CGRect(x: -layout.width / 2 - s, y: bottom + gap, width: layout.width + 2 * s, height: layout.height)
      ctx.saveGState()
      ctx.clip(to: region)
      ctx.beginTransparencyLayer(in: region, auxiliaryInfo: nil)
      ctx.saveGState()
      ctx.translateBy(x: 0, y: 2 * bottom + gap)
      ctx.scaleBy(x: 1, y: -1)
      drawGlyphs(ctx, layer: layer, layout: layout, local: local, alpha: alpha * 0.45, lineStartX: lineStartX,
                 top0: top0, baseOffset: baseOffset, mirror: true, shadowScale: totalScale)
      ctx.restoreGState()
      ctx.setBlendMode(.destinationIn)
      if let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                               locations: [0, 1]) {
        ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: region.minY), end: CGPoint(x: 0, y: region.maxY),
                               options: [])
      }
      ctx.endTransparencyLayer()
      ctx.restoreGState()
    }
    ctx.restoreGState()
  }

  private static func drawGlyphs(_ ctx: CGContext, layer: TextLayer, layout: Layout, local: Int64, alpha: CGFloat,
                                 lineStartX: (Line) -> CGFloat, top0: CGFloat, baseOffset: CGFloat, mirror: Bool,
                                 shadowScale: CGFloat) {
    let s = layout.sizePx
    let fillGradient = gradient(layer.style)
    let total = layout.lines.reduce(0) { $0 + $1.glyphs.count }
    var index = 0
    let space = CGColorSpaceCreateDeviceRGB()

    for (li, line) in layout.lines.enumerated() {
      var x = lineStartX(line)
      let baseline = top0 + CGFloat(li) * layout.lineHeight + baseOffset
      for (gi, glyph) in line.glyphs.enumerated() {
        defer { x += line.advances[gi] }
        let i = index
        index += 1
        guard let gm = glyphMotion(layer.animation, local, i, total) else { continue }
        let a = alpha * gm.1
        let y = baseline + gm.0 * s
        let color: Int32
        if layer.animation == .RAINBOW {
          let hue = ((CGFloat(local) / 1000) * 120 + CGFloat(i) * 25).truncatingRemainder(dividingBy: 360) / 360
          var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
          UIColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: nil)
          color = argbFrom(r: r, g: g, b: b)
        } else {
          color = layer.color
        }

        guard let outline = glyph.path else {
          // No outline (colour emoji etc.): draw the glyph as text, fill only.
          ctx.saveGState()
          ctx.translateBy(x: x, y: y)
          ctx.scaleBy(x: 1, y: -1)
          ctx.setFillColor(cg(color, a))
          ctx.textPosition = .zero
          CTLineDraw(glyph.line, ctx)
          ctx.restoreGState()
          continue
        }

        func path(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPath {
          var t = CGAffineTransform(translationX: x + dx, y: y + dy).scaledBy(x: 1, y: -1)
          return outline.copy(using: &t) ?? outline
        }
        func fill(_ p: CGPath, _ c: CGColor) {
          ctx.addPath(p)
          ctx.setFillColor(c)
          ctx.fillPath()
        }
        func stroke(_ p: CGPath, _ c: CGColor, _ width: CGFloat) {
          ctx.addPath(p)
          ctx.setStrokeColor(c)
          ctx.setLineWidth(width)
          ctx.setLineJoin(.round)
          ctx.setLineCap(.round)
          ctx.strokePath()
        }
        func glowFill(_ p: CGPath, _ c: CGColor, blur: CGFloat, glow: CGColor) {
          ctx.saveGState()
          ctx.setShadow(offset: .zero, blur: blur * shadowScale, color: glow)
          fill(p, c)
          ctx.restoreGState()
        }
        let p = path()

        if !mirror {
          switch layer.style {
          case .OUTLINE:
            stroke(p, cg(layer.accentColor, a), 0.1 * s)
          case .SHADOW:
            fill(path(dx: 0.05 * s, dy: 0.06 * s), cg(layer.accentColor, a * 0.8))
          case .GLOW:
            glowFill(p, cg(color, a), blur: 0.35 * s, glow: cg(layer.accentColor, a))
          case .NEON:
            glowFill(p, cg(layer.accentColor, a), blur: 0.5 * s, glow: cg(layer.accentColor, a))
            glowFill(p, cg(layer.accentColor, a), blur: 0.18 * s, glow: cg(layer.accentColor, a))
          case .EXTRUDE:
            let depth = cg(darker(layer.accentColor, 0.75), a)
            for k in stride(from: 6, through: 1, by: -1) {
              fill(path(dx: CGFloat(k) * 0.015 * s, dy: CGFloat(k) * 0.015 * s), depth)
            }
          case .COMIC:
            fill(path(dx: 0.07 * s, dy: 0.08 * s), CGColor(red: 0, green: 0, blue: 0, alpha: a))
            stroke(p, CGColor(red: 0, green: 0, blue: 0, alpha: a), 0.14 * s)
          case .RETRO:
            stroke(p, cg(layer.accentColor, a), 0.24 * s)
            stroke(p, CGColor(red: 1, green: 1, blue: 1, alpha: a), 0.11 * s)
          case .GLITCH:
            fill(path(dx: -0.05 * s), cg(hex(0xFF00_E5FF), a * 0.85))
            fill(path(dx: 0.05 * s), cg(hex(0xFFFF_1744), a * 0.85))
          case .GOLD:
            stroke(p, cg(hex(0xFF6B_4A00), a), 0.05 * s)
          default:
            break
          }
        }

        if layer.style == .HOLLOW && !mirror {
          stroke(p, cg(color, a), 0.07 * s)
        } else if layer.style != .GLOW || mirror {
          if let fg = fillGradient, layer.animation != .RAINBOW,
             let gradient = CGGradient(colorsSpace: space, colors: fg.0.map { cg($0, 1) } as CFArray,
                                       locations: fg.1) {
            let vertical = fg.2
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            ctx.setAlpha(a)
            let w = layout.width / 2
            let h = layout.height / 2
            let start = vertical ? CGPoint(x: 0, y: -h) : CGPoint(x: -w, y: 0)
            let end = vertical ? CGPoint(x: 0, y: h) : CGPoint(x: w, y: 0)
            ctx.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
          } else {
            let fillColor = layer.style == .NEON && !mirror ? lerp(color, -1, 0.6) : color
            fill(p, cg(fillColor, a))
          }
        }
      }
    }
  }
}

// MARK: - Export / compositor overlay

/// The captions as a full-frame image for the compositor (export): redrawn
/// only while something animates or the visible set changes. Time is the
/// composition's own time, which is OUTPUT time — the captions' time base.
final class TextOverlayRenderer: @unchecked Sendable {
  private let layers: [TextLayer]
  private let lock = NSLock()
  private var lastKey: String?
  private var lastImage: CIImage?

  init(layers: [TextLayer]) {
    self.layers = layers.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.endMs > $0.startMs }
  }

  var isEmpty: Bool { layers.isEmpty }

  func image(size: CGSize, tMs: Int64) -> CIImage? {
    lock.lock()
    defer { lock.unlock() }
    let active = layers.filter { tMs >= $0.startMs && tMs < $0.endMs }
    guard !active.isEmpty else { return nil }
    let key = active.map(\.id).joined(separator: ",") + "@\(Int(size.width))x\(Int(size.height))"
    let animating = active.contains { TextRenderer.isAnimating($0, at: tMs) }
    if !animating, key == lastKey, let cached = lastImage { return cached }

    let w = max(2, Int(size.width))
    let h = max(2, Int(size.height))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // y-down drawing, like the preview canvas.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    for layer in active {
      TextRenderer.draw(ctx, layer: layer, frameW: CGFloat(w), frameH: CGFloat(h), tMs: tMs)
    }
    guard let cgImage = ctx.makeImage() else { return nil }
    let image = CIImage(cgImage: cgImage)
    lastKey = key
    lastImage = image
    return image
  }
}
