import AVFoundation
import SwiftUI

// Sound effects ("Sound FX") — mirror of android/.../editor/SoundEffects.kt.
// The same 39 CC0 sounds (AdGagSfx: MP3s + sfx.json + LICENSE.txt, made by
// android/tools/build_sfx.py). A layer is one effect at startMs (OUTPUT
// time) playing its whole length. Preview AND export: extra audio tracks
// in the one composition (EditorCompositionBuilder), so unlike Android the
// preview mixes them itself.

struct SoundLayer: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var sfxId: String
  var startMs: Int64 = 0

  static func from(_ o: [String: Any]) -> SoundLayer {
    SoundLayer(id: o["id"] as? String ?? UUID().uuidString,
               sfxId: o["sfxId"] as? String ?? "",
               startMs: (o["startMs"] as? NSNumber)?.int64Value ?? 0)
  }
}

struct SfxDef: Codable, Identifiable {
  let id: String
  let label: String
  let category: String
  let file: String
  let durationMs: Int64
}

final class SfxStore: @unchecked Sendable {
  static let shared = SfxStore()

  let all: [SfxDef]
  let categories: [String]

  private init() {
    if let url = Bundle.main.url(forResource: "sfx", withExtension: "json", subdirectory: "AdGagSfx"),
       let data = try? Data(contentsOf: url),
       let list = try? JSONDecoder().decode([SfxDef].self, from: data) {
      all = list
    } else {
      all = []
    }
    var seen: [String] = []
    for d in all where !seen.contains(d.category) { seen.append(d.category) }
    categories = seen
  }

  func byId(_ id: String) -> SfxDef? { all.first { $0.id == id } }

  func url(_ def: SfxDef) -> URL? {
    Bundle.main.url(forResource: (def.file as NSString).deletingPathExtension, withExtension: "mp3",
                    subdirectory: "AdGagSfx")
  }
}

/// Plays an effect in the picker ("tap to listen").
@MainActor
final class SfxPreviewPlayer {
  static let shared = SfxPreviewPlayer()
  private var players: [AVAudioPlayer] = []

  func play(_ def: SfxDef) {
    guard let url = SfxStore.shared.url(def), let p = try? AVAudioPlayer(contentsOf: url) else { return }
    players.removeAll { !$0.isPlaying }
    players.append(p)
    p.play()
  }
}

/// The picker, in place of the timeline + tools: category chips, every
/// effect as a card — tap to listen, + to add at the playhead (or, opened on
/// an existing effect, to replace it). Delete / Done in the header.
struct SoundPanel: View {
  @ObservedObject var viewModel: EditorViewModel
  let editingId: String?
  let onClose: () -> Void
  @State private var category: String?

  private var editing: SoundLayer? { editingId.flatMap { id in viewModel.soundLayers.first { $0.id == id } } }

  var body: some View {
    let store = SfxStore.shared
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(editing != nil ? "Change sound" : "Sound FX").font(.headline).foregroundColor(.white)
        Spacer()
        if let editing {
          Button("Delete") {
            viewModel.removeSound(editing.id)
            onClose()
          }
          .foregroundColor(EditorPalette.danger)
        }
        Button("Done", action: onClose).foregroundColor(EditorPalette.accent)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          chip("All", selected: category == nil) { category = nil }
          ForEach(store.categories, id: \.self) { c in chip(c, selected: category == c) { category = c } }
        }
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
          ForEach(store.all.filter { category == nil || $0.category == category }) { def in
            let selected = editing?.sfxId == def.id
            HStack(spacing: 4) {
              Image(systemName: "play.fill").font(.system(size: 11)).foregroundColor(EditorPalette.muted)
              VStack(alignment: .leading, spacing: 1) {
                Text(def.label).font(.caption).foregroundColor(.white).lineLimit(1)
                Text(formatPreciseSeconds(def.durationMs)).font(.caption2).foregroundColor(EditorPalette.muted)
              }
              Spacer(minLength: 0)
              Button {
                if let editing {
                  var changed = editing
                  changed.sfxId = def.id
                  viewModel.updateSound(changed)
                } else {
                  viewModel.addSound(def)
                }
                SfxPreviewPlayer.shared.play(def)
                onClose()
              } label: {
                Image(systemName: "plus").foregroundColor(.white).frame(width: 36, height: 44)
              }
              .accessibilityLabel(editing != nil ? "Use this sound" : "Add")
            }
            .padding(.leading, 8)
            .frame(height: 48)
            .background(selected ? EditorPalette.accent.opacity(0.25) : EditorPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? EditorPalette.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { SfxPreviewPlayer.shared.play(def) }
          }
        }
      }
      .frame(height: 196)
      Text("Tap to listen, + to add at the playhead. Sounds: CC0 (Freesound, Kenney)")
        .font(.caption2).foregroundColor(EditorPalette.muted)
    }
    .padding(.top, 4)
  }

  private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).font(.subheadline).foregroundColor(selected ? .white : EditorPalette.muted)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(selected ? EditorPalette.accent.opacity(0.35) : EditorPalette.surface)
        .clipShape(Capsule())
    }
  }
}
