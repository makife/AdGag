import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// The native iOS editor screen — same layout and tools as the Android
/// EditorScreen: top bar (Cancel / Next), the video (aspect kept, never
/// covered by the panel), then the editing panel (timeline + tools).
/// Pickers open as bottom panels over the editing panel only.
struct EditorView: View {
  @ObservedObject var viewModel: EditorViewModel
  let exportOutputURL: URL
  let onCancel: () -> Void
  let onExported: (String, Int64) -> Void
  /// "+": close so Flutter's camera can record another clip, then reopen with this state.
  let onAddClip: (String, Int64) -> Void

  private enum Panel: Equatable {
    case transition(Int), music, speed(String), effects, text(String)
    /// Sticker picker: nil = adding, else the sticker being changed.
    case stickers(String?)
    /// Sound FX picker: same convention.
    case sounds(String?)
  }

  @State private var panel: Panel?
  @State private var pickingMusic = false
  /// The bottom panel dragged down out of the way (the video gets the space).
  @State private var panelCollapsed = false

  private enum BottomKind: Hashable { case editor, text, stickers, sounds }

  private var bottomKind: BottomKind {
    switch panel {
    case .text: return .text
    case .stickers: return .stickers
    case .sounds: return .sounds
    default: return .editor
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      topBar
      videoArea
      bottomPanel
    }
    .background(EditorPalette.background.ignoresSafeArea())
    .overlay(alignment: .bottom) { panelOverlay }
    .fileImporter(isPresented: $pickingMusic, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
      if case let .success(urls) = result, let url = urls.first { viewModel.setMusic(url: url) }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
      viewModel.pause() // never keep playing in the background
    }
    .preferredColorScheme(.dark)
  }

  // MARK: Top bar

  private var topBar: some View {
    HStack {
      Button("Cancel", action: onCancel)
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
      Spacer()
      Button {
        viewModel.export(to: exportOutputURL) { path, durationMs in
          if let path { onExported(path, durationMs) }
        }
      } label: {
        Text("Next").fontWeight(.semibold).foregroundColor(.white)
          .padding(.horizontal, 18).padding(.vertical, 8)
          .background(viewModel.isExporting ? AnyView(EditorPalette.border) : AnyView(EditorPalette.brand))
          .clipShape(Capsule())
      }
      .disabled(viewModel.isExporting)
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
  }

  // MARK: Video

  private var videoArea: some View {
    ZStack {
      PlayerLayerView(player: viewModel.player)
      // Captions + all taps on the video (play/pause, selecting captions).
      TextOverlayView(viewModel: viewModel) { id in editOverlay(id) }
      if !viewModel.isPlaying {
        Image(systemName: "play.fill")
          .font(.system(size: 30))
          .foregroundColor(.white)
          .frame(width: 64, height: 64)
          .background(Color.black.opacity(0.45))
          .clipShape(Circle())
          .allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  /// Tapping a selected caption/sticker (or its timeline bar) opens the matching editor.
  private func editOverlay(_ id: String) {
    viewModel.pause()
    if viewModel.stickerLayers.contains(where: { $0.id == id }) {
      panel = .stickers(id)
    } else if viewModel.soundLayers.contains(where: { $0.id == id }) {
      panel = .sounds(id)
    } else {
      panel = .text(id)
    }
  }

  /// Slow-mo tool / the Speed row's "+": a range at the playhead (or the one
  /// the playhead is in), then its settings.
  private func openSpeed() {
    if let range = viewModel.addSpeedRangeAtPlayhead() {
      panel = .speed(range.id)
    } else {
      viewModel.showNotice("No room for slow motion — the Ad is already 30s. Trim it first.")
    }
  }

  private func addText() {
    let layer = viewModel.addText()
    panel = .text(layer.id)
  }

  // MARK: Bottom panel

  /// The editor (timeline + tools), or the text / sticker editors IN ITS
  /// PLACE — never over the video. The grab bar collapses it (the video
  /// grows into the space) and expands it again; a newly opened panel
  /// slides up.
  private var bottomPanel: some View {
    VStack(spacing: 0) {
      PanelHandle(collapsed: $panelCollapsed,
                  label: bottomKind == .text ? "Text" : bottomKind == .stickers ? "Stickers"
                    : bottomKind == .sounds ? "Sound FX" : "Editor",
                  onDone: bottomKind == .editor ? nil : { panel = nil })
      if !panelCollapsed {
        Group {
          switch panel {
          case .text(let id):
            TextEditorPanel(viewModel: viewModel, layerId: id, onClose: { panel = nil })
          case .stickers(let id):
            StickerPanel(viewModel: viewModel, editingId: id, onClose: { panel = nil })
          case .sounds(let id):
            SoundPanel(viewModel: viewModel, editingId: id, onClose: { panel = nil })
          default:
            editingPanel
          }
        }
        .id(bottomKind)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
    .background(EditorPalette.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .animation(.easeOut(duration: 0.28), value: panelCollapsed)
    .animation(.easeOut(duration: 0.3), value: bottomKind)
    .onChange(of: bottomKind) { _ in panelCollapsed = false }
  }

  // MARK: Editing panel

  private var editingPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      EditorTimelineView(
        viewModel: viewModel,
        onAddClip: {
          viewModel.pause()
          onAddClip(viewModel.sessionState().toJSON(), viewModel.remainingMs)
        },
        onPickTransition: { panel = .transition($0) },
        onOpenMusic: { panel = .music },
        onAddText: addText,
        onEditText: { id in editOverlay(id) },
        onAddSpeedRange: openSpeed,
        onEditSpeedRange: { panel = .speed($0) })
      toolRow
      if let notice = viewModel.notice {
        Text(notice).font(.footnote).foregroundColor(EditorPalette.muted)
      }
      if viewModel.isExporting {
        VStack(alignment: .leading, spacing: 4) {
          Text("Exporting your Ad…").font(.footnote).foregroundColor(EditorPalette.muted)
          ProgressView(value: viewModel.exportProgress).tint(EditorPalette.pink)
        }
      }
      if viewModel.isAttachingMusic {
        VStack(alignment: .leading, spacing: 4) {
          Text("Preparing music…").font(.footnote).foregroundColor(EditorPalette.muted)
          ProgressView().progressViewStyle(.linear).tint(EditorPalette.pink)
        }
      }
      if let error = viewModel.previewError {
        Text("Preview problem: \(error)").font(.footnote).foregroundColor(EditorPalette.danger).lineLimit(3)
      }
      if let error = viewModel.exportError {
        Text("Export failed: \(error)").font(.footnote).foregroundColor(EditorPalette.danger).lineLimit(3)
      }
    }
  }

  private var toolRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 16) {
        ToolButton(icon: "textformat",
                   label: viewModel.textLayers.isEmpty ? "Text" : "Text (\(viewModel.textLayers.count))",
                   active: !viewModel.textLayers.isEmpty) { addText() }
        ToolButton(icon: "face.smiling",
                   label: viewModel.stickerLayers.isEmpty ? "Stickers" : "Stickers (\(viewModel.stickerLayers.count))",
                   active: !viewModel.stickerLayers.isEmpty) {
          viewModel.pause()
          panel = .stickers(nil)
        }
        ToolButton(icon: "waveform",
                   label: viewModel.soundLayers.isEmpty ? "Sound FX" : "Sound FX (\(viewModel.soundLayers.count))",
                   active: !viewModel.soundLayers.isEmpty) {
          viewModel.pause()
          panel = .sounds(nil)
        }
        ToolButton(icon: "rotate.right", label: "Rotate", active: false) { viewModel.rotateNinety() }
        ToolButton(icon: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                   label: viewModel.isMuted ? "Muted" : "Mute", active: viewModel.isMuted) { viewModel.toggleMute() }
        ToolButton(icon: "slowmo",
                   label: viewModel.speedRanges.isEmpty ? "Slow-mo" : "Slow-mo (\(viewModel.speedRanges.count))",
                   active: !viewModel.speedRanges.isEmpty) { openSpeed() }
        ToolButton(icon: "wand.and.stars",
                   label: viewModel.videoFilter == .NONE ? "Effects" : viewModel.videoFilter.label,
                   active: viewModel.videoFilter != .NONE) { panel = .effects }
        ToolButton(icon: "music.note", label: viewModel.hasMusic ? "Music" : "Add music",
                   active: viewModel.hasMusic) {
          if viewModel.hasMusic { panel = .music } else { pickingMusic = true }
        }
      }
    }
  }

  // MARK: Bottom panels

  @ViewBuilder
  private var panelOverlay: some View {
    if let panel, !isTextPanel(panel) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(panelTitle(panel)).font(.headline).foregroundColor(.white)
          Spacer()
          Button("Done") { self.panel = nil }.foregroundColor(EditorPalette.pink)
        }
        switch panel {
        case .transition(let boundary): TransitionPanel(viewModel: viewModel, boundary: boundary)
        case .music: MusicPanel(viewModel: viewModel, onReplace: { self.panel = nil; pickingMusic = true },
                                onRemoved: { self.panel = nil })
        case .speed(let id): SpeedPanel(viewModel: viewModel, rangeId: id, onRemoved: { self.panel = nil })
        case .effects: EffectsPanel(viewModel: viewModel)
        case .text, .stickers, .sounds: EmptyView()
        }
      }
      .padding(16)
      .background(EditorPalette.surfaceElevated.ignoresSafeArea(edges: .bottom))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(radius: 12)
      .transition(.move(edge: .bottom))
    }
  }

  private func isTextPanel(_ panel: Panel) -> Bool {
    switch panel {
    case .text, .stickers, .sounds: return true
    default: return false
    }
  }

  private func panelTitle(_ panel: Panel) -> String {
    switch panel {
    case .transition(let b): return "Clip \(b + 1) → Clip \(b + 2)"
    case .music: return "Music"
    case .speed: return "Slow motion"
    case .effects: return "Effects"
    case .text: return "Text"
    case .stickers: return "Stickers"
    case .sounds: return "Sound FX"
    }
  }
}

private struct ToolButton: View {
  let icon: String
  let label: String
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundColor(active ? EditorPalette.pink : .white)
          .frame(width: 48, height: 48)
          .background(active ? EditorPalette.pink.opacity(0.25) : EditorPalette.surface)
          .clipShape(Circle())
        Text(label).font(.caption2).foregroundColor(EditorPalette.muted).lineLimit(1)
      }
    }
  }
}

/// AVPlayerLayer host — the preview shows the composition's own rendering
/// (transitions and effects included), aspect kept.
struct PlayerLayerView: UIViewRepresentable {
  let player: AVPlayer

  final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }

  func makeUIView(context: Context) -> PlayerUIView {
    let view = PlayerUIView()
    view.backgroundColor = .black
    view.playerLayer.videoGravity = .resizeAspect
    view.playerLayer.player = player
    return view
  }

  func updateUIView(_ uiView: PlayerUIView, context: Context) {
    uiView.playerLayer.player = player
  }
}

// MARK: - Panels

private struct TransitionPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let boundary: Int

  var body: some View {
    let spec = boundary < viewModel.transitions.count ? viewModel.transitions[boundary] : TransitionSpec()
    VStack(alignment: .leading, spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(ClipTransition.allCases, id: \.self) { type in
            Button { viewModel.setTransitionType(boundary, type) } label: {
              VStack(spacing: 4) {
                TransitionThumbnail(type: type)
                  .frame(width: 64, height: 96)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(type == spec.type ? EditorPalette.pink : EditorPalette.border,
                            lineWidth: type == spec.type ? 2 : 1))
                Text(type.label).font(.caption2)
                  .foregroundColor(type == spec.type ? EditorPalette.pink : EditorPalette.muted)
                  .lineLimit(1)
              }
              .frame(width: 72)
            }
          }
        }
      }
      HStack {
        Text("Duration").font(.caption).foregroundColor(EditorPalette.muted)
        Spacer()
        Text(spec.type == .NONE ? "—" : String(format: "%.1fs", Double(spec.durationMs) / 1000))
          .font(.caption).foregroundColor(.white)
      }
      Slider(
        value: Binding(get: { Double(spec.durationMs) },
                       set: { viewModel.setTransitionDuration(boundary, Int64($0)) }),
        in: Double(EditorLimits.minTransitionMs)...Double(EditorLimits.maxTransitionMs), step: 100,
        onEditingChanged: { editing in if !editing { viewModel.commitTransitionDuration(boundary) } })
        .tint(EditorPalette.pink)
        .disabled(spec.type == .NONE)
    }
  }
}

/// Looping mini illustration of a transition (the pink frame going out, then
/// coming in), posed by the same TransitionMath the compositor uses.
private struct TransitionThumbnail: View {
  let type: ClipTransition
  private let clipMs: Int64 = 1_400
  private let demoMs: Int64 = 800

  var body: some View {
    TimelineView(.animation) { context in
      Canvas { g, size in
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let t = Int64(context.date.timeIntervalSinceReferenceDate * 1000) % (clipMs * 2)
        let spec = TransitionSpec(type: type, durationMs: demoMs)
        let outgoing = t < clipMs
        let local = outgoing ? t : t - clipMs
        let pose = outgoing
          ? TransitionMath.clipPose(entry: nil, exit: spec, keptMs: clipMs, localMs: local)
          : TransitionMath.clipPose(entry: spec, exit: nil, keptMs: clipMs, localMs: local)
        var frame = g
        frame.translateBy(x: pose.translateX * size.width + size.width / 2,
                          y: pose.translateY * size.height + size.height / 2)
        frame.rotate(by: .degrees(pose.rotationDegrees))
        frame.scaleBy(x: pose.scale, y: pose.scale)
        frame.translateBy(x: -size.width / 2, y: -size.height / 2)
        frame.fill(Path(CGRect(origin: .zero, size: size)), with: .color(EditorPalette.pink))
        var mountain = Path()
        mountain.move(to: CGPoint(x: size.width * 0.05, y: size.height * 0.78))
        mountain.addLine(to: CGPoint(x: size.width * 0.40, y: size.height * 0.36))
        mountain.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.60))
        mountain.addLine(to: CGPoint(x: size.width * 0.75, y: size.height * 0.48))
        mountain.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.78))
        mountain.closeSubpath()
        frame.fill(mountain, with: .color(.white.opacity(0.9)))
        frame.fill(Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.16,
                                          width: size.width * 0.2, height: size.width * 0.2)),
                   with: .color(.white.opacity(0.9)))
        if pose.brightness < 1 {
          g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(1 - pose.brightness)))
        }
      }
    }
  }
}

private struct MusicPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let onReplace: () -> Void
  let onRemoved: () -> Void

  var body: some View {
    let maxFade = Double(max(min(EditorLimits.maxMusicFadeMs, viewModel.musicCoveredMs), 1))
    VStack(alignment: .leading, spacing: 10) {
      Text("Speed").font(.caption).foregroundColor(EditorPalette.muted)
      ChoiceRow(options: EditorLimits.musicSpeedOptions, selected: viewModel.musicSpeed,
                enabled: { _ in true }) { viewModel.changeMusicSpeed($0) }
      Toggle(isOn: Binding(get: { viewModel.musicLoop }, set: { viewModel.changeMusicLoop($0) })) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Loop to fill the video").foregroundColor(.white)
          Text("Repeats the selected part until the video ends").font(.caption).foregroundColor(EditorPalette.muted)
        }
      }
      .tint(EditorPalette.pink)
      fadeSlider("Fade in", value: viewModel.musicFadeInMs, maxMs: maxFade) {
        viewModel.setMusicFade(inMs: $0, outMs: viewModel.musicFadeOutMs, commit: $1)
      }
      fadeSlider("Fade out", value: viewModel.musicFadeOutMs, maxMs: maxFade) {
        viewModel.setMusicFade(inMs: viewModel.musicFadeInMs, outMs: $0, commit: $1)
      }
      HStack {
        Button("Replace music", action: onReplace).foregroundColor(.white)
        Spacer()
        Button("Remove music") {
          viewModel.removeMusic()
          onRemoved()
        }
        .foregroundColor(EditorPalette.danger)
      }
    }
  }

  private func fadeSlider(_ title: String, value: Int64, maxMs: Double,
                          onChange: @escaping (Int64, Bool) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.caption).foregroundColor(EditorPalette.muted)
        Spacer()
        Text(value == 0 ? "Off" : String(format: "%.1fs", Double(value) / 1000)).font(.caption).foregroundColor(.white)
      }
      Slider(value: Binding(get: { min(Double(value), maxMs) },
                            set: { onChange(Int64(($0 / 100).rounded() * 100), false) }),
             in: 0...maxMs,
             onEditingChanged: { editing in if !editing { onChange(value, true) } })
        .tint(EditorPalette.pink)
    }
  }
}

/// Slow motion for ONE range (selected on the timeline's Speed row): its
/// speed, stretch it over the whole video, or remove it. The range's edges
/// are dragged on the Speed row itself.
private struct SpeedPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let rangeId: String
  let onRemoved: () -> Void

  var body: some View {
    if let range = viewModel.speedRanges.first(where: { $0.id == rangeId }) {
      let blocked = EditorLimits.speedRangeOptions.filter { !viewModel.canUseRangeSpeed(range.id, $0) }
      let wholeOk = viewModel.canApplySpeedToWholeVideo(range.id)
      VStack(alignment: .leading, spacing: 10) {
        Text("\(formatPreciseSeconds(range.startMs)) – \(formatPreciseSeconds(range.endMs)) of your clips plays at "
          + "\(formatSpeed(range.speed)). Drag the pink edges on the Speed row to change which part.")
          .font(.caption).foregroundColor(EditorPalette.muted)
        ChoiceRow(options: EditorLimits.speedRangeOptions, selected: range.speed,
                  enabled: { viewModel.canUseRangeSpeed(range.id, $0) }) { viewModel.setSpeedRangeSpeed(range.id, $0) }
        Text(blocked.isEmpty
          ? "Your Ad: \(formatClock(viewModel.outputDurationMs)) of 0:30."
          : "\(blocked.map(formatSpeed).joined(separator: ", ")) would make the Ad longer than 30s — shorten the range first.")
          .font(.caption).foregroundColor(EditorPalette.muted)
        HStack {
          Button("Whole video") { viewModel.applySpeedToWholeVideo(range.id) }
            .foregroundColor(wholeOk ? .white : EditorPalette.muted)
            .disabled(!wholeOk)
          Spacer()
          Button("Remove slow motion") {
            viewModel.removeSpeedRange(range.id)
            onRemoved()
          }
          .foregroundColor(EditorPalette.danger)
        }
      }
    }
  }
}

private struct EffectsPanel: View {
  @ObservedObject var viewModel: EditorViewModel

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(VideoFilter.allCases, id: \.self) { filter in
          let selected = filter == viewModel.videoFilter
          Button { viewModel.changeFilter(filter) } label: {
            VStack(spacing: 4) {
              ZStack {
                EditorPalette.surface
                if let image = viewModel.filterThumbnails[filter] {
                  Image(uiImage: image).resizable().scaledToFill()
                } else {
                  ProgressView().tint(EditorPalette.pink)
                }
              }
              .frame(width: 64, height: 112)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? EditorPalette.pink : EditorPalette.border, lineWidth: selected ? 2 : 1))
              Text(filter.label).font(.caption2)
                .foregroundColor(selected ? EditorPalette.pink : EditorPalette.muted).lineLimit(1)
            }
            .frame(width: 72)
          }
        }
      }
    }
    .onAppear { viewModel.ensureFilterThumbnails() }
  }
}

private struct ChoiceRow: View {
  let options: [Double]
  let selected: Double
  let enabled: (Double) -> Bool
  let onSelect: (Double) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(options, id: \.self) { option in
          let isSelected = option == selected
          let isEnabled = enabled(option)
          Button { onSelect(option) } label: {
            Text(formatSpeed(option)).fontWeight(.semibold).foregroundColor(.white)
              .padding(.horizontal, 16).padding(.vertical, 8)
              .background(isSelected ? EditorPalette.pink : EditorPalette.surface)
              .clipShape(Capsule())
              .opacity(isEnabled || isSelected ? 1 : 0.35)
          }
          .disabled(!isEnabled || isSelected)
        }
      }
    }
  }
}

/// Grab bar on top of the bottom panel: drag down to collapse it (the video
/// grows into the freed space), up (or tap) to bring it back. While
/// collapsed it says which panel is hidden, plus Done for the text / sticker
/// editors so they can be closed without expanding.
private struct PanelHandle: View {
  @Binding var collapsed: Bool
  let label: String
  let onDone: (() -> Void)?

  var body: some View {
    VStack(spacing: 6) {
      Capsule().fill(Color.white.opacity(0.35)).frame(width: 44, height: 5)
      if collapsed {
        HStack {
          Text("\(label) · drag up to edit").font(.caption).foregroundColor(EditorPalette.muted)
          Spacer()
          if let onDone {
            Button("Done", action: onDone).foregroundColor(EditorPalette.pink)
          }
        }
        .frame(height: 32)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 8)
    .padding(.bottom, collapsed ? 2 : 8)
    .contentShape(Rectangle())
    .onTapGesture { collapsed.toggle() }
    .gesture(DragGesture(minimumDistance: 6).onEnded { value in
      if value.translation.height > 36 { collapsed = true } else if value.translation.height < -36 { collapsed = false }
    })
    .accessibilityLabel(collapsed ? "Expand \(label)" : "Collapse \(label)")
  }
}
