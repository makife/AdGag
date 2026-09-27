import SwiftUI

// SwiftUI side of the captions — mirror of android/.../editor/TextEditor.kt:
// the overlay over the preview video (drawn by the same TextRenderer as the
// export, in the rendered frame's rectangle) and the editing panel.

// MARK: - Overlay

/// Tap a caption to select it, tap it again to edit, drag to move, pinch to
/// resize, twist to rotate (two fingers also work on the selected caption
/// anywhere on the video). Tapping empty video deselects, or toggles
/// play/pause when nothing is selected.
struct TextOverlayView: View {
  @ObservedObject var viewModel: EditorViewModel
  let onEdit: (String) -> Void

  private struct DragState {
    let hitId: String?
    let wasSelected: Bool
    let start: TextLayer?
    let startSticker: StickerLayer?
    var moved = false
  }

  @State private var drag: DragState?
  /// (scale, rotation) of the selected caption/sticker when a pinch / twist began.
  @State private var pinchStart: Double?
  @State private var rotateStart: Double?

  var body: some View {
    GeometryReader { geo in
      let aspect = CGFloat(viewModel.renderAspect)
      let box = geo.size
      let frame: CGSize = box.width / max(box.height, 1) > aspect
        ? CGSize(width: box.height * aspect, height: box.height)
        : CGSize(width: box.width, height: box.width / max(aspect, 0.01))
      ZStack {
        // Letterbox bars: same rule as empty video.
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { tapEmpty() }
        captionsCanvas(frame: frame)
          .frame(width: frame.width, height: frame.height)
          .contentShape(Rectangle())
          .gesture(dragGesture(frame: frame))
          .simultaneousGesture(pinchGesture)
          .simultaneousGesture(rotationGesture)
      }
      .frame(width: box.width, height: box.height)
    }
  }

  @ViewBuilder
  private func captionsCanvas(frame: CGSize) -> some View {
    if viewModel.textLayers.isEmpty && viewModel.stickerLayers.isEmpty {
      Color.clear
    } else {
      TimelineView(.animation) { _ in
        Canvas { context, size in
          let tMs = viewModel.currentOutputMs()
          let selected = viewModel.selectedTextId
          let playing = viewModel.isPlaying
          context.withCGContext { cg in
            // Stickers under the captions (same order as the export).
            for sticker in viewModel.stickerLayers {
              let frozen = sticker.id == selected && !playing && (tMs < sticker.startMs || tMs >= sticker.endMs)
              StickerRenderer.draw(cg, layer: sticker, frameW: size.width, frameH: size.height,
                                   tMs: frozen ? min(sticker.startMs + 400, sticker.endMs - 1) : tMs)
              if sticker.id == selected {
                let half = StickerRenderer.halfSide(sticker, frameH: size.height) * 1.1
                let s = CGFloat(sticker.scale)
                cg.saveGState()
                cg.translateBy(x: CGFloat(sticker.x) * size.width, y: CGFloat(sticker.y) * size.height)
                cg.rotate(by: CGFloat(sticker.rotationDeg) * .pi / 180)
                cg.scaleBy(x: s, y: s)
                cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                cg.setLineWidth(1.5 / s)
                cg.setLineDash(phase: 0, lengths: [9 / s, 6 / s])
                cg.addPath(CGPath(roundedRect: CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half),
                                  cornerWidth: 6 / s, cornerHeight: 6 / s, transform: nil))
                cg.strokePath()
                cg.restoreGState()
              }
            }
            for layer in viewModel.textLayers {
              let frozen = layer.id == selected && !playing
              TextRenderer.draw(cg, layer: layer, frameW: size.width, frameH: size.height,
                                tMs: frozen ? TextRenderer.settledTimeMs(layer) : tMs)
              if layer.id == selected {
                let bounds = TextRenderer.localBounds(TextRenderer.layout(layer, frameH: size.height))
                let s = CGFloat(layer.scale)
                cg.saveGState()
                cg.translateBy(x: CGFloat(layer.x) * size.width, y: CGFloat(layer.y) * size.height)
                cg.rotate(by: CGFloat(layer.rotationDeg) * .pi / 180)
                cg.scaleBy(x: s, y: s)
                cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                cg.setLineWidth(1.5 / s)
                cg.setLineDash(phase: 0, lengths: [9 / s, 6 / s])
                cg.addPath(CGPath(roundedRect: bounds, cornerWidth: 6 / s, cornerHeight: 6 / s, transform: nil))
                cg.strokePath()
                cg.restoreGState()
              }
            }
          }
        }
      }
    }
  }

  private func tapEmpty() {
    if viewModel.selectedTextId != nil { viewModel.selectedTextId = nil } else { viewModel.togglePlayPause() }
  }

  private func isShown(_ id: String, _ start: Int64, _ end: Int64, at tMs: Int64) -> Bool {
    (tMs >= start && tMs < end) || (id == viewModel.selectedTextId && !viewModel.isPlaying)
  }

  private func dragGesture(frame: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if drag == nil {
          let tMs = viewModel.currentOutputMs()
          // Captions are drawn over stickers, so they win the touch.
          let hit = viewModel.textLayers.reversed().first { layer in
            isShown(layer.id, layer.startMs, layer.endMs, at: tMs)
              && TextRenderer.hitTest(layer, frameW: frame.width, frameH: frame.height, point: value.startLocation)
          }
          let stickerHit = hit != nil ? nil : viewModel.stickerLayers.reversed().first { s in
            isShown(s.id, s.startMs, s.endMs, at: tMs)
              && StickerRenderer.hitTest(s, frameW: frame.width, frameH: frame.height, point: value.startLocation)
          }
          let hitId = hit?.id ?? stickerHit?.id
          drag = DragState(hitId: hitId, wasSelected: hitId != nil && hitId == viewModel.selectedTextId,
                           start: hit, startSticker: stickerHit)
          if let hitId { viewModel.selectedTextId = hitId }
        }
        guard var state = drag else { return }
        let distance = hypot(value.translation.width, value.translation.height)
        if !state.moved && distance > 6 { state.moved = true }
        drag = state
        // Moving is for the touched caption only (pinch/rotate handle the rest).
        guard state.moved, pinchStart == nil, rotateStart == nil else { return }
        let dx = Double(value.translation.width / frame.width)
        let dy = Double(value.translation.height / frame.height)
        if let start = state.start, var layer = viewModel.textLayers.first(where: { $0.id == start.id }) {
          layer.x = min(max(start.x + dx, 0), 1)
          layer.y = min(max(start.y + dy, 0), 1)
          viewModel.updateText(layer)
        } else if let start = state.startSticker,
                  var sticker = viewModel.stickerLayers.first(where: { $0.id == start.id }) {
          sticker.x = min(max(start.x + dx, 0), 1)
          sticker.y = min(max(start.y + dy, 0), 1)
          viewModel.updateSticker(sticker)
        }
      }
      .onEnded { _ in
        if let state = drag, !state.moved {
          if state.hitId == nil {
            tapEmpty()
          } else if state.wasSelected, let id = state.hitId {
            onEdit(id)
          }
        }
        drag = nil
      }
  }

  private var pinchGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        guard let id = viewModel.selectedTextId else { return }
        drag?.moved = true
        if var layer = viewModel.textLayers.first(where: { $0.id == id }) {
          let start = pinchStart ?? layer.scale
          if pinchStart == nil { pinchStart = start }
          layer.scale = min(max(start * Double(value), 0.2), 8)
          viewModel.updateText(layer)
        } else if var sticker = viewModel.stickerLayers.first(where: { $0.id == id }) {
          let start = pinchStart ?? sticker.scale
          if pinchStart == nil { pinchStart = start }
          sticker.scale = min(max(start * Double(value), 0.2), 8)
          viewModel.updateSticker(sticker)
        }
      }
      .onEnded { _ in pinchStart = nil }
  }

  private var rotationGesture: some Gesture {
    RotationGesture()
      .onChanged { angle in
        guard let id = viewModel.selectedTextId else { return }
        drag?.moved = true
        if var layer = viewModel.textLayers.first(where: { $0.id == id }) {
          let start = rotateStart ?? layer.rotationDeg
          if rotateStart == nil { rotateStart = start }
          layer.rotationDeg = start + angle.degrees
          viewModel.updateText(layer)
        } else if var sticker = viewModel.stickerLayers.first(where: { $0.id == id }) {
          let start = rotateStart ?? sticker.rotationDeg
          if rotateStart == nil { rotateStart = start }
          sticker.rotationDeg = start + angle.degrees
          viewModel.updateSticker(sticker)
        }
      }
      .onEnded { _ in rotateStart = nil }
  }
}

// MARK: - Editing panel

private enum TextTab: String, CaseIterable {
  case font = "Font", style = "Style", motion = "In", exit = "Out", color = "Color", size = "Size"
}

/// Edits one caption: its words, then Font / Style / In / Out / Color / Size.
/// Shown IN PLACE of the timeline and tools (not over the video), so the
/// video just gets a bit smaller and every change shows there live. Font,
/// style and motion choices are live renders of the caption itself.
struct TextEditorPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let layerId: String
  let onClose: () -> Void

  @State private var tab: TextTab = .style

  var body: some View {
    if let layer = viewModel.textLayers.first(where: { $0.id == layerId }) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Text("Text").font(.headline).foregroundColor(.white)
          TextField("Type something", text: Binding(
            get: { layer.text },
            set: { var l = layer; l.text = String($0.prefix(120)); viewModel.updateText(l) }))
            .foregroundColor(.white)
            .padding(10)
            .background(EditorPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          Button("Delete") {
            viewModel.removeText(layerId)
            onClose()
          }
          .foregroundColor(EditorPalette.danger)
          Button("Done", action: onClose).foregroundColor(EditorPalette.pink)
        }
        HStack(spacing: 6) {
          ForEach(TextTab.allCases, id: \.self) { t in
            Button { tab = t } label: {
              Text(t.rawValue).font(.caption).fontWeight(.semibold)
                .foregroundColor(t == tab ? EditorPalette.pink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(t == tab ? EditorPalette.pink.opacity(0.25) : EditorPalette.surface)
                .clipShape(Capsule())
            }
          }
        }
        Group {
          switch tab {
          case .font:
            PreviewChipRow(items: TextFonts.all.map(\.id), isSelected: { $0 == layer.fontId },
                           preview: { id in
                             var l = layer; l.fontId = id; l.text = TextFonts.byId(id).label; l.animation = .NONE
                             return l
                           }, label: nil, animated: false,
                           onSelect: { id in var l = layer; l.fontId = id; viewModel.updateText(l) })
          case .style:
            PreviewChipRow(items: TextStyleEffect.allCases, isSelected: { $0 == layer.style },
                           preview: { style in var l = layer; l.style = style; l.text = "Aa"; l.animation = .NONE; return l },
                           label: { $0.label }, animated: false,
                           onSelect: { style in var l = layer; l.style = style; viewModel.updateText(l) })
          case .motion:
            PreviewChipRow(items: TextAnimation.allCases, isSelected: { $0 == layer.animation },
                           preview: { anim in var l = layer; l.animation = anim; l.text = "Wow"; return l },
                           label: { $0.label }, animated: true,
                           onSelect: { anim in var l = layer; l.animation = anim; viewModel.updateText(l) })
          case .exit:
            // Each chip shows the word, then it leaving (looping).
            PreviewChipRow(items: TextExit.allCases, isSelected: { $0 == layer.exit },
                           preview: { exit in var l = layer; l.exit = exit; l.text = "Bye"; l.animation = .NONE; return l },
                           label: { $0.label }, animated: true,
                           onSelect: { exit in var l = layer; l.exit = exit; viewModel.updateText(l) },
                           previewEndMs: 1_600, loopMs: 2_100)
          case .color:
            ColorTab(layer: layer) { viewModel.updateText($0) }
          case .size:
            SizeTab(layer: layer) { viewModel.updateText($0) }
          }
        }
        .frame(height: 116, alignment: .top)
      }
      .onDisappear { viewModel.removeTextIfBlank(layerId) }
    }
  }
}

/// Horizontally scrolling chips, each a live render of the caption with one option applied.
private struct PreviewChipRow<Item: Hashable>: View {
  let items: [Item]
  let isSelected: (Item) -> Bool
  let preview: (Item) -> TextLayer
  let label: ((Item) -> String)?
  let animated: Bool
  let onSelect: (Item) -> Void
  /// Where the chip's caption ends (exit previews); otherwise it never ends.
  var previewEndMs: Int64 = Int64.max / 4
  var loopMs: Int64 = 2_400

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(items, id: \.self) { item in
          let selected = isSelected(item)
          Button { onSelect(item) } label: {
            VStack(spacing: 4) {
              chip(preview(item))
                .frame(width: label == nil ? 104 : 76, height: label == nil ? 96 : 72)
                .background(Color(red: 0.16, green: 0.16, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                  .stroke(selected ? EditorPalette.pink : EditorPalette.border, lineWidth: selected ? 2 : 1))
              if let label {
                Text(label(item)).font(.caption2)
                  .foregroundColor(selected ? EditorPalette.pink : EditorPalette.muted).lineLimit(1)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func chip(_ base: TextLayer) -> some View {
    if animated {
      TimelineView(.animation) { context in
        let t = Int64(context.date.timeIntervalSinceReferenceDate * 1000) % loopMs
        canvas(base, tMs: t)
      }
    } else {
      canvas(base, tMs: 10_000)
    }
  }

  private func canvas(_ base: TextLayer, tMs: Int64) -> some View {
    Canvas { context, size in
      var layer = base
      layer.x = 0.5
      layer.y = 0.5
      layer.rotationDeg = 0
      layer.opacity = 1
      layer.align = .CENTER
      layer.startMs = 0
      layer.endMs = previewEndMs
      layer.sizeFrac = 0.3
      let layout = TextRenderer.layout(layer, frameH: size.height)
      layer.scale = Double(min(1, size.width * 0.72 / max(1, layout.width)))
      context.withCGContext { cg in
        TextRenderer.draw(cg, layer: layer, frameW: size.width, frameH: size.height, tMs: tMs)
      }
    }
  }
}

private let spectrum: [(CGFloat, CGFloat, CGFloat)] = [
  (1, 1, 1), (1, 0.09, 0.27), (1, 0.57, 0), (1, 0.92, 0), (0, 0.9, 0.46),
  (0, 0.9, 1), (0.16, 0.47, 1), (0.84, 0, 0.98), (1, 0.09, 0.27), (0, 0, 0),
]

/// Colour at `f` (0...1) along the spectrum bar.
private func spectrumAt(_ f: CGFloat) -> Int32 {
  let x = min(max(f, 0), 1) * CGFloat(spectrum.count - 1)
  let i = min(Int(x), spectrum.count - 2)
  let t = x - CGFloat(i)
  let a = spectrum[i]
  let b = spectrum[i + 1]
  return argbFrom(r: a.0 + (b.0 - a.0) * t, g: a.1 + (b.1 - a.1) * t, b: a.2 + (b.2 - a.2) * t)
}

private func swiftUIColor(_ argb: Int32) -> Color {
  let c = argbComponents(argb)
  return Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
}

private struct ColorTab: View {
  let layer: TextLayer
  let onChange: (TextLayer) -> Void
  /// 0 = text colour, 1 = second colour (outline / glow / box / shadow / 3D).
  @State private var target = 0

  private func set(_ color: Int32) {
    var l = layer
    if target == 0 { l.color = color } else { l.accentColor = color }
    onChange(l)
  }

  var body: some View {
    let current = target == 0 ? layer.color : layer.accentColor
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        ForEach(0..<2, id: \.self) { i in
          Button { target = i } label: {
            HStack(spacing: 6) {
              Circle().fill(swiftUIColor(i == 0 ? layer.color : layer.accentColor)).frame(width: 12, height: 12)
              Text(i == 0 ? "Text" : "Effect colour").font(.caption)
                .foregroundColor(i == target ? EditorPalette.pink : .white)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(i == target ? EditorPalette.pink.opacity(0.25) : EditorPalette.surface)
            .clipShape(Capsule())
          }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(textPalette, id: \.self) { c in
            Button { set(c) } label: {
              Circle().fill(swiftUIColor(c)).frame(width: 32, height: 32)
                .overlay(Circle().stroke(c == current ? EditorPalette.pink : EditorPalette.border,
                                         lineWidth: c == current ? 3 : 1))
            }
          }
        }
        .padding(.vertical, 2)
      }
      // Full colour scale: drag along the spectrum.
      GeometryReader { geo in
        LinearGradient(colors: spectrum.map { Color(red: Double($0.0), green: Double($0.1), blue: Double($0.2)) },
                       startPoint: .leading, endPoint: .trailing)
          .clipShape(Capsule())
          .contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            set(spectrumAt(value.location.x / max(geo.size.width, 1)))
          })
      }
      .frame(height: 26)
      LabeledSlider(title: "Opacity", value: layer.opacity, range: 0.1...1) {
        var l = layer; l.opacity = $0; onChange(l)
      }
    }
  }
}

private struct SizeTab: View {
  let layer: TextLayer
  let onChange: (TextLayer) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledSlider(title: "Size", value: layer.sizeFrac, range: 0.025...0.2) {
        var l = layer; l.sizeFrac = $0; onChange(l)
      }
      LabeledSlider(title: "Letter spacing", value: layer.letterSpacing, range: -0.05...0.6) {
        var l = layer; l.letterSpacing = $0; onChange(l)
      }
      HStack(spacing: 8) {
        ForEach(TextLayerAlign.allCases, id: \.self) { a in
          Button { var l = layer; l.align = a; onChange(l) } label: {
            Text(a.label).font(.caption)
              .foregroundColor(a == layer.align ? EditorPalette.pink : .white)
              .padding(.horizontal, 12).padding(.vertical, 6)
              .background(a == layer.align ? EditorPalette.pink.opacity(0.25) : EditorPalette.surface)
              .clipShape(Capsule())
          }
        }
        Spacer()
        Button("Straighten") {
          var l = layer; l.rotationDeg = 0; l.scale = 1; l.x = 0.5; onChange(l)
        }
        .font(.caption).foregroundColor(EditorPalette.pink)
      }
    }
  }
}

private struct LabeledSlider: View {
  let title: String
  let value: Double
  let range: ClosedRange<Double>
  let onChange: (Double) -> Void

  var body: some View {
    HStack {
      Text(title).font(.caption).foregroundColor(EditorPalette.muted).frame(width: 96, alignment: .leading)
      Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: onChange), in: range)
        .tint(EditorPalette.pink)
    }
  }
}
