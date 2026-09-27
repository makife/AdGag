import SwiftUI

// SwiftUI mirror of android/.../editor/EditorTimeline.kt:
// 1. clip strip (SOURCE time) with a transition button on every boundary
//    and "+" to record another clip;
// 2. trim row for the selected clip (its whole source, cut parts dimmed);
// 3. music row (OUTPUT time) — trim handles on both ends, drag to move;
// 4. song row — the whole song, the used section a window slid anywhere.
// Drags only change local @State; the real (rebuilding) edit is committed
// once, on release.

enum EditorPalette {
  static let background = Color.black
  static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
  static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.18)
  static let border = Color(white: 0.3)
  static let muted = Color(white: 0.62)
  static let pink = Color(red: 1.0, green: 0.24, blue: 0.62)
  static let blue = Color(red: 0.27, green: 0.45, blue: 1.0)
  static let danger = Color(red: 1.0, green: 0.35, blue: 0.35)
  static let brand = LinearGradient(
    colors: [Color(red: 0.27, green: 0.45, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 1.0),
             Color(red: 1.0, green: 0.24, blue: 0.62), Color(red: 1.0, green: 0.55, blue: 0.2)],
    startPoint: .leading, endPoint: .trailing)
}

private let stripHeight: CGFloat = 56
private let rowHeight: CGFloat = 56
private let musicRowHeight: CGFloat = 32
private let songRowHeight: CGFloat = 40
private let textRowHeight: CGFloat = 30
private let addButtonSize: CGFloat = 48
private let handleHitWidth: CGFloat = 32
private let handleWidth: CGFloat = 16

struct EditorTimelineView: View {
  @ObservedObject var viewModel: EditorViewModel
  let onAddClip: () -> Void
  let onPickTransition: (Int) -> Void
  let onOpenMusic: () -> Void
  var onAddText: () -> Void = {}
  var onEditText: (String) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        label("Clips")
        Spacer()
        label((viewModel.videoSpeed != 1 ? "\(formatSpeed(viewModel.videoSpeed)) · " : "")
          + "\(formatClock(viewModel.outputDurationMs)) / \(formatClock(EditorLimits.maxTotalMs))")
      }
      aligned(trailing: AnyView(addButton)) { ClipStripView(viewModel: viewModel, onPickTransition: onPickTransition) }

      let index = viewModel.selectedClipIndex
      if viewModel.clips.indices.contains(index) {
        let clip = viewModel.clips[index]
        HStack {
          label(viewModel.clips.count > 1 ? "Clip \(index + 1) · trim" : "Trim")
          Spacer()
          label("\(formatClock(clip.trimStartMs)) – \(formatClock(clip.trimEndMs))")
          if viewModel.clips.count > 1 {
            Button("Delete clip") { viewModel.removeClip(index) }
              .font(.caption).foregroundColor(EditorPalette.danger)
          }
        }
        TrimRowView(viewModel: viewModel, index: index, clip: clip)
          .id(index) // reset the row's drag state when another clip is selected
      }

      if !viewModel.textLayers.isEmpty || !viewModel.stickerLayers.isEmpty {
        let selected = overlayBars(viewModel).first { $0.id == viewModel.selectedTextId }
        HStack {
          if let selected {
            label("\(selected.kind) · \"\(String(selected.label.prefix(18)))\"")
              .lineLimit(1)
            Spacer()
            label("\(formatClock(selected.startMs)) – \(formatClock(selected.endMs))")
          } else {
            label("Text & stickers · tap one to select")
            Spacer()
          }
        }
        aligned(trailing: AnyView(addTextButton)) { TextRowView(viewModel: viewModel, onEditText: onEditText) }
      }

      if viewModel.hasMusic {
        HStack {
          label("Music" + (viewModel.musicSpeed != 1 ? " · \(formatSpeed(viewModel.musicSpeed))" : "")
            + (viewModel.musicLoop ? " · loop" : ""))
          Spacer()
          label("\(formatClock(viewModel.musicStartOffsetMs)) – "
            + formatClock(viewModel.musicStartOffsetMs + viewModel.musicPlayDurationMs))
        }
        aligned(trailing: AnyView(musicSettingsButton)) { MusicRowView(viewModel: viewModel) }
        HStack {
          label("Song section")
          Spacer()
          label("\(formatClock(viewModel.musicSourceStartMs)) – "
            + "\(formatClock(viewModel.musicSourceStartMs + viewModel.musicPlayDurationMs)) of "
            + formatClock(viewModel.musicDurationMs ?? 0))
        }
        SongRowView(viewModel: viewModel)
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.caption).foregroundColor(EditorPalette.muted)
  }

  /// Keeps the strip and the music row the same width (same time scale) either way.
  private func aligned<Content: View>(trailing: AnyView, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 8) {
      content()
      trailing.frame(width: addButtonSize)
    }
  }

  private var addButton: some View {
    Button(action: onAddClip) {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: addButtonSize, height: addButtonSize)
        .background(viewModel.canAddClip ? EditorPalette.pink : EditorPalette.border)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .disabled(!viewModel.canAddClip)
    .accessibilityLabel("Record another clip")
  }

  private var addTextButton: some View {
    Button(action: onAddText) {
      Image(systemName: "plus")
        .foregroundColor(.white)
        .frame(width: addButtonSize, height: textRowHeight)
        .background(EditorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .accessibilityLabel("Add text")
  }

  private var musicSettingsButton: some View {
    Button(action: onOpenMusic) {
      Image(systemName: "slider.horizontal.3")
        .foregroundColor(.white)
        .frame(width: addButtonSize, height: musicRowHeight)
        .background(EditorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .accessibilityLabel("Music settings")
  }
}

// MARK: - Clip strip

private struct ClipStripView: View {
  @ObservedObject var viewModel: EditorViewModel
  let onPickTransition: (Int) -> Void

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let total = max(viewModel.totalDurationMs, 1)
      let msToX = { (ms: Int64) -> CGFloat in CGFloat(ms) / CGFloat(total) * width }
      let xToMs = { (x: CGFloat) -> Int64 in Int64(min(max(x / width, 0), 1) * CGFloat(total)) }

      ZStack(alignment: .topLeading) {
        HStack(spacing: 1) {
          ForEach(Array(viewModel.clips.enumerated()), id: \.offset) { i, clip in
            let frames = (viewModel.thumbnails[clip.path] ?? [])
            let inRange = frames.filter { $0.sourceMs >= clip.trimStartMs - 1 && $0.sourceMs < clip.trimEndMs }
            ThumbnailStrip(images: (inRange.isEmpty ? Array(frames.prefix(1)) : inRange).map(\.image))
              .frame(width: max(msToX(clip.keptDurationMs) - 1, 1), height: stripHeight)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(i == viewModel.selectedClipIndex && viewModel.clips.count > 1 ? EditorPalette.pink : .clear,
                          lineWidth: 2))
          }
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in viewModel.seekToGlobal(xToMs(value.location.x)) }
            .onEnded { value in
              // A tap (no real movement) also selects the clip under it.
              if abs(value.translation.width) < 6 {
                let g = xToMs(value.location.x)
                let index = viewModel.clips.indices.last { viewModel.clipStartMs($0) <= g } ?? 0
                viewModel.selectClip(index)
              }
            })

        // Transition button on each boundary.
        ForEach(0..<max(viewModel.clips.count - 1, 0), id: \.self) { b in
          let active = b < viewModel.transitions.count && viewModel.transitions[b].type != .NONE
          Button { onPickTransition(b) } label: {
            Image(systemName: "sparkles")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.white)
              .frame(width: 28, height: 28)
              .background(active ? EditorPalette.pink : EditorPalette.surfaceElevated)
              .clipShape(Circle())
              .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
          }
          .position(x: msToX(viewModel.clipStartMs(b + 1)), y: stripHeight / 2)
          .accessibilityLabel("Transition effect")
        }

        // Playhead.
        Rectangle().fill(EditorPalette.brand)
          .frame(width: 3, height: stripHeight)
          .offset(x: msToX(min(max(viewModel.globalPositionMs, 0), total)) - 1)
          .allowsHitTesting(false)
      }
    }
    .frame(height: stripHeight)
    .background(EditorPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct ThumbnailStrip: View {
  let images: [UIImage]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(images.enumerated()), id: \.offset) { _, image in
        Image(uiImage: image).resizable().scaledToFill()
          .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
      }
    }
  }
}

// MARK: - Trim row

private struct TrimRowView: View {
  @ObservedObject var viewModel: EditorViewModel
  let index: Int
  let clip: EditorClip
  @State private var liveStart: Int64?
  @State private var liveEnd: Int64?
  @State private var dragOrigin: Int64?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let sourceMs = max(clip.sourceDurationMs, 1)
      let msToX = { (ms: Int64) -> CGFloat in CGFloat(ms) / CGFloat(sourceMs) * width }
      let dxToMs = { (dx: CGFloat) -> Int64 in Int64(dx / width * CGFloat(sourceMs)) }
      let start = liveStart ?? clip.trimStartMs
      let end = liveEnd ?? clip.trimEndMs
      let maxKept = max(viewModel.sourceBudgetMs - (viewModel.totalDurationMs - clip.keptDurationMs), EditorLimits.minTrimGapMs)

      ZStack(alignment: .topLeading) {
        ThumbnailStrip(images: (viewModel.thumbnails[clip.path] ?? []).map(\.image))
          .frame(width: width, height: rowHeight)
          .clipped()
          .contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let src = min(max(Int64(value.location.x / width * CGFloat(sourceMs)), clip.trimStartMs), clip.trimEndMs)
            viewModel.seekToGlobal(viewModel.clipStartMs(index) + (src - clip.trimStartMs))
          })

        Rectangle().fill(Color.black.opacity(0.55))
          .frame(width: max(msToX(start), 0), height: rowHeight).allowsHitTesting(false)
        Rectangle().fill(Color.black.opacity(0.55))
          .frame(width: max(width - msToX(end), 0), height: rowHeight)
          .offset(x: msToX(end)).allowsHitTesting(false)

        // Playhead while playback is inside this clip.
        let clipStart = viewModel.clipStartMs(index)
        let g = viewModel.globalPositionMs
        if g >= clipStart && g < clipStart + clip.keptDurationMs {
          Rectangle().fill(EditorPalette.brand)
            .frame(width: 3, height: rowHeight)
            .offset(x: msToX(min(max(clip.trimStartMs + (g - clipStart), start), end)) - 1)
            .allowsHitTesting(false)
        }

        TrimHandle(x: msToX(start), rowWidth: width, height: rowHeight)
          .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
              let origin = dragOrigin ?? start
              if dragOrigin == nil { dragOrigin = start }
              let lower = max(end - maxKept, 0)
              let upper = max(end - EditorLimits.minTrimGapMs, lower)
              liveStart = min(max(origin + dxToMs(value.translation.width), lower), upper)
            }
            .onEnded { _ in commit(start: liveStart ?? start, end: end) })
        TrimHandle(x: msToX(end), rowWidth: width, height: rowHeight)
          .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
              let origin = dragOrigin ?? end
              if dragOrigin == nil { dragOrigin = end }
              let lower = start + EditorLimits.minTrimGapMs
              let upper = max(min(sourceMs, start + maxKept), lower)
              liveEnd = min(max(origin + dxToMs(value.translation.width), lower), upper)
            }
            .onEnded { _ in commit(start: start, end: liveEnd ?? end) })
      }
    }
    .frame(height: rowHeight)
    .background(EditorPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func commit(start: Int64, end: Int64) {
    dragOrigin = nil
    liveStart = nil
    liveEnd = nil
    viewModel.setClipTrim(index: index, startMs: start, endMs: end)
  }
}

/// A trim handle: 32pt touch target kept inside the row (a half-outside one
/// can't be grabbed at the edges), pink bar centred on the real position.
private struct TrimHandle: View {
  let x: CGFloat
  let rowWidth: CGFloat
  let height: CGFloat

  var body: some View {
    let hitLeft = min(max(x - handleHitWidth / 2, 0), max(rowWidth - handleHitWidth, 0))
    let barLeft = min(max(x - handleWidth / 2 - hitLeft, 0), handleHitWidth - handleWidth)
    ZStack(alignment: .topLeading) {
      Color.clear
      RoundedRectangle(cornerRadius: 6).fill(EditorPalette.pink)
        .frame(width: handleWidth, height: height)
        .offset(x: barLeft)
    }
    .frame(width: handleHitWidth, height: height)
    .contentShape(Rectangle())
    .offset(x: hitLeft)
  }
}

// MARK: - Music row (OUTPUT time)

private struct MusicRowView: View {
  @ObservedObject var viewModel: EditorViewModel
  @State private var liveStart: Int64?
  @State private var liveSource: Int64?
  @State private var liveDuration: Int64?
  @State private var origin: (Int64, Int64, Int64)?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let total = max(viewModel.outputDurationMs, 1)
      let msToX = { (ms: Int64) -> CGFloat in CGFloat(ms) / CGFloat(total) * width }
      let dxToMs = { (dx: CGFloat) -> Int64 in Int64(dx / width * CGFloat(total)) }
      let start = liveStart ?? viewModel.musicStartOffsetMs
      let source = liveSource ?? viewModel.musicSourceStartMs
      let duration = liveDuration ?? viewModel.musicPlayDurationMs
      let song = viewModel.musicDurationMs ?? Int64.max
      let startX = msToX(start)
      let endX = msToX(start + duration)

      ZStack(alignment: .topLeading) {
        // Loop repetitions after the first play — fainter, not draggable.
        if viewModel.musicLoop && duration > 0 {
          ForEach(Array(repetitionStarts(start: start, unit: duration, total: total).enumerated()), id: \.offset) { _, rep in
            RoundedRectangle(cornerRadius: 6).fill(EditorPalette.blue.opacity(0.25))
              .frame(width: max(msToX(min(duration, total - rep)) - 1, 1), height: musicRowHeight)
              .offset(x: msToX(rep) + 1)
          }
        }

        RoundedRectangle(cornerRadius: 6).fill(EditorPalette.blue.opacity(0.55))
          .frame(width: max(endX - startX, 1), height: musicRowHeight)
          .offset(x: startX)
          .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
              let o = origin ?? (start, source, duration)
              if origin == nil { origin = o }
              liveStart = min(max(o.0 + dxToMs(value.translation.width), 0), max(total - o.2, 0))
            }
            .onEnded { _ in commit(start, source, duration) })

        TrimHandle(x: startX, rowWidth: width, height: musicRowHeight)
          .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
              // Left edge: the segment starts later on the timeline AND later in the song, and gets shorter.
              let o = origin ?? (start, source, duration)
              if origin == nil { origin = o }
              let lower = -min(o.0, o.1)
              let upper = max(o.2 - EditorLimits.minTrimGapMs, lower)
              let d = min(max(dxToMs(value.translation.width), lower), upper)
              liveStart = o.0 + d
              liveSource = o.1 + d
              liveDuration = o.2 - d
            }
            .onEnded { _ in commit(start, source, duration) })
        TrimHandle(x: endX, rowWidth: width, height: musicRowHeight)
          .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
              let o = origin ?? (start, source, duration)
              if origin == nil { origin = o }
              let maxMs = max(min(song - o.1, total - o.0), EditorLimits.minTrimGapMs)
              liveDuration = min(max(o.2 + dxToMs(value.translation.width), EditorLimits.minTrimGapMs), maxMs)
            }
            .onEnded { _ in commit(start, source, duration) })
      }
    }
    .frame(height: musicRowHeight)
    .background(EditorPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func repetitionStarts(start: Int64, unit: Int64, total: Int64) -> [Int64] {
    var result: [Int64] = []
    var s = start + unit
    while s < total && result.count < 200 {
      result.append(s)
      s += unit
    }
    return result
  }

  private func commit(_ start: Int64, _ source: Int64, _ duration: Int64) {
    origin = nil
    liveStart = nil
    liveSource = nil
    liveDuration = nil
    viewModel.setMusicPlacement(startOffsetMs: start, sourceStartMs: source, playDurationMs: duration)
  }
}

// MARK: - Text row (OUTPUT time)

/// One caption or sticker as a bar on the overlay row.
private struct OverlayBar: Identifiable {
  let id: String
  let kind: String
  let label: String
  let startMs: Int64
  let endMs: Int64
  let color: Color
}

@MainActor
private func overlayBars(_ viewModel: EditorViewModel) -> [OverlayBar] {
  viewModel.stickerLayers.map { s in
    OverlayBar(id: s.id, kind: "Sticker", label: StickerStore.shared.byId(s.stickerId)?.label ?? "Sticker",
               startMs: s.startMs, endMs: s.endMs, color: Color(red: 1, green: 0.7, blue: 0))
  } + viewModel.textLayers.map { t in
    let c = argbComponents(t.color)
    return OverlayBar(id: t.id, kind: "Text", label: t.text.components(separatedBy: "\n").first ?? "",
                      startMs: t.startMs, endMs: t.endMs,
                      color: Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b)))
  }
}

/// Captions on the OUTPUT timeline (same width and scale as the clip strip).
/// Every caption is a bar; tap one to select it (and jump there), tap the
/// selected one to edit it. The selected caption gets start/end handles and
/// can be dragged by its body; the change is committed on release.
private struct TextRowView: View {
  @ObservedObject var viewModel: EditorViewModel
  let onEditText: (String) -> Void
  @State private var liveStart: Int64?
  @State private var liveEnd: Int64?
  @State private var origin: (String, Int64, Int64)?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let total = max(viewModel.outputDurationMs, 1)
      let msToX = { (ms: Int64) -> CGFloat in CGFloat(min(max(ms, 0), total)) / CGFloat(total) * width }
      let dxToMs = { (dx: CGFloat) -> Int64 in Int64(dx / width * CGFloat(total)) }
      let selectedId = viewModel.selectedTextId
      let bars = overlayBars(viewModel)

      ZStack(alignment: .topLeading) {
        ForEach(bars.filter { $0.id != selectedId }) { layer in
          let left = msToX(layer.startMs)
          let right = max(msToX(layer.endMs), left + 4)
          RoundedRectangle(cornerRadius: 6)
            .fill(layer.color.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(EditorPalette.border, lineWidth: 1))
            .frame(width: right - left, height: textRowHeight - 10)
            .offset(x: left, y: 5)
            .onTapGesture {
              viewModel.selectedTextId = layer.id
              viewModel.seekToOutput(layer.startMs)
            }
        }

        if let sel = bars.first(where: { $0.id == selectedId }) {
          let live = origin?.0 == sel.id
          let start = live ? (liveStart ?? sel.startMs) : sel.startMs
          let end = live ? (liveEnd ?? sel.endMs) : sel.endMs
          let startX = msToX(start)
          let endX = max(msToX(end), startX + 4)

          RoundedRectangle(cornerRadius: 6).fill(EditorPalette.pink.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(EditorPalette.pink, lineWidth: 2))
            .overlay(
              Text(sel.label)
                .font(.caption2).foregroundColor(.white).lineLimit(1)
                .padding(.horizontal, 18),
              alignment: .leading)
            .frame(width: endX - startX, height: textRowHeight - 6)
            .offset(x: startX, y: 3)
            .onTapGesture { onEditText(sel.id) }
            .gesture(DragGesture(minimumDistance: 4)
              .onChanged { value in
                let o = origin ?? (sel.id, sel.startMs, sel.endMs)
                if origin == nil { origin = o }
                let len = o.2 - o.1
                let s = min(max(o.1 + dxToMs(value.translation.width), 0), max(total - len, 0))
                liveStart = s
                liveEnd = s + len
              }
              .onEnded { _ in commit() })

          TrimHandle(x: startX, rowWidth: width, height: textRowHeight)
            .gesture(DragGesture(minimumDistance: 2)
              .onChanged { value in
                let o = origin ?? (sel.id, sel.startMs, sel.endMs)
                if origin == nil { origin = o }
                liveStart = min(max(o.1 + dxToMs(value.translation.width), 0), max(o.2 - 300, 0))
                liveEnd = o.2
              }
              .onEnded { _ in commit() })
          TrimHandle(x: endX, rowWidth: width, height: textRowHeight)
            .gesture(DragGesture(minimumDistance: 2)
              .onChanged { value in
                let o = origin ?? (sel.id, sel.startMs, sel.endMs)
                if origin == nil { origin = o }
                liveStart = o.1
                liveEnd = min(max(o.2 + dxToMs(value.translation.width), o.1 + 300), total)
              }
              .onEnded { _ in commit() })
        }
      }
    }
    .frame(height: textRowHeight)
    .background(EditorPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func commit() {
    if let o = origin {
      viewModel.setOverlayTiming(o.0, startMs: liveStart ?? o.1, endMs: liveEnd ?? o.2)
    }
    origin = nil
    liveStart = nil
    liveEnd = nil
  }
}

// MARK: - Song row (the whole song)

/// Fixed-length window (the music's play length) slid anywhere in the
/// song; the whole row is the touch target and a tap centres the window —
/// no edge handles (on a long song they swallowed the few-pixel window).
private struct SongRowView: View {
  @ObservedObject var viewModel: EditorViewModel
  @State private var liveSource: Int64?
  @State private var origin: Int64?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let song = max(viewModel.musicDurationMs ?? 1, 1)
      let msToX = { (ms: Int64) -> CGFloat in CGFloat(ms) / CGFloat(song) * width }
      let section = min(max(viewModel.musicPlayDurationMs, 0), song)
      let maxSource = max(song - section, 0)
      let source = liveSource ?? viewModel.musicSourceStartMs

      ZStack(alignment: .topLeading) {
        // 10-second ticks.
        ForEach(Array(stride(from: Int64(10_000), to: song, by: 10_000)), id: \.self) { tick in
          Rectangle().fill(EditorPalette.border).frame(width: 1, height: songRowHeight).offset(x: msToX(tick))
        }
        let realWidth = msToX(section)
        let drawWidth = max(realWidth, 6)
        let drawStart = min(max(msToX(source) - (drawWidth - realWidth) / 2, 0), max(width - drawWidth, 0))
        RoundedRectangle(cornerRadius: 6).fill(EditorPalette.pink.opacity(0.75))
          .frame(width: drawWidth, height: songRowHeight)
          .offset(x: drawStart)

        let outMs = viewModel.positionOutMs - viewModel.musicStartOffsetMs
        if viewModel.musicPlayDurationMs > 0 && outMs >= 0 && outMs < viewModel.musicCoveredMs {
          Rectangle().fill(Color.white)
            .frame(width: 2, height: songRowHeight)
            .offset(x: msToX(viewModel.musicSourceStartMs + outMs % viewModel.musicPlayDurationMs) - 1)
        }
      }
      .frame(width: width, height: songRowHeight, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0)
        .onChanged { value in
          let o = origin ?? source
          if origin == nil { origin = o }
          let delta = Int64(value.translation.width / width * CGFloat(song))
          liveSource = min(max(o + delta, 0), maxSource)
        }
        .onEnded { value in
          var final = liveSource ?? source
          if abs(value.translation.width) < 6 {
            // A tap centres the window there.
            let centre = Int64(value.location.x / width * CGFloat(song))
            final = min(max(centre - section / 2, 0), maxSource)
          }
          origin = nil
          liveSource = nil
          viewModel.setMusicPlacement(startOffsetMs: viewModel.musicStartOffsetMs, sourceStartMs: final,
                                      playDurationMs: viewModel.musicPlayDurationMs)
        })
    }
    .frame(height: songRowHeight)
    .background(EditorPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
