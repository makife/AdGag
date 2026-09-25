package com.adgag.adgag.editor

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import java.io.File

/**
 * Native editor state, phase 1 scope: play the captured clip, trim it,
 * optionally attach one background-music track, export.
 *
 * The entire reason this exists (see AdGag's own CLAUDE.md checkpoint,
 * "why Instagram doesn't have this problem" discussion): the Flutter
 * editor kept two independent VideoPlayerControllers (video + music),
 * each with its own native clock, and no amount of retry/watchdog
 * patching around periodic re-seeking ever fully eliminated audible
 * drift or stall recovery glitches — because two independent clocks are
 * structurally the wrong architecture for this. [CompositionPlayer]
 * (Media3's own composition-preview player) plays a video sequence and
 * an audio sequence through ONE Player instance / ONE native clock —
 * there is nothing to keep in sync from the outside, because there is
 * only one clock to begin with. The exact same [Composition] object is
 * later handed to [Transformer] for export, so preview and export are
 * built from literally the same definition, not two separate
 * approximations of each other.
 *
 * Honesty note (do not remove): as of media3 1.11.0, CompositionPlayer
 * is still `@UnstableApi` inside Media3 itself — genuinely newer and
 * less battle-tested than ExoPlayer's core playback path, not a decade-
 * proven legacy API. It is Google's own official, actively-developed
 * path for exactly this (video + background audio, one clock) use case,
 * which is why it's used here instead of hand-rolling an
 * ExoPlayer.MergingMediaSource setup directly — but real-device
 * confirmation matters more here than for most other native APIs in
 * this app, precisely because it's young.
 */
@UnstableApi
class EditorViewModel(private val context: Context, private val sourcePath: String) : ViewModel() {

    init {
        DebugLog.log(context, "EditorViewModel: constructor start, sourcePath=$sourcePath")
    }

    val player: CompositionPlayer = run {
        DebugLog.log(context, "EditorViewModel: building CompositionPlayer")
        val built = CompositionPlayer.Builder(context).build()
        DebugLog.log(context, "EditorViewModel: CompositionPlayer built OK")
        built
    }

    var durationMs by mutableStateOf(0L)
        private set
    var trimStartMs by mutableStateOf(0L)
    var trimEndMs by mutableStateOf(0L)
    var isPlaying by mutableStateOf(false)
        private set
    var musicUri by mutableStateOf<Uri?>(null)
    var musicVolume by mutableStateOf(1.0f)

    // Export state, surfaced to the Compose UI.
    var isExporting by mutableStateOf(false)
        private set
    var exportProgress by mutableStateOf(0f)
        private set
    var exportError by mutableStateOf<String?>(null)
        private set
    var exportedFilePath by mutableStateOf<String?>(null)
        private set

    private var probedDurationMs = 0L

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && probedDurationMs == 0L) {
                    val d = player.duration
                    if (d > 0) {
                        probedDurationMs = d
                        durationMs = d
                        // Default trim window: the whole clip, capped the
                        // same way the rest of this app caps a source
                        // clip's usable window — the caller (Dart side)
                        // is responsible for the exact max-duration rule;
                        // this native screen just avoids defaulting to an
                        // empty window.
                        if (trimEndMs == 0L) {
                            trimEndMs = d
                        }
                    }
                }
            }
        })
        rebuildAndPrepare(startAt = 0L, playWhenReady = true)
    }

    fun togglePlayPause() {
        if (player.isPlaying) {
            player.pause()
        } else {
            player.play()
        }
    }

    fun setTrim(startMs: Long, endMs: Long) {
        trimStartMs = startMs
        trimEndMs = endMs
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition.coerceIn(0L, endMs - startMs)
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    fun setMusic(uri: Uri?) {
        musicUri = uri
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    /** Rebuilds [Composition] from current trim/music state and reloads it into [player]. */
    private fun rebuildAndPrepare(startAt: Long, playWhenReady: Boolean) {
        DebugLog.log(context, "rebuildAndPrepare: start startAt=$startAt playWhenReady=$playWhenReady")
        val composition = buildComposition()
        DebugLog.log(context, "rebuildAndPrepare: composition built, calling player.stop()")
        player.stop()
        DebugLog.log(context, "rebuildAndPrepare: player.stop() done, calling setComposition")
        player.setComposition(composition)
        DebugLog.log(context, "rebuildAndPrepare: setComposition done, calling prepare()")
        player.prepare()
        DebugLog.log(context, "rebuildAndPrepare: prepare() done")
        if (startAt > 0) {
            player.seekTo(startAt)
            DebugLog.log(context, "rebuildAndPrepare: seekTo done")
        }
        player.playWhenReady = playWhenReady
        DebugLog.log(context, "rebuildAndPrepare: playWhenReady set, done")
    }

    private fun buildComposition(): Composition {
        DebugLog.log(context, "buildComposition: start trimStartMs=$trimStartMs trimEndMs=$trimEndMs")
        val clippedVideo = MediaItem.Builder()
            .setUri(Uri.fromFile(File(sourcePath)))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(trimStartMs)
                    .setEndPositionMs(if (trimEndMs > trimStartMs) trimEndMs else trimStartMs + 1)
                    .build(),
            )
            .build()
        DebugLog.log(context, "buildComposition: clippedVideo MediaItem built")
        val videoItem = EditedMediaItem.Builder(clippedVideo).build()
        DebugLog.log(context, "buildComposition: videoItem built")
        // EditedMediaItemSequence has no public constructor as of media3
        // 1.11.0 (confirmed by reading the real sources jar downloaded
        // from Google's Maven repo, after an initial guess at a plain
        // constructor failed to compile) — withAudioAndVideoFrom/
        // withAudioFrom are the current, non-deprecated static factories
        // over EditedMediaItemSequence.Builder.
        //
        // Real crash found on first physical-device test: unconditionally
        // calling withAudioAndVideoFrom REQUIRES the sequence to produce
        // an audio track — if the captured source clip genuinely has no
        // audio track (silent recording, muted gallery import), Media3's
        // internal pipeline has nothing to satisfy that requirement with
        // and throws. Probing the real source file first (MediaExtractor,
        // a plain stable Android API, not Media3-specific) and only
        // requesting audio+video when an audio track actually exists
        // fixes this at the source instead of guessing at a workaround.
        val hasAudio = sourceHasAudioTrack(sourcePath)
        DebugLog.log(context, "buildComposition: sourceHasAudioTrack=$hasAudio")
        val videoSequence = if (hasAudio) {
            EditedMediaItemSequence.withAudioAndVideoFrom(ImmutableList.of(videoItem))
        } else {
            EditedMediaItemSequence.withVideoFrom(ImmutableList.of(videoItem))
        }
        DebugLog.log(context, "buildComposition: videoSequence built")

        val uri = musicUri
        if (uri == null) {
            val composition = Composition.Builder(ImmutableList.of(videoSequence)).build()
            DebugLog.log(context, "buildComposition: composition built (no music), returning")
            return composition
        }

        // Volume/gain control (GainProcessor) is a deliberate phase-2
        // follow-up, not shipped blind here — its exact constructor
        // needs verifying against the real media3-common 1.11.0 sources
        // (same verification method used for EditedMediaItemSequence
        // above) rather than guessed, since a wrong signature is a build
        // break, not a soft failure. Music plays at its own source level
        // for now.
        val musicItem = EditedMediaItem.Builder(MediaItem.fromUri(uri)).build()
        // isLooping=false (withAudioFrom's default): this app's
        // BackgroundAudio model (see the Flutter side's VideoProject)
        // never asked for the music to loop past the clip's own end —
        // the mix simply ends when the video sequence does, matching
        // amix=duration=first in the FFmpeg export pipeline this
        // replaces.
        val musicSequence = EditedMediaItemSequence.withAudioFrom(ImmutableList.of(musicItem))

        return Composition.Builder(ImmutableList.of(videoSequence, musicSequence)).build()
    }

    fun export(outputPath: String, onProgress: (Float) -> Unit, onComplete: (String?, String?) -> Unit) {
        isExporting = true
        exportProgress = 0f
        exportError = null

        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    isExporting = false
                    exportedFilePath = outputPath
                    onComplete(outputPath, null)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    isExporting = false
                    val message = exportException.message ?: "Export failed"
                    exportError = message
                    onComplete(null, message)
                }
            })
            .build()

        val composition = buildComposition()
        transformer.start(composition, outputPath)

        // Transformer doesn't push progress via listener — it's polled.
        // A simple fixed-interval poll (matching the coarse granularity
        // this app's own upload/export progress bars already use
        // elsewhere) is enough for a progress bar; no need for a tighter
        // loop than the UI can visibly represent anyway.
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val progressHolder = ProgressHolder()
        val poll = object : Runnable {
            override fun run() {
                if (!isExporting) return
                val state = transformer.getProgress(progressHolder)
                if (state != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    exportProgress = progressHolder.progress / 100f
                    onProgress(exportProgress)
                }
                if (isExporting) {
                    handler.postDelayed(this, 200)
                }
            }
        }
        handler.postDelayed(poll, 200)
    }

    override fun onCleared() {
        player.release()
    }

    private companion object {
        /** Cached per source path — the source file never changes mid-session. */
        var cachedPath: String? = null
        var cachedResult: Boolean = false

        fun sourceHasAudioTrack(path: String): Boolean {
            if (cachedPath == path) return cachedResult
            val extractor = MediaExtractor()
            val result = try {
                extractor.setDataSource(path)
                (0 until extractor.trackCount).any { i ->
                    val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
                    mime?.startsWith("audio/") == true
                }
            } catch (e: Exception) {
                Log.w("EditorViewModel", "sourceHasAudioTrack probe failed, assuming no audio track", e)
                false
            } finally {
                extractor.release()
            }
            cachedPath = path
            cachedResult = result
            return result
        }
    }
}
