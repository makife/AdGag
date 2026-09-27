import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UIKit

// Mirror of android/.../editor/Stickers.kt + StickerPanel.kt: animated
// stickers from Google's Noto Animated Emoji (CC BY 4.0, AdGagStickers/
// LICENSE.txt), pre-packed into one sprite sheet per sticker (uniform 50ms
// frames, 192px, WebP) + stickers.json — the SAME files as Android. A sheet
// lets the preview and the export draw any frame at any time.

// MARK: - Model

/// Same JSON keys as the Kotlin StickerLayer. Centre as frame fractions,
/// size (the long side) a fraction of the frame HEIGHT, OUTPUT-time start/end.
struct StickerLayer: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var stickerId: String
  var sizeFrac: Double = 0.16
  var x: Double = 0.5
  var y: Double = 0.35
  var rotationDeg: Double = 0
  var scale: Double = 1
  var flipX: Bool = false
  var startMs: Int64 = 0
  var endMs: Int64 = 3_000

  static func from(_ o: [String: Any]) -> StickerLayer {
    func d(_ key: String, _ fallback: Double) -> Double { (o[key] as? NSNumber)?.doubleValue ?? fallback }
    func i64(_ key: String, _ fallback: Int64) -> Int64 { (o[key] as? NSNumber)?.int64Value ?? fallback }
    var s = StickerLayer(stickerId: o["stickerId"] as? String ?? "")
    s.id = o["id"] as? String ?? UUID().uuidString
    s.sizeFrac = d("sizeFrac", 0.16)
    s.x = d("x", 0.5)
    s.y = d("y", 0.35)
    s.rotationDeg = d("rotationDeg", 0)
    s.scale = d("scale", 1)
    s.flipX = o["flipX"] as? Bool ?? false
    s.startMs = i64("startMs", 0)
    s.endMs = i64("endMs", 3_000)
    return s
  }
}

struct StickerDef: Codable, Identifiable {
  let id: String
  let label: String
  /// A file name in AdGagStickers, or an absolute path when `local`.
  let file: String
  let frames: Int
  let cols: Int
  let size: Int
  let durationMs: Int64
  /// Cell size (non-square stickers keep their aspect); the bundled ones are size x size.
  var w: Int
  var h: Int
  var local: Bool

  init(id: String, label: String, file: String, frames: Int, cols: Int, size: Int, durationMs: Int64,
       w: Int? = nil, h: Int? = nil, local: Bool = false) {
    self.id = id
    self.label = label
    self.file = file
    self.frames = frames
    self.cols = cols
    self.size = size
    self.durationMs = durationMs
    self.w = w ?? size
    self.h = h ?? size
    self.local = local
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let size = try c.decode(Int.self, forKey: .size)
    self.init(id: try c.decode(String.self, forKey: .id),
              label: try c.decodeIfPresent(String.self, forKey: .label) ?? "",
              file: try c.decode(String.self, forKey: .file),
              frames: try c.decode(Int.self, forKey: .frames),
              cols: try c.decode(Int.self, forKey: .cols),
              size: size,
              durationMs: try c.decode(Int64.self, forKey: .durationMs),
              w: try c.decodeIfPresent(Int.self, forKey: .w),
              h: try c.decodeIfPresent(Int.self, forKey: .h),
              local: try c.decodeIfPresent(Bool.self, forKey: .local) ?? false)
  }

  var aspect: CGFloat { CGFloat(w) / CGFloat(max(h, 1)) }

  /// Frame shown `localMs` into the sticker's time on screen (loops).
  func frameAt(_ localMs: Int64) -> Int {
    guard frames > 1, durationMs > 0 else { return 0 }
    let t = ((localMs % durationMs) + durationMs) % durationMs
    return min(max(Int(t * Int64(frames) / durationMs), 0), frames - 1)
  }
}

// MARK: - Store

/// Catalog + decoded sheets. Thread-safe (main thread and the compositor queue).
final class StickerStore: @unchecked Sendable {
  static let shared = StickerStore()

  let all: [StickerDef]
  private let lock = NSLock()
  private var sheets: [String: CGImage] = [:]
  private var order: [String] = []
  private var smallSheets: [String: CGImage] = [:]
  private var smallOrder: [String] = []

  private init() {
    if let url = Bundle.main.url(forResource: "stickers", withExtension: "json", subdirectory: "AdGagStickers"),
       let data = try? Data(contentsOf: url),
       let list = try? JSONDecoder().decode([StickerDef].self, from: data) {
      all = list
    } else {
      NSLog("AdGag: sticker catalog missing")
      all = []
    }
  }

  func byId(_ id: String) -> StickerDef? { all.first { $0.id == id } }

  private func url(of def: StickerDef) -> URL? {
    if def.local { return URL(fileURLWithPath: def.file) }
    return Bundle.main.url(forResource: (def.file as NSString).deletingPathExtension,
                           withExtension: (def.file as NSString).pathExtension, subdirectory: "AdGagStickers")
  }

  func sheet(_ def: StickerDef) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    if let s = sheets[def.file] { return s }
    guard let url = url(of: def),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { return nil }
    // Keep the 10 most recently used full sheets (each a few MB decoded).
    sheets[def.file] = image
    order.removeAll { $0 == def.file }
    order.append(def.file)
    if order.count > 10 { sheets.removeValue(forKey: order.removeFirst()) }
    return image
  }

  /// Half-resolution sheet for the picker's animated thumbnails (decoded off the main thread by the caller).
  func smallSheet(_ def: StickerDef) -> CGImage? {
    lock.lock()
    if let s = smallSheets[def.file] { lock.unlock(); return s }
    lock.unlock()
    guard let url = url(of: def), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let pw = props[kCGImagePropertyPixelWidth] as? Int, let ph = props[kCGImagePropertyPixelHeight] as? Int,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pw, ph) / 2,
          ] as CFDictionary)
    else { return nil }
    lock.lock()
    smallSheets[def.file] = image
    smallOrder.removeAll { $0 == def.file }
    smallOrder.append(def.file)
    if smallOrder.count > 40 { smallSheets.removeValue(forKey: smallOrder.removeFirst()) }
    lock.unlock()
    return image
  }

  /// Already-decoded small sheet, or nil (never decodes — safe to call while drawing).
  func cachedSmallSheet(_ def: StickerDef) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    return smallSheets[def.file]
  }

  /// One frame cut out of a sheet (full or small), honouring non-square cells.
  static func frame(_ def: StickerDef, in sheet: CGImage, _ index: Int) -> CGImage? {
    let cw = sheet.width / max(def.cols, 1)
    let ch = max(1, cw * def.h / max(def.w, 1))
    return sheet.cropping(to: CGRect(x: (index % def.cols) * cw, y: (index / def.cols) * ch, width: cw, height: ch))
  }

  func frame(_ def: StickerDef, _ index: Int) -> CGImage? {
    guard let sheet = sheet(def) else { return nil }
    return Self.frame(def, in: sheet, index)
  }
}

// MARK: - Renderer

enum StickerRenderer {
  private static let popMs: Int64 = 250
  private static let outMs: Int64 = 200

  private static func backOut(_ t: CGFloat) -> CGFloat {
    let c1: CGFloat = 1.70158
    let c3 = c1 + 1
    let x = min(max(t, 0), 1) - 1
    return 1 + c3 * x * x * x + c1 * x * x
  }

  /// Half width / height in frame units before its own scale: the LONG side is sizeFrac of the frame height.
  static func halfSize(_ layer: StickerLayer, frameH: CGFloat) -> CGSize {
    let long = CGFloat(layer.sizeFrac) * frameH / 2
    let aspect = StickerStore.shared.byId(layer.stickerId)?.aspect ?? 1
    return aspect >= 1 ? CGSize(width: long, height: long / aspect) : CGSize(width: long * aspect, height: long)
  }

  static func hitTest(_ layer: StickerLayer, frameW: CGFloat, frameH: CGFloat, point: CGPoint) -> Bool {
    let rad = -CGFloat(layer.rotationDeg) * .pi / 180
    let dx = point.x - CGFloat(layer.x) * frameW
    let dy = point.y - CGFloat(layer.y) * frameH
    let s = CGFloat(layer.scale)
    let lx = (dx * cos(rad) - dy * sin(rad)) / s
    let ly = (dx * sin(rad) + dy * cos(rad)) / s
    let half = halfSize(layer, frameH: frameH)
    return abs(lx) <= half.width * 1.1 && abs(ly) <= half.height * 1.1
  }

  /// Draws into a y-DOWN context whose units are the frame's.
  static func draw(_ ctx: CGContext, layer: StickerLayer, frameW: CGFloat, frameH: CGFloat, tMs: Int64) {
    guard tMs >= layer.startMs, tMs < layer.endMs,
          let def = StickerStore.shared.byId(layer.stickerId) else { return }
    let local = tMs - layer.startMs
    let pop = local < popMs ? max(backOut(CGFloat(local) / CGFloat(popMs)), 0.01) : 1
    let remaining = layer.endMs - tMs
    let alpha = remaining < outMs ? min(max(CGFloat(remaining) / CGFloat(outMs), 0), 1) : 1
    guard alpha > 0.001, let image = StickerStore.shared.frame(def, def.frameAt(local)) else { return }
    let half = halfSize(layer, frameH: frameH)
    let s = CGFloat(layer.scale) * pop
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(layer.x) * frameW, y: CGFloat(layer.y) * frameH)
    ctx.rotate(by: CGFloat(layer.rotationDeg) * .pi / 180)
    // CGContext.draw expects y-up: flip vertically (about the centre) in this y-down space.
    ctx.scaleBy(x: layer.flipX ? -s : s, y: -s)
    ctx.setAlpha(alpha)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: -half.width, y: -half.height, width: 2 * half.width, height: 2 * half.height))
    ctx.restoreGState()
  }
}

// MARK: - Picker panel

/// Shown in place of the timeline + tools (never over the video): the
/// bundled animated emoji, every thumbnail animating. From the "Stickers" tool it ADDS the tapped
/// sticker at the playhead; on an existing sticker it REPLACES it and
/// offers Flip / Delete.
struct StickerPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let editingId: String?
  let onClose: () -> Void

  private func pick(_ def: StickerDef) {
    if let id = editingId, var s = viewModel.stickerLayers.first(where: { $0.id == id }) {
      s.stickerId = def.id
      viewModel.updateSticker(s)
    } else {
      viewModel.addSticker(def)
      onClose()
    }
  }

  var body: some View {
    let editing = editingId.flatMap { id in viewModel.stickerLayers.first { $0.id == id } }
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(editing != nil ? "Change sticker" : "Stickers").font(.headline).foregroundColor(.white)
        Spacer()
        if let editing {
          Button("Flip") {
            var s = editing
            s.flipX.toggle()
            viewModel.updateSticker(s)
          }
          .foregroundColor(.white)
          Button("Delete") {
            viewModel.removeSticker(editing.id)
            onClose()
          }
          .foregroundColor(EditorPalette.danger)
        }
        Button("Done", action: onClose).foregroundColor(EditorPalette.pink)
      }
      EmojiGrid(selectedId: editing?.stickerId, onPick: pick)
    }
  }
}

private struct EmojiGrid: View {
  let selectedId: String?
  let onPick: (StickerDef) -> Void
  @State private var loaded: Set<String> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
          ForEach(StickerStore.shared.all) { def in
            let selected = selectedId == def.id
            Button { onPick(def) } label: {
              ZStack {
                (selected ? EditorPalette.pink.opacity(0.25) : EditorPalette.surface)
                if loaded.contains(def.id) {
                  TimelineView(.animation) { context in
                    let ms = Int64(context.date.timeIntervalSinceReferenceDate * 1000)
                    if let sheet = StickerStore.shared.cachedSmallSheet(def),
                       let frame = StickerStore.frame(def, in: sheet, def.frameAt(ms)) {
                      Image(decorative: frame, scale: 1).resizable().scaledToFit().padding(6)
                    }
                  }
                }
              }
              .frame(width: 60, height: 60)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? EditorPalette.pink : Color.clear, lineWidth: 2))
            }
            .accessibilityLabel(def.label)
            .task {
              await Task.detached(priority: .utility) { _ = StickerStore.shared.smallSheet(def) }.value
              loaded.insert(def.id)
            }
          }
        }
      }
      .frame(height: 196)
      Text("Animated emoji: Google Noto Emoji (CC BY 4.0)").font(.caption2).foregroundColor(EditorPalette.muted)
    }
  }
}
