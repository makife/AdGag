// ADGAG PATCH — the live AR effects' artwork, a line-for-line port of
// third_party/camera_android_camerax/.../ArEffects.kt (same shapes, sizes,
// colours and timing). Everything is drawn in FACE UNITS (see ArFace):
// origin between the eyes, x: 1 = eye distance, +y down the face; eyes at
// (±0.5, 0), nose base ≈ (0, 0.7), mouth ≈ (0, 1.05), forehead top ≈ -1.
// Animated effects are stateless functions of time t (seconds). All artwork
// is left-right symmetric. The ids are the contract with the app
// (lib/.../ar_effects.dart).

import CoreGraphics
import Foundation

enum ArEffects {
  static func draw(_ c: CGContext, id: String, face: ArFace, t: CGFloat) {
    let d = Draw(c)
    switch id {
    case "sunglasses": sunglasses(d)
    case "nerd": nerdGlasses(d)
    case "crown": crown(d, t)
    case "flower_crown": flowerCrown(d)
    case "party": partyHat(d, t)
    case "viking": viking(d)
    case "devil": devil(d, t)
    case "halo": halo(d, t)
    case "cat": cat(d, face)
    case "bunny": bunny(d, face)
    case "puppy": puppy(d, face)
    case "alien": alien(d, t)
    case "heart_eyes": heartEyes(d, t)
    case "star_eyes": starEyes(d, t)
    case "blush": blush(d, face)
    case "tears": tears(d, t)
    case "hearts": floatingHearts(d, t)
    case "money_rain": moneyRain(d, t)
    case "sparkles": sparkles(d, t)
    case "rainbow": rainbowMouth(d, face, t)
    case "mustache": mustache(d, face)
    case "clown": clown(d, face)
    default: break
    }
  }

  private static let sides: [CGFloat] = [-1, 1]

  // MARK: - glasses

  private static func sunglasses(_ d: Draw) {
    for side in sides {
      let cx = 0.52 * side
      let lens = d.roundRect(CGRect(x: cx - 0.43, y: -0.25, width: 0.86, height: 0.55), 0.22)
      d.linear(lens, from: CGPoint(x: 0, y: -0.25), to: CGPoint(x: 0, y: 0.3), rgb(40, 40, 55), rgb(4, 4, 10))
      d.stroke(lens, rgb(15, 15, 15), 0.08)
      d.fill(d.poly([(cx - 0.32, -0.15), (cx - 0.1, -0.15), (cx - 0.3, 0.14)]), rgb(255, 255, 255, 140))
      d.fill(d.circle(cx + 0.24, 0.16, 0.04), rgb(255, 255, 255, 90))
    }
    d.line(-0.1, -0.13, 0.1, -0.13, rgb(15, 15, 15), 0.09)
    d.line(-0.95, -0.12, -1.22, -0.2, rgb(15, 15, 15), 0.09)
    d.line(0.95, -0.12, 1.22, -0.2, rgb(15, 15, 15), 0.09)
  }

  private static func nerdGlasses(_ d: Draw) {
    for side in sides {
      let cx = 0.5 * side
      d.fill(d.circle(cx, 0.02, 0.36), rgb(180, 220, 255, 45))
      d.stroke(d.circle(cx, 0.02, 0.36), rgb(25, 20, 18), 0.12)
      d.stroke(d.arc(CGRect(x: cx - 0.26, y: -0.24, width: 0.52, height: 0.52), 200, 60), rgb(255, 255, 255, 160), 0.04)
    }
    d.stroke(d.arc(CGRect(x: -0.16, y: -0.12, width: 0.32, height: 0.24), 200, 140), rgb(25, 20, 18), 0.1)
    d.line(-0.86, -0.04, -1.2, -0.12, rgb(25, 20, 18), 0.1)
    d.line(0.86, -0.04, 1.2, -0.12, rgb(25, 20, 18), 0.1)
    // Tape on the bridge.
    d.fill(d.rect(-0.07, -0.14, 0.07, 0.0), rgb(245, 245, 235))
  }

  // MARK: - headwear

  private static func crown(_ d: Draw, _ t: CGFloat) {
    let path = d.poly([(-0.85, -1.15), (-0.9, -1.95), (-0.45, -1.55), (0, -2.15), (0.45, -1.55), (0.9, -1.95), (0.85, -1.15)])
    d.linear(path, from: CGPoint(x: 0, y: -2.15), to: CGPoint(x: 0, y: -1.15), rgb(255, 232, 120), rgb(205, 140, 15))
    d.stroke(path, rgb(140, 90, 5), 0.05)
    d.fill(d.rect(-0.86, -1.32, 0.86, -1.15), rgb(170, 110, 10))
    for x: CGFloat in [-0.9, 0, 0.9] {
      d.fill(d.circle(x, x == 0 ? -2.17 : -1.97, 0.1), rgb(255, 245, 170))
    }
    gem(d, 0, -1.47, 0.15, rgb(230, 30, 70))
    gem(d, -0.5, -1.4, 0.1, rgb(40, 120, 240))
    gem(d, 0.5, -1.4, 0.1, rgb(40, 120, 240))
    // Twinkles on the tips.
    for (i, x) in [CGFloat(-0.9), 0, 0.9].enumerated() {
      let tw = twinkle(t, i)
      if tw > 0.05 { sparkle(d, x, x == 0 ? -2.25 : -2.05, 0.18 * tw, rgb(255, 255, 255)) }
    }
  }

  private static func flowerCrown(_ d: Draw) {
    let colors = [rgb(255, 120, 170), rgb(255, 210, 80), rgb(170, 130, 255), rgb(255, 150, 90), rgb(120, 200, 255)]
    let n = 9
    // Leaves first (under the flowers).
    for i in 0..<(n - 1) {
      let a = arcPoint(CGFloat(i) + 0.5, n)
      d.c.saveGState()
      d.c.translateBy(x: a.x, y: a.y)
      d.c.rotate(by: (a.x < 0 ? -30 : 30) * .pi / 180)
      d.fill(d.oval(CGRect(x: -0.07, y: -0.16, width: 0.14, height: 0.32)), rgb(90, 170, 90))
      d.c.restoreGState()
    }
    for i in 0..<n {
      let p = arcPoint(CGFloat(i), n)
      // Mirror-symmetric colours: index from the centre.
      let k = abs(i - n / 2) % colors.count
      flower(d, p.x, p.y, i == n / 2 ? 0.24 : 0.19, colors[k])
    }
  }

  /// Points on the arc over the forehead, from ear to ear.
  private static func arcPoint(_ i: CGFloat, _ n: Int) -> CGPoint {
    let a = CGFloat.pi * (0.12 + 0.76 * i / CGFloat(n - 1))
    return CGPoint(x: -cos(a) * 1.15, y: -0.95 - sin(a) * 0.45)
  }

  private static func partyHat(_ d: Draw, _ t: CGFloat) {
    let hat = d.poly([(-0.6, -1.2), (0, -2.65), (0.6, -1.2)])
    d.linear(hat, from: CGPoint(x: -0.6, y: 0), to: CGPoint(x: 0.6, y: 0), rgb(14, 170, 166), rgb(40, 220, 210))
    d.c.saveGState()
    d.c.addPath(hat)
    d.c.clip()
    var y: CGFloat = -2.55
    while y < -1.1 {
      d.fill(d.rect(-1, y, 1, y + 0.12), rgb(255, 214, 64))
      y += 0.32
    }
    d.c.restoreGState()
    d.fill(d.circle(0, -2.68, 0.17), rgb(255, 90, 140))
    d.line(-0.62, -1.2, 0.62, -1.2, rgb(255, 255, 255), 0.06)
    // Confetti falling around the head.
    let confetti = [rgb(255, 90, 140), rgb(255, 214, 64), rgb(22, 197, 192), rgb(140, 110, 255)]
    for i in 0..<16 {
      let side: CGFloat = i % 2 == 0 ? -1 : 1
      let x = side * (0.8 + 1.0 * hash(i, 1))
      let y = fall(t, i, 0.35, -2.8, 2.2)
      d.c.saveGState()
      d.c.translateBy(x: x, y: y)
      d.c.rotate(by: t * 240 * (0.5 + hash(i, 2)) * side * .pi / 180)
      d.fill(d.rect(-0.06, -0.03, 0.06, 0.03), confetti[i % confetti.count])
      d.c.restoreGState()
    }
  }

  private static func viking(_ d: Draw) {
    // Horns first (behind the helmet).
    for side in sides {
      let horn = CGMutablePath()
      horn.move(to: CGPoint(x: 0.78 * side, y: -1.2))
      horn.addCurve(
        to: CGPoint(x: 1.35 * side, y: -2.25), control1: CGPoint(x: 1.3 * side, y: -1.25),
        control2: CGPoint(x: 1.55 * side, y: -1.7))
      horn.addCurve(
        to: CGPoint(x: 0.72 * side, y: -1.48), control1: CGPoint(x: 1.25 * side, y: -1.85),
        control2: CGPoint(x: 1.1 * side, y: -1.55))
      horn.closeSubpath()
      d.linear(
        horn, from: CGPoint(x: 0.8 * side, y: -1.2), to: CGPoint(x: 1.35 * side, y: -2.25), rgb(250, 240, 215),
        rgb(200, 180, 140))
      d.stroke(horn, rgb(150, 130, 95), 0.03)
    }
    let dome = d.arc(CGRect(x: -0.95, y: -2.0, width: 1.9, height: 1.5), 180, 180, closed: true)
    d.linear(dome, from: CGPoint(x: -0.9, y: -2), to: CGPoint(x: 0.9, y: -1), rgb(200, 205, 215), rgb(110, 115, 125))
    d.fill(d.rect(-0.98, -1.33, 0.98, -1.13), rgb(150, 110, 60))
    d.fill(d.rect(-0.08, -2.0, 0.08, -1.25), rgb(150, 110, 60))
    for x: CGFloat in [-0.7, -0.35, 0, 0.35, 0.7] {
      d.fill(d.circle(x, -1.23, 0.045), rgb(230, 200, 120))
    }
  }

  private static func devil(_ d: Draw, _ t: CGFloat) {
    let pulse = 0.5 + 0.5 * sin(t * 4)
    for side in sides {
      let horn = CGMutablePath()
      horn.move(to: CGPoint(x: 0.3 * side, y: -1.05))
      horn.addCurve(
        to: CGPoint(x: 0.95 * side, y: -1.95), control1: CGPoint(x: 0.45 * side, y: -1.5),
        control2: CGPoint(x: 0.75 * side, y: -1.75))
      horn.addCurve(
        to: CGPoint(x: 0.7 * side, y: -1.0), control1: CGPoint(x: 0.85 * side, y: -1.55),
        control2: CGPoint(x: 0.8 * side, y: -1.25))
      horn.closeSubpath()
      d.glow(horn, rgb(255, 40, 20, 80 + 80 * pulse), 0.15)
      d.linear(horn, from: CGPoint(x: 0.3 * side, y: -1.0), to: CGPoint(x: 0.95 * side, y: -1.95), rgb(200, 10, 20), rgb(255, 80, 60))
    }
  }

  private static func halo(_ d: Draw, _ t: CGFloat) {
    let pulse = 0.75 + 0.25 * sin(t * 3)
    let bob = 0.04 * sin(t * 2)
    let ring = d.oval(CGRect(x: -0.8, y: -2.12 + bob, width: 1.6, height: 0.36))
    d.stroke(ring, rgb(255, 230, 120, 110 * pulse), 0.32)
    d.stroke(ring, rgb(255, 215, 70), 0.11)
    d.stroke(ring, rgb(255, 250, 225, 230), 0.035)
  }

  // MARK: - animals

  private static func cat(_ d: Draw, _ face: ArFace) {
    for side in sides {
      d.fill(d.poly([(0.35 * side, -1.05), (0.95 * side, -1.95), (1.1 * side, -0.85)]), rgb(70, 60, 60))
      d.fill(d.poly([(0.52 * side, -1.07), (0.92 * side, -1.68), (1.0 * side, -0.98)]), rgb(255, 160, 185))
    }
    let ny = face.toLocal(face.nose).y - 0.12
    d.fill(d.poly([(-0.14, ny - 0.05), (0.14, ny - 0.05), (0, ny + 0.1)]), rgb(255, 130, 160))
    for side in sides {
      for k in -1...1 {
        let kf = CGFloat(k)
        d.line(0.22 * side, ny + 0.08 + 0.05 * kf, 0.95 * side, ny + 0.02 + 0.14 * kf, rgb(40, 35, 35, 230), 0.025)
      }
    }
  }

  private static func bunny(_ d: Draw, _ face: ArFace) {
    for side in sides {
      d.c.saveGState()
      d.c.translateBy(x: 0.45 * side, y: -1.1)
      d.c.rotate(by: 12 * side * .pi / 180)
      let ear = d.oval(CGRect(x: -0.25, y: -1.35, width: 0.5, height: 1.45))
      d.fill(ear, rgb(250, 250, 250))
      d.stroke(ear, rgb(220, 220, 225), 0.03)
      d.fill(d.oval(CGRect(x: -0.13, y: -1.2, width: 0.26, height: 1.15)), rgb(255, 180, 200))
      d.c.restoreGState()
    }
    let nose = face.toLocal(face.nose)
    d.fill(d.oval(CGRect(x: -0.12, y: nose.y - 0.2, width: 0.24, height: 0.16)), rgb(255, 140, 170))
    let mouth = face.toLocal(face.mouth)
    for side in sides {
      let x0: CGFloat = side < 0 ? -0.13 : 0.005
      let tooth = d.roundRect(CGRect(x: x0, y: mouth.y - 0.04, width: 0.125, height: 0.24), 0.03)
      d.fill(tooth, rgb(255, 255, 255))
      d.stroke(tooth, rgb(190, 190, 190), 0.02)
    }
  }

  private static func puppy(_ d: Draw, _ face: ArFace) {
    for side in sides {
      d.c.saveGState()
      d.c.translateBy(x: 1.05 * side, y: -0.95)
      d.c.rotate(by: -18 * side * .pi / 180)
      d.linear(
        d.oval(CGRect(x: -0.32, y: -0.55, width: 0.64, height: 1.3)), from: CGPoint(x: 0, y: -0.55),
        to: CGPoint(x: 0, y: 0.75), rgb(150, 95, 50), rgb(95, 60, 30))
      d.fill(d.oval(CGRect(x: -0.16, y: -0.3, width: 0.32, height: 0.8)), rgb(230, 150, 150))
      d.c.restoreGState()
    }
    let cy = face.toLocal(face.nose).y - 0.1
    d.fill(d.oval(CGRect(x: -0.24, y: cy - 0.16, width: 0.48, height: 0.3)), rgb(25, 20, 20))
    d.fill(d.oval(CGRect(x: -0.1, y: cy - 0.12, width: 0.2, height: 0.07)), rgb(255, 255, 255, 160))
    // Tongue only while the mouth is open.
    let open = face.mouthOpen()
    if open > 0.15 {
      let mb = face.toLocal(face.mouthBottom)
      let len = 0.25 + 0.35 * open
      d.fill(d.roundRect(CGRect(x: -0.17, y: mb.y - 0.15, width: 0.34, height: len), 0.17), rgb(240, 90, 110))
      d.line(0, mb.y - 0.1, 0, mb.y - 0.2 + len, rgb(200, 50, 70), 0.03)
    }
  }

  private static func alien(_ d: Draw, _ t: CGFloat) {
    for side in sides {
      let sway = 12 * sin(t * 3 + (side < 0 ? 0 : 1.3))
      d.c.saveGState()
      d.c.translateBy(x: 0.35 * side, y: -1.05)
      d.c.rotate(by: (20 * side + sway) * .pi / 180)
      d.line(0, 0, 0, -0.9, rgb(90, 200, 90), 0.06)
      d.radial(d.circle(0, -0.95, 0.16), center: CGPoint(x: -0.05, y: -0.97), radius: 0.2, rgb(200, 255, 170), rgb(60, 180, 60))
      d.c.restoreGState()
    }
  }

  // MARK: - eyes

  private static func heartEyes(_ d: Draw, _ t: CGFloat) {
    let beat = 1 + 0.12 * max(0, sin(t * 7))
    for side in sides {
      let cx = 0.5 * side
      let s = 0.34 * beat
      d.radial(heart(cx, 0.05, s), center: CGPoint(x: cx - s * 0.3, y: -s * 0.3), radius: s * 1.4, rgb(255, 90, 120), rgb(210, 15, 55))
      d.fill(d.circle(cx - s * 0.45, 0.05 - s * 0.45, s * 0.14), rgb(255, 255, 255, 170))
    }
  }

  private static func starEyes(_ d: Draw, _ t: CGFloat) {
    for side in sides {
      d.c.saveGState()
      d.c.translateBy(x: 0.5 * side, y: 0.02)
      d.c.rotate(by: t * 90 * side * .pi / 180)
      let s = star(0, 0, 0.42, 0.18, 5)
      d.radial(s, center: .zero, radius: 0.42, rgb(255, 250, 180), rgb(255, 190, 20))
      d.stroke(s, rgb(220, 140, 0), 0.03)
      d.c.restoreGState()
    }
  }

  private static func tears(_ d: Draw, _ t: CGFloat) {
    for side in sides {
      let x0 = 0.52 * side
      // A streak down the cheek plus drops running along it.
      d.linear(
        d.roundRect(CGRect(x: x0 - 0.06, y: 0.15, width: 0.12, height: 1.15), 0.06), from: CGPoint(x: 0, y: 0.15),
        to: CGPoint(x: 0, y: 1.3), rgb(120, 190, 255, 150), rgb(120, 190, 255, 20))
      for i in 0..<3 {
        let y = fall(t, i + (side < 0 ? 0 : 7), 0.9, 0.2, 1.6)
        let a = 255 * (1 - min(1, max(0, (y - 0.2) / 1.4)))
        d.fill(drop(x0, y, 0.09), rgb(110, 180, 255, a))
      }
    }
  }

  // MARK: - face

  private static func blush(_ d: Draw, _ face: ArFace) {
    for cheek in [face.toLocal(face.leftCheek), face.toLocal(face.rightCheek)] {
      d.radial(d.circle(cheek.x, cheek.y, 0.32), center: cheek, radius: 0.32, rgb(255, 90, 120, 150), rgb(255, 90, 120, 0))
      for k in 0...2 {
        let x = cheek.x - 0.12 + 0.12 * CGFloat(k)
        d.line(x, cheek.y - 0.06, x - 0.05, cheek.y + 0.06, rgb(255, 255, 255, 170), 0.025)
      }
    }
  }

  private static func mustache(_ d: Draw, _ face: ArFace) {
    let nose = face.toLocal(face.nose)
    let mouth = face.toLocal(face.mouth)
    let y = nose.y + (mouth.y - nose.y) * 0.45
    let half = CGMutablePath()
    half.move(to: CGPoint(x: 0, y: y - 0.05))
    half.addCurve(to: CGPoint(x: 0.55, y: y + 0.02), control1: CGPoint(x: 0.18, y: y - 0.2), control2: CGPoint(x: 0.45, y: y - 0.16))
    half.addCurve(to: CGPoint(x: 0.8, y: y - 0.02), control1: CGPoint(x: 0.62, y: y + 0.12), control2: CGPoint(x: 0.74, y: y + 0.12))
    half.addCurve(to: CGPoint(x: 0.35, y: y + 0.12), control1: CGPoint(x: 0.76, y: y + 0.24), control2: CGPoint(x: 0.5, y: y + 0.26))
    half.addCurve(to: CGPoint(x: 0, y: y + 0.12), control1: CGPoint(x: 0.22, y: y + 0.02), control2: CGPoint(x: 0.1, y: y + 0.08))
    half.closeSubpath()
    let top = CGPoint(x: 0, y: y - 0.2)
    let bottom = CGPoint(x: 0, y: y + 0.25)
    d.linear(half, from: top, to: bottom, rgb(80, 50, 30), rgb(35, 20, 12))
    d.c.saveGState()
    d.c.scaleBy(x: -1, y: 1)
    d.linear(half, from: top, to: bottom, rgb(80, 50, 30), rgb(35, 20, 12))
    d.c.restoreGState()
  }

  private static func clown(_ d: Draw, _ face: ArFace) {
    // Curly hair tufts by the temples.
    let hair = [rgb(255, 80, 60), rgb(255, 150, 40)]
    for side in sides {
      for k in 0..<5 {
        let kf = CGFloat(k)
        d.fill(d.circle((1.0 + 0.12 * CGFloat(k % 2)) * side, -0.95 + 0.28 * kf - 0.2, 0.22), hair[k % 2])
      }
    }
    let cy = face.toLocal(face.nose).y - 0.08
    d.radial(d.circle(0, cy, 0.28), center: CGPoint(x: -0.08, y: cy - 0.1), radius: 0.34, rgb(255, 100, 100), rgb(190, 0, 20))
    d.fill(d.oval(CGRect(x: -0.14, y: cy - 0.19, width: 0.12, height: 0.1)), rgb(255, 255, 255, 200))
  }

  private static func rainbowMouth(_ d: Draw, _ face: ArFace, _ t: CGFloat) {
    let open = face.mouthOpen()
    if open < 0.2 { return }
    let mb = face.toLocal(face.mouthBottom)
    let mouth = face.toLocal(face.mouth)
    let top = (mouth.y + mb.y) / 2
    let colors = [
      rgb(255, 60, 60), rgb(255, 150, 40), rgb(255, 225, 50), rgb(70, 200, 90), rgb(50, 140, 255), rgb(140, 80, 230),
    ]
    let len = 1.4 + 1.6 * open
    let band: CGFloat = 0.075
    let width = band * CGFloat(colors.count)
    for (i, col) in colors.enumerated() {
      let x = -width / 2 + band * (CGFloat(i) + 0.5)
      let p = CGMutablePath()
      p.move(to: CGPoint(x: x, y: top))
      var y = top
      while y < top + len {
        y += 0.1
        let spread = (y - top) * 0.35
        p.addLine(to: CGPoint(x: x * (1 + spread * 3) + 0.05 * sin(y * 6 - t * 10), y: y))
      }
      d.stroke(p, col, band * 1.15, cap: .butt)
    }
  }

  // MARK: - particles

  private static func floatingHearts(_ d: Draw, _ t: CGFloat) {
    for i in 0..<10 {
      let side: CGFloat = i % 2 == 0 ? -1 : 1
      let y = fall(t, i, 0.25, 1.6, -2.4)
      let progress = min(1, max(0, (1.6 - y) / 4))
      let x = side * (0.95 + 0.7 * hash(i, 3)) + 0.12 * sin(t * 2 + CGFloat(i))
      let s = 0.14 + 0.12 * hash(i, 4)
      let alpha = 255 * (1 - progress * progress)
      d.fill(heart(x, y, s), i % 3 == 0 ? rgb(255, 120, 170, alpha) : rgb(240, 40, 80, alpha))
    }
  }

  private static func moneyRain(_ d: Draw, _ t: CGFloat) {
    for i in 0..<14 {
      let side: CGFloat = i % 2 == 0 ? -1 : 1
      let x = side * (0.2 + 1.7 * hash(i, 5))
      let y = fall(t, i, 0.3 + 0.2 * hash(i, 6), -2.8, 2.4)
      let spin = abs(cos(t * 5 + CGFloat(i)))
      coin(d, x, y, 0.17, spin)
    }
  }

  private static func sparkles(_ d: Draw, _ t: CGFloat) {
    for i in 0..<14 {
      let a = 2 * CGFloat.pi * hash(i, 7)
      let r = 1.3 + 0.6 * hash(i, 8)
      let x = cos(a) * r * 1.1
      let y = -0.4 + sin(a) * r
      let tw = twinkle(t, i)
      if tw > 0.05 { sparkle(d, x, y, 0.26 * tw, i % 3 == 0 ? rgb(255, 230, 120) : rgb(255, 255, 255)) }
    }
  }

  // MARK: - helpers

  /// Stable pseudo-random 0..1 for particle i, channel k (Float maths, as on Android).
  private static func hash(_ i: Int, _ k: Int) -> CGFloat {
    let v = sinf(Float(i) * 12.9898 + Float(k) * 78.233) * 43758.547
    return CGFloat(v - floorf(v))
  }

  /// Particle position going from `from` to `to`, `speed` loops per second, looping.
  private static func fall(_ t: CGFloat, _ i: Int, _ speed: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
    let p = t * speed + hash(i, 9)
    return from + (to - from) * (p - floor(p))
  }

  /// 0..1 twinkle: short flashes at a per-particle phase.
  private static func twinkle(_ t: CGFloat, _ i: Int) -> CGFloat {
    let p = t * (0.7 + 0.6 * hash(i, 10)) + hash(i, 11)
    let f = p - floor(p)
    let s = max(0, sin(f * .pi * 2))
    return s * s
  }

  private static func heart(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy + s * 0.9))
    p.addCurve(
      to: CGPoint(x: cx, y: cy - s * 0.5), control1: CGPoint(x: cx - s * 1.6, y: cy - s * 0.2),
      control2: CGPoint(x: cx - s * 0.7, y: cy - s * 1.4))
    p.addCurve(
      to: CGPoint(x: cx, y: cy + s * 0.9), control1: CGPoint(x: cx + s * 0.7, y: cy - s * 1.4),
      control2: CGPoint(x: cx + s * 1.6, y: cy - s * 0.2))
    p.closeSubpath()
    return p
  }

  private static func star(_ cx: CGFloat, _ cy: CGFloat, _ outer: CGFloat, _ inner: CGFloat, _ points: Int) -> CGPath {
    let p = CGMutablePath()
    for k in 0..<(points * 2) {
      let r = k % 2 == 0 ? outer : inner
      let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / CGFloat(points)
      let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
      if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
  }

  private static func drop(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy - s * 1.6))
    p.addCurve(to: CGPoint(x: cx, y: cy + s), control1: CGPoint(x: cx + s, y: cy - s * 0.4), control2: CGPoint(x: cx + s, y: cy + s))
    p.addCurve(
      to: CGPoint(x: cx, y: cy - s * 1.6), control1: CGPoint(x: cx - s, y: cy + s), control2: CGPoint(x: cx - s, y: cy - s * 0.4))
    p.closeSubpath()
    return p
  }

  private static func sparkle(_ d: Draw, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    let c = CGPoint(x: cx, y: cy)
    p.move(to: CGPoint(x: cx, y: cy - s))
    p.addQuadCurve(to: CGPoint(x: cx + s, y: cy), control: c)
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + s), control: c)
    p.addQuadCurve(to: CGPoint(x: cx - s, y: cy), control: c)
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - s), control: c)
    p.closeSubpath()
    d.fill(p, color)
  }

  private static func gem(_ d: Draw, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: CGColor) {
    d.radial(d.circle(cx, cy, r), center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.3), radius: r * 1.3, rgb(255, 255, 255), color)
  }

  private static func flower(_ d: Draw, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: CGColor) {
    for k in 0..<5 {
      let a = 2 * CGFloat.pi * CGFloat(k) / 5 - .pi / 2
      d.fill(d.circle(cx + cos(a) * r * 0.55, cy + sin(a) * r * 0.55, r * 0.48), color)
    }
    d.fill(d.circle(cx, cy, r * 0.35), rgb(255, 235, 120))
  }

  /// A gold coin turning around its vertical axis (spin 0..1 = its visible width).
  private static func coin(_ d: Draw, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ spin: CGFloat) {
    let w = r * (0.15 + 0.85 * spin)
    d.linear(
      d.oval(CGRect(x: cx - w, y: cy - r, width: 2 * w, height: 2 * r)), from: CGPoint(x: cx - w, y: cy - r),
      to: CGPoint(x: cx + w, y: cy + r), rgb(255, 235, 130), rgb(210, 150, 20))
    d.stroke(d.oval(CGRect(x: cx - w * 0.72, y: cy - r * 0.72, width: 2 * w * 0.72, height: 2 * r * 0.72)), rgb(180, 120, 10), r * 0.12)
    if spin > 0.5 {
      d.fill(star(cx, cy, r * 0.42 * spin, r * 0.18 * spin, 5), rgb(255, 245, 190))
    }
  }
}

private let arColorSpace = CGColorSpaceCreateDeviceRGB()

/// Colour from 0-255 channels (alpha may be fractional, like Android's computed alphas).
private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 255) -> CGColor {
  CGColor(colorSpace: arColorSpace, components: [r / 255, g / 255, b / 255, max(0, min(255, a)) / 255])!
}

/// The few Canvas-like drawing calls the artwork needs, on a y-down CGContext.
private struct Draw {
  let c: CGContext
  init(_ c: CGContext) { self.c = c }

  func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
  }

  func oval(_ rect: CGRect) -> CGPath { CGPath(ellipseIn: rect, transform: nil) }

  /// Android drawRect(left, top, right, bottom).
  func rect(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) -> CGPath {
    CGPath(rect: CGRect(x: l, y: t, width: r - l, height: b - t), transform: nil)
  }

  func roundRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let rr = min(radius, rect.width / 2, rect.height / 2)
    return CGPath(roundedRect: rect, cornerWidth: rr, cornerHeight: rr, transform: nil)
  }

  func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    return p
  }

  /// Android drawArc(oval, startDeg, sweepDeg): angles clockwise from +x in
  /// y-down space. Sampled, so it means exactly the same as on Android.
  func arc(_ oval: CGRect, _ startDeg: CGFloat, _ sweepDeg: CGFloat, closed: Bool = false) -> CGPath {
    let p = CGMutablePath()
    let steps = 32
    for k in 0...steps {
      let a = (startDeg + sweepDeg * CGFloat(k) / CGFloat(steps)) * .pi / 180
      let pt = CGPoint(x: oval.midX + cos(a) * oval.width / 2, y: oval.midY + sin(a) * oval.height / 2)
      if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    if closed {
      p.addLine(to: CGPoint(x: oval.midX, y: oval.midY))
      p.closeSubpath()
    }
    return p
  }

  func fill(_ path: CGPath, _ color: CGColor) {
    c.addPath(path)
    c.setFillColor(color)
    c.fillPath()
  }

  func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat, cap: CGLineCap = .round) {
    c.addPath(path)
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineCap(cap)
    c.setLineJoin(.round)
    c.strokePath()
  }

  func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: CGColor, _ width: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x1, y: y1))
    p.addLine(to: CGPoint(x: x2, y: y2))
    stroke(p, color, width)
  }

  func linear(_ path: CGPath, from: CGPoint, to: CGPoint, _ a: CGColor, _ b: CGColor) {
    guard let g = CGGradient(colorsSpace: arColorSpace, colors: [a, b] as CFArray, locations: [0, 1]) else { return }
    c.saveGState()
    c.addPath(path)
    c.clip()
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
  }

  func radial(_ path: CGPath, center: CGPoint, radius: CGFloat, _ a: CGColor, _ b: CGColor) {
    guard let g = CGGradient(colorsSpace: arColorSpace, colors: [a, b] as CFArray, locations: [0, 1]) else { return }
    c.saveGState()
    c.addPath(path)
    c.clip()
    c.drawRadialGradient(
      g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
  }

  /// A soft glow around [path] (Android: BlurMaskFilter(radius) in face units).
  func glow(_ path: CGPath, _ color: CGColor, _ radius: CGFloat) {
    // Shadow blur is in device pixels: convert the face-unit radius.
    let ctm = c.ctm
    let unit = sqrt(ctm.a * ctm.a + ctm.b * ctm.b)
    c.saveGState()
    c.setShadow(offset: .zero, blur: radius * unit * 2, color: color)
    fill(path, color)
    c.restoreGState()
  }
}
