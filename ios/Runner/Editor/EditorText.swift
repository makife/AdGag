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
  var label: String { tr(String(rawValue.prefix(1)) + rawValue.dropFirst().lowercased()) }
}

enum TextStyleEffect: String, Codable, CaseIterable {
  case NONE, OUTLINE, SHADOW, GLOW, NEON, BOX, PILL, HIGHLIGHT, HOLLOW, EXTRUDE, REFLECTION
  case COMIC, RETRO, GLITCH, GOLD, SUNSET, OCEAN, RAINBOW_FILL
  case STICKER, LONG_SHADOW, DOUBLE_OUTLINE, CHROME, FIRE, ICE, SPLIT, CANDY

  /// Shown in the editor's language (`tr`).
  var label: String { tr(labelEn) }
  var labelEn: String {
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
    case .STICKER: return "Sticker"
    case .LONG_SHADOW: return "Long shadow"
    case .DOUBLE_OUTLINE: return "Double"
    case .CHROME: return "Chrome"
    case .FIRE: return "Fire"
    case .ICE: return "Ice"
    case .SPLIT: return "Split"
    case .CANDY: return "Candy"
    }
  }
}

/// How a caption leaves at its end (same as Android's TextExit).
enum TextExit: String, Codable, CaseIterable {
  case NONE, FADE, SHRINK, BLOW_UP, SPIN, SLIDE_UP, SLIDE_DOWN, SLIDE_LEFT, SLIDE_RIGHT
  case ERASE, FALL, SCATTER, FLICKER_OUT

  /// Shown in the editor's language (`tr`).
  var label: String { tr(labelEn) }
  var labelEn: String {
    switch self {
    case .NONE: return "None"
    case .FADE: return "Fade"
    case .SHRINK: return "Shrink"
    case .BLOW_UP: return "Blow up"
    case .SPIN: return "Spin"
    case .SLIDE_UP: return "Slide up"
    case .SLIDE_DOWN: return "Slide down"
    case .SLIDE_LEFT: return "Slide left"
    case .SLIDE_RIGHT: return "Slide right"
    case .ERASE: return "Erase"
    case .FALL: return "Fall"
    case .SCATTER: return "Scatter"
    case .FLICKER_OUT: return "Flicker"
    }
  }
}

enum TextAnimation: String, Codable, CaseIterable {
  case NONE, FADE, POP, BOUNCE, ZOOM, SPIN, SLIDE_UP, SLIDE_DOWN, SLIDE_LEFT, SLIDE_RIGHT
  case TYPEWRITER, RISE, DROP, WAVE, JUMP, SHAKE, PULSE, SWING, FLICKER, RAINBOW

  /// Shown in the editor's language (`tr`).
  var label: String { tr(labelEn) }
  var labelEn: String {
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
  /// How it leaves at endMs (the last ~0.5s).
  var exit: TextExit = .FADE
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
    t.exit = TextExit(rawValue: o["exit"] as? String ?? "") ?? .NONE
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
    TextFont(id: "alfaslab", label: "Alfa Slab", file: "AlfaSlabOne-Regular"),
    TextFont(id: "amatic", label: "Amatic", file: "AmaticSC-Bold"),
    TextFont(id: "barlow", label: "Barlow Black", file: "BarlowCondensed-Black"),
    TextFont(id: "bowlby", label: "Bowlby", file: "BowlbyOneSC-Regular"),
    TextFont(id: "bungeeshade", label: "Bungee Shade", file: "BungeeShade-Regular"),
    TextFont(id: "courgette", label: "Courgette", file: "Courgette-Regular"),
    TextFont(id: "nosifer", label: "Nosifer", file: "Nosifer-Regular"),
    TextFont(id: "rubikbubbles", label: "Bubbles", file: "RubikBubbles-Regular"),
    TextFont(id: "rubikglitch", label: "Glitchy", file: "RubikGlitch-Regular"),
    TextFont(id: "rubikwet", label: "Wet Paint", file: "RubikWetPaint-Regular"),
    TextFont(id: "spacegrotesk", label: "Space Grotesk", file: "SpaceGrotesk-Variable", weight: 700),
    TextFont(id: "staatliches", label: "Staatliches", file: "Staatliches-Regular"),
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

  /// How long exit effects take (less on very short captions).
  static let exitMs: Int64 = 500

  static func exitMs(of layer: TextLayer) -> Int64 { min(exitMs, (layer.endMs - layer.startMs) / 2) }

  /// 0 while the caption is fully on screen, rising to 1 at its end while its exit plays.
  static func exitProgress(_ layer: TextLayer, _ tMs: Int64) -> CGFloat {
    guard layer.exit != .NONE else { return 0 }
    let d = exitMs(of: layer)
    let remaining = layer.endMs - tMs
    guard d > 0, remaining < d else { return 0 }
    return min(max(1 - CGFloat(remaining) / CGFloat(d), 0), 1)
  }

  private static func easeIn(_ t: CGFloat) -> CGFloat {
    let x = min(max(t, 0), 1)
    return x * x * x
  }

  /// The whole-block part of an exit at progress q (0...1).
  private static func applyExit(_ exit: TextExit, _ q: CGFloat, _ m: inout Motion) {
    guard q > 0 else { return }
    let e = easeIn(q)
    switch exit {
    case .FADE: m.alpha *= 1 - q
    case .SHRINK: m.scale *= max(1 - e, 0.01)
    case .BLOW_UP: m.scale *= 1 + 1.5 * e; m.alpha *= 1 - q
    case .SPIN: m.rotation += 360 * e; m.scale *= max(1 - e, 0.01)
    case .SLIDE_UP: m.dy -= 3 * e; m.alpha *= 1 - e
    case .SLIDE_DOWN: m.dy += 3 * e; m.alpha *= 1 - e
    case .SLIDE_LEFT: m.dx -= 5 * e; m.alpha *= 1 - e
    case .SLIDE_RIGHT: m.dx += 5 * e; m.alpha *= 1 - e
    case .FLICKER_OUT: m.alpha *= (q > 0.85 || sin(q * 60) > 0.2) ? 0 : 1
    default: break
    }
  }

  /// Per-letter part of an exit: (extra dy in font units, alpha multiplier), or nil to hide the glyph.
  private static func glyphExit(_ exit: TextExit, _ q: CGFloat, _ i: Int, _ count: Int) -> (CGFloat, CGFloat)? {
    guard q > 0 else { return (0, 1) }
    switch exit {
    case .ERASE:
      return CGFloat(i) < CGFloat(count) * (1 - q) ? (0, 1) : nil
    case .FALL:
      let k = min(max(q * 1.6 - CGFloat(i) / CGFloat(max(count, 1)) * 0.6, 0), 1)
      return (3 * easeIn(k), 1 - k)
    case .SCATTER:
      let k = easeIn(q)
      let dir: CGFloat = i % 2 == 0 ? -1 : 1
      return (dir * 2.5 * k * (1 + CGFloat(i % 3) * 0.4), 1 - q)
    default:
      return (0, 1)
    }
  }

  /// True while this layer looks different from one frame to the next.
  static func isAnimating(_ layer: TextLayer, at tMs: Int64) -> Bool {
    let local = tMs - layer.startMs
    let n = Int64(layer.text.count)
    if layer.exit != .NONE && layer.endMs - tMs < exitMs(of: layer) + 50 { return true }
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
    let lastSettled = max(layer.startMs, layer.endMs - exitMs(of: layer) - 1)
    return min(layer.startMs + entrance, lastSettled)
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
  private static func gradient(_ layer: TextLayer) -> ([Int32], [CGFloat], Bool)? {
    switch layer.style {
    case .CHROME:
      return ([hex(0xFFFF_FFFF), hex(0xFFB0_BEC5), hex(0xFF37_474F), hex(0xFFEC_EFF1), hex(0xFF90_A4AE)],
              [0, 0.4, 0.52, 0.7, 1], true)
    case .FIRE:
      return ([hex(0xFFD5_0000), hex(0xFFFF_6D00), hex(0xFFFF_D600)], [0, 0.5, 1], true)
    case .ICE:
      return ([hex(0xFFFF_FFFF), hex(0xFFB3_E5FC), hex(0xFF29_B6F6)], [0, 0.5, 1], true)
    case .SPLIT:
      return ([layer.color, layer.color, layer.accentColor, layer.accentColor], [0, 0.5, 0.5, 1], true)
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
    var motion = blockMotion(layer.animation, local)
    let exitQ = exitProgress(layer, tMs)
    applyExit(layer.exit, exitQ, &motion)
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
               top0: top0, baseOffset: baseOffset, mirror: false, shadowScale: totalScale, exitQ: exitQ)

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
                 top0: top0, baseOffset: baseOffset, mirror: true, shadowScale: totalScale, exitQ: exitQ)
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
                                 shadowScale: CGFloat, exitQ: CGFloat) {
    let s = layout.sizePx
    let fillGradient = gradient(layer)
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
        guard let gm = glyphMotion(layer.animation, local, i, total),
              let ge = glyphExit(layer.exit, exitQ, i, total) else { continue }
        let a = alpha * gm.1 * ge.1
        let y = baseline + (gm.0 + ge.0) * s
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
          case .STICKER:
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 0.12 * s * shadowScale, color: CGColor(red: 0, green: 0, blue: 0, alpha: a * 0.45))
            stroke(p, CGColor(red: 1, green: 1, blue: 1, alpha: a), 0.3 * s)
            ctx.restoreGState()
          case .LONG_SHADOW:
            let shade = cg(layer.accentColor, a)
            for k in stride(from: 18, through: 1, by: -1) {
              fill(path(dx: CGFloat(k) * 0.02 * s, dy: CGFloat(k) * 0.02 * s), shade)
            }
          case .DOUBLE_OUTLINE:
            stroke(p, cg(color, a), 0.32 * s)
            stroke(p, cg(layer.accentColor, a), 0.18 * s)
          case .CHROME:
            stroke(p, cg(hex(0xFF26_3238), a), 0.06 * s)
          case .FIRE:
            glowFill(p, cg(hex(0xFFFF_6D00), a), blur: 0.4 * s, glow: cg(hex(0xFFFF_3D00), a))
          case .ICE:
            glowFill(p, cg(hex(0xFF81_D4FA), a), blur: 0.3 * s, glow: cg(hex(0xFF00_E5FF), a))
            stroke(p, CGColor(red: 1, green: 1, blue: 1, alpha: a), 0.05 * s)
          case .CANDY:
            stroke(p, CGColor(red: 1, green: 1, blue: 1, alpha: a), 0.12 * s)
          default:
            break
          }
        }

        if layer.style == .HOLLOW && !mirror {
          stroke(p, cg(color, a), 0.07 * s)
        } else if layer.style == .CANDY && layer.animation != .RAINBOW {
          // Diagonal stripes of the two colours, clipped to the letter.
          ctx.saveGState()
          ctx.addPath(p)
          ctx.clip()
          fill(p, cg(layer.color, a))
          ctx.rotate(by: -.pi / 4)
          let period = 0.18 * s * 1.41421356
          let reach = layout.width + layout.height + 4 * s
          ctx.setFillColor(cg(layer.accentColor, a))
          var sx = -reach
          while sx < reach {
            ctx.fill(CGRect(x: sx, y: -reach, width: period / 2, height: 2 * reach))
            sx += period
          }
          ctx.restoreGState()
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
  /// Drawn under the captions; they always animate, so redraw while one is on screen.
  private let stickers: [StickerLayer]
  private let lock = NSLock()
  private var lastKey: String?
  private var lastImage: CIImage?

  init(layers: [TextLayer], stickers: [StickerLayer] = []) {
    self.layers = layers.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.endMs > $0.startMs }
    self.stickers = stickers.filter { $0.endMs > $0.startMs && StickerStore.shared.byId($0.stickerId) != nil }
  }

  var isEmpty: Bool { layers.isEmpty && stickers.isEmpty }

  func image(size: CGSize, tMs: Int64) -> CIImage? {
    lock.lock()
    defer { lock.unlock() }
    let active = layers.filter { tMs >= $0.startMs && tMs < $0.endMs }
    let activeStickers = stickers.filter { tMs >= $0.startMs && tMs < $0.endMs }
    guard !active.isEmpty || !activeStickers.isEmpty else { return nil }
    let key = (activeStickers.map(\.id) + active.map(\.id)).joined(separator: ",")
      + "@\(Int(size.width))x\(Int(size.height))"
    let animating = !activeStickers.isEmpty || active.contains { TextRenderer.isAnimating($0, at: tMs) }
    if !animating, key == lastKey, let cached = lastImage { return cached }

    let w = max(2, Int(size.width))
    let h = max(2, Int(size.height))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // y-down drawing, like the preview canvas.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    for sticker in activeStickers {
      StickerRenderer.draw(ctx, layer: sticker, frameW: CGFloat(w), frameH: CGFloat(h), tMs: tMs)
    }
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
