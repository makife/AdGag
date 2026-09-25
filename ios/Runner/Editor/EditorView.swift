import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Phase 1 native editor UI — the Swift/SwiftUI counterpart to the
/// Android side's `EditorScreen.kt`. Same phase 1 scope: preview + trim
/// + one background-music attachment + Next. Not a redesign of the
/// Flutter editor's full toolset (text/stickers/filters/speed) — those
/// are later phases, once phase 1's actual reason for existing
/// (drift-free preview via `AVMutableComposition`) is confirmed on a
/// real device.
///
/// Trim UI is two independent `Slider`s (start, end) rather than a
/// single range control — SwiftUI has no built-in range-slider
/// equivalent to Compose Material3's `RangeSlider`; two sliders is the
/// simplest robust option for phase 1, not a compromise worth blocking
/// on.
struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    let exportOutputURL: URL
    let onCancel: () -> Void
    let onExported: (String, Double) -> Void

    @State private var showMusicPicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    VideoPlayer(player: viewModel.player)
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.durationSeconds > 0 {
                        Text("Trim").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text("Start").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { viewModel.trimStartSeconds },
                                    set: { newValue in
                                        let clamped = min(newValue, viewModel.trimEndSeconds - 0.1)
                                        viewModel.setTrim(startSeconds: max(0, clamped), endSeconds: viewModel.trimEndSeconds)
                                    }
                                ),
                                in: 0...viewModel.durationSeconds
                            )
                        }
                        HStack {
                            Text("End").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { viewModel.trimEndSeconds },
                                    set: { newValue in
                                        let clamped = max(newValue, viewModel.trimStartSeconds + 0.1)
                                        viewModel.setTrim(
                                            startSeconds: viewModel.trimStartSeconds,
                                            endSeconds: min(viewModel.durationSeconds, clamped)
                                        )
                                    }
                                ),
                                in: 0...viewModel.durationSeconds
                            )
                        }
                    }

                    HStack {
                        Button(action: { showMusicPicker = true }) {
                            Label(
                                viewModel.musicURL != nil ? "Music attached" : "Add music",
                                systemImage: "music.note"
                            )
                        }
                        Spacer()
                    }

                    if viewModel.isExporting {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exporting…").font(.caption)
                            ProgressView(value: viewModel.exportProgress)
                        }
                    }

                    if let error = viewModel.exportError {
                        Text("Export failed: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") {
                        viewModel.export(outputURL: exportOutputURL) { path, error in
                            if let path {
                                onExported(path, viewModel.trimEndSeconds - viewModel.trimStartSeconds)
                            }
                            // error != nil: surfaced via viewModel.exportError
                            // above, the screen stays open — matches this
                            // app's "never silently fail" rule.
                        }
                    }
                    .disabled(viewModel.isExporting)
                }
            }
        }
        .fileImporter(
            isPresented: $showMusicPicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // fileImporter hands back a security-scoped URL for
                    // content outside the app's own sandbox (e.g. Files
                    // app / iCloud Drive) — must start/stop access
                    // around actually reading it, or AVFoundation will
                    // fail to open the file with a permissions error.
                    if url.startAccessingSecurityScopedResource() {
                        viewModel.setMusic(url: url)
                        // Deliberately not calling
                        // stopAccessingSecurityScopedResource() here:
                        // the composition (built lazily by
                        // buildComposition()) still needs to read this
                        // URL later, including at export time. Released
                        // when the ViewModel/URL is replaced or the
                        // screen is dismissed — a real, tracked follow-
                        // up, not an oversight: revisit if music files
                        // outside the sandbox fail to load on a real
                        // device.
                    } else {
                        viewModel.setMusic(url: url)
                    }
                }
            case .failure:
                break
            }
        }
    }
}
