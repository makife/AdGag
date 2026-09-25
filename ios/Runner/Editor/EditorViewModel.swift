import AVFoundation
import Combine
import Foundation

/// Native editor state, phase 1 scope: play the captured clip, trim it,
/// optionally attach one background-music track, export. The exact
/// Swift/AVFoundation counterpart to the Android side's
/// `EditorViewModel.kt` (see that file's own doc comment for the full
/// "why does this screen exist at all" reasoning — the short version:
/// AdGag's Flutter editor kept two independent `VideoPlayerController`s,
/// each with its own native clock, and no amount of drift-correction
/// patching around that ever fully eliminated sync/stall glitches,
/// because two independent clocks are structurally the wrong
/// architecture for "play these two tracks together").
///
/// `AVMutableComposition` is the iOS-native answer to the same problem
/// Media3's `CompositionPlayer` solves on Android: video and background
/// audio become tracks of ONE composition, played by ONE `AVPlayer`
/// through ONE `AVPlayerItem` — there is nothing to keep in sync from
/// the outside, because there is only one clock to begin with. Unlike
/// `CompositionPlayer` (still `@UnstableApi` in Media3 as of this
/// round), `AVMutableComposition`/`AVPlayer` are long-established,
/// stable AVFoundation APIs — this side of the native editor rests on
/// more solidly proven ground than the Android side does.
///
/// NEVER VERIFIED ON A REAL DEVICE OR SIMULATOR AS OF THIS ROUND — this
/// dev environment has no Mac/Xcode. Written carefully against
/// AVFoundation's well-documented, stable composition APIs, but the
/// only verification available until a real Mac/device test is the
/// `.github/workflows/ios-build.yml` GitHub Actions job (compiles on a
/// macOS runner) — compiling is not the same as working correctly.
@MainActor
final class EditorViewModel: ObservableObject {
    let sourceURL: URL

    @Published var player: AVPlayer
    @Published var durationSeconds: Double = 0
    @Published var trimStartSeconds: Double = 0
    @Published var trimEndSeconds: Double = 0
    @Published var isPlaying: Bool = false
    @Published var musicURL: URL?

    @Published var isExporting: Bool = false
    @Published var exportProgress: Float = 0
    @Published var exportError: String?
    @Published var exportedFilePath: String?

    private var timeObserverToken: Any?
    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        self.player = AVPlayer()
        Task { await loadInitialDuration() }
        rebuildAndPrepare(seekTo: .zero, autoplay: true)
    }

    deinit {
        progressTimer?.invalidate()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    private func loadInitialDuration() async {
        let asset = AVURLAsset(url: sourceURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return }
        durationSeconds = seconds
        if trimEndSeconds == 0 {
            trimEndSeconds = seconds
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func setTrim(startSeconds: Double, endSeconds: Double) {
        trimStartSeconds = startSeconds
        trimEndSeconds = endSeconds
        let wasPlaying = isPlaying
        rebuildAndPrepare(seekTo: .zero, autoplay: wasPlaying)
    }

    func setMusic(url: URL?) {
        musicURL = url
        let wasPlaying = isPlaying
        rebuildAndPrepare(seekTo: .zero, autoplay: wasPlaying)
    }

    /// Rebuilds the `AVMutableComposition` from current trim/music state
    /// and loads it into `player` via a fresh `AVPlayerItem`. Mirrors
    /// the Android side's `rebuildAndPrepare` — same trigger points
    /// (trim change, music change), same "there is exactly one place
    /// that (re)builds the composition" discipline preview and export
    /// both rely on.
    private func rebuildAndPrepare(seekTo: CMTime, autoplay: Bool) {
        player.pause()
        Task {
            do {
                let composition = try await buildComposition()
                let item = AVPlayerItem(asset: composition)
                await MainActor.run {
                    player.replaceCurrentItem(with: item)
                    player.seek(to: seekTo)
                    if autoplay {
                        player.play()
                        isPlaying = true
                    }
                }
            } catch {
                await MainActor.run {
                    exportError = "Couldn't prepare preview: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Builds the composition video and background-audio sequences
    /// share — the SAME object this function returns is later handed to
    /// export, so preview and export are literally the same definition.
    private func buildComposition() async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: sourceURL)

        let start = CMTime(seconds: trimStartSeconds, preferredTimescale: 600)
        let end = CMTime(seconds: max(trimEndSeconds, trimStartSeconds + 0.1), preferredTimescale: 600)
        let trimRange = CMTimeRange(start: start, end: end)

        let sourceVideoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        if let sourceVideoTrack = sourceVideoTracks.first,
           let compVideoTrack = composition.addMutableTrack(
               withMediaType: .video,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compVideoTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
            compVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        }

        let sourceAudioTracks = try await videoAsset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = sourceAudioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compAudioTrack.insertTimeRange(trimRange, of: sourceAudioTrack, at: .zero)
        }

        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            let musicTracks = try await musicAsset.loadTracks(withMediaType: .audio)
            if let sourceMusicTrack = musicTracks.first,
               let compMusicTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let musicDuration = try await musicAsset.load(.duration)
                // Clamp to the trimmed clip's own duration — this app's
                // BackgroundAudio model (see the Flutter/Android sides)
                // never asked for music to extend past the clip's end.
                let insertDuration = min(musicDuration, trimRange.duration)
                let musicRange = CMTimeRange(start: .zero, duration: insertDuration)
                try compMusicTrack.insertTimeRange(musicRange, of: sourceMusicTrack, at: .zero)
            }
        }

        return composition
    }

    func export(outputURL: URL, onComplete: @escaping (String?, String?) -> Void) {
        isExporting = true
        exportProgress = 0
        exportError = nil

        Task {
            do {
                let composition = try await buildComposition()
                guard
                    let session = AVAssetExportSession(
                        asset: composition,
                        presetName: AVAssetExportPresetHighestQuality
                    )
                else {
                    await MainActor.run {
                        isExporting = false
                        exportError = "Couldn't create export session"
                        onComplete(nil, "Couldn't create export session")
                    }
                    return
                }
                session.outputURL = outputURL
                session.outputFileType = .mp4
                self.exportSession = session

                // exportAsynchronously(completionHandler:), not the newer
                // async export(to:as:) API — this project's deployment
                // target is iOS 15.0, and the async variant needs iOS 18.
                // Deliberate, deployment-target-driven choice, not an
                // oversight.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    startProgressPolling(for: session)
                    session.exportAsynchronously {
                        continuation.resume()
                    }
                }

                progressTimer?.invalidate()
                progressTimer = nil

                await MainActor.run {
                    isExporting = false
                    switch session.status {
                    case .completed:
                        exportedFilePath = outputURL.path
                        onComplete(outputURL.path, nil)
                    default:
                        let message = session.error?.localizedDescription ?? "Export failed"
                        exportError = message
                        onComplete(nil, message)
                    }
                }
            } catch {
                progressTimer?.invalidate()
                progressTimer = nil
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    onComplete(nil, error.localizedDescription)
                }
            }
        }
    }

    private func startProgressPolling(for session: AVAssetExportSession) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.exportProgress = session.progress
            }
        }
    }
}
