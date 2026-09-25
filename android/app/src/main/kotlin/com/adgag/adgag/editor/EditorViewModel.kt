package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.ConcatenatingMediaSource
import androidx.media3.exoplayer.source.FilteringMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SilenceMediaSource
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import com.google.common.collect.ImmutableSet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
 * structurally the wrong architecture for this.
 *
 * PIVOT (this round): the live preview player was [androidx.media3.transformer.CompositionPlayer]
 * (Media3's own composition-preview player, one Player/one clock playing
 * a whole [Composition] directly) — confirmed via TWO independent real-
 * device tests (6% battery, then fully charged, ruling out a power-
 * saving cause) that `CompositionPlayer.Builder(context).build()` itself
 * crashes on the user's real device, before any composition/video file
 * is even involved. Reading its real decompiled source confirmed why
 * it's a comparatively risky construction path: the constructor starts
 * its own `HandlerThread` at `THREAD_PRIORITY_AUDIO` and sets up a GL-
 * backed video graph pipeline immediately — genuinely heavy, newer,
 * `@UnstableApi` machinery, unlike a plain player.
 *
 * The preview player is now a plain [ExoPlayer] — the same decade-old,
 * extremely widely deployed core Media3/ExoPlayer architecture used in
 * essentially every production Android video app — combined with
 * [MergingMediaSource] (to attach a separate audio track to the video,
 * the standard, long-established way to preview "video + different
 * audio" with one Player/one clock) and [ClippingMediaSource] (trim).
 * `ExoPlayer.Builder().build()` does NOT do CompositionPlayer's own
 * heavy construction-time GL/video-graph setup — real rendering setup
 * only happens once a Surface is attached and playback actually starts
 * — making it a structurally lighter, safer construction path.
 *
 * IMPORTANT SCOPE NOTE (preview-only, does not affect the exported Ad):
 * plain ExoPlayer has no equivalent of Composition's real N-way audio
 * MIXING. When background music is attached, this preview plays ONLY
 * the music track (the clip's own original audio is excluded from the
 * live preview via [FilteringMediaSource] rather than left to an
 * unpredictable two-audio-track-group tie-break). The final EXPORTED
 * Ad is unaffected by any of this — [export] still goes through
 * [Transformer]/[Composition] exactly as before (a completely separate,
 * long-stable pipeline that never used CompositionPlayer and has never
 * been implicated in any crash), which genuinely mixes the original
 * audio (when not muted) together with the music, sample-accurately.
 */
@UnstableApi
class EditorViewModel(private val context: Context, private val sourcePath: String) : ViewModel() {

    init {
        DebugLog.log(context, "EditorViewModel: constructor start, sourcePath=$sourcePath")
    }

    val player: ExoPlayer = run {
        DebugLog.log(context, "EditorViewModel: building ExoPlayer")
        val built = ExoPlayer.Builder(context).build()
        DebugLog.log(context, "EditorViewModel: ExoPlayer.Builder(context).build() returned")
        // Same fix as before the pivot, carried over unchanged: without
        // an explicit repeat mode, a plain STATE_ENDED is reached at the
        // end of every playthrough, and per standard Player semantics,
        // calling play() again on an ENDED player does nothing without
        // an explicit seekTo(0) first.
        built.repeatMode = Player.REPEAT_MODE_ONE
        DebugLog.log(context, "EditorViewModel: ExoPlayer built OK, repeatMode=ONE")
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
    /** The music file's own real duration, probed once when attached — drives the timeline's music segment width (see EditorScreen's TimelineSection). Null while no music is attached. */
    var musicDurationMs by mutableStateOf<Long?>(null)
        private set
    /**
     * Where in the CLIP's own timeline (0 = clip/trim start) the music
     * begins playing, and for how long — real, user-report-driven
     * additions ("eklenen müziği kesemiyorum" / "can't cut the music I
     * added"): previously music always started at 0 with no way to
     * shorten it. [EditorScreen]'s timeline lets both be dragged
     * directly. Both are relative to the CLIP's timeline, not the music
     * file's own (possibly much longer) runtime — trimming means
     * "how much of the song, from its own start, plays and where,"
     * matching this phase's actual scope, not implying arbitrary in-
     * song scrubbing that doesn't exist yet.
     */
    var musicStartOffsetMs by mutableStateOf(0L)
        private set
    var musicPlayDurationMs by mutableStateOf(0L)
        private set
    /** 0/90/180/270 — [rotateNinety] is the only mutator, so it can never drift off a multiple of 90. */
    var rotationDegrees by mutableStateOf(0)
        private set
    var isMuted by mutableStateOf(false)
        private set

    /** A handful of evenly-spaced frames from the source clip, for the timeline's filmstrip — see [generateThumbnails]. Empty until generation finishes; the timeline simply shows a plain track until then, never blocks on it. */
    var thumbnails by mutableStateOf<List<Bitmap>>(emptyList())
        private set

    // Deliberately not named viewModelScope and not the real Jetpack
    // extension property of that name (which needs lifecycle-viewmodel-
    // ktx, a dependency this module doesn't otherwise need) — a plain,
    // manually-cancelled scope is simpler for the one call site that needs it.
    private val editorScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

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
        generateThumbnails()
    }

    /**
     * Real feature gap found via user report ("timelineda thumbnail
     * yok" / no thumbnails in the timeline): reads a handful of evenly-
     * spaced frames directly from the source file with
     * [MediaMetadataRetriever.getFrameAtTime] — a plain, long-stable
     * platform API (available since API 10), not Media3-specific, so no
     * new-API verification risk here. Runs on [Dispatchers.IO] since
     * decoding several frames synchronously is real work; publishes to
     * [thumbnails] on the main thread once done. Best-effort: any
     * failure just leaves the timeline without thumbnails rather than
     * blocking or crashing the editor over a cosmetic feature.
     */
    private fun generateThumbnails() {
        editorScope.launch {
            val frames = withContext(Dispatchers.IO) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(sourcePath)
                    val totalMs = retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull()
                    if (totalMs == null || totalMs <= 0) {
                        emptyList()
                    } else {
                        val count = 10
                        (0 until count).mapNotNull { i ->
                            val timeUs = (totalMs * i / count) * 1000
                            try {
                                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            } catch (e: Exception) {
                                null
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w("EditorViewModel", "Thumbnail generation failed", e)
                    emptyList()
                } finally {
                    retriever.release()
                }
            }
            thumbnails = frames
        }
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
        // Defensive: if music was already placed and the clip is now
        // SHORTER than before (the trim window shrank), re-clamp the
        // music's placement so it can never end up specifying a segment
        // that no longer fits.
        if (musicUri != null) {
            val newClipDurationMs = (endMs - startMs).coerceAtLeast(0L)
            val clampedStart = musicStartOffsetMs.coerceIn(0L, newClipDurationMs)
            musicStartOffsetMs = clampedStart
            musicPlayDurationMs = musicPlayDurationMs.coerceIn(0L, newClipDurationMs - clampedStart)
        }
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition.coerceIn(0L, endMs - startMs)
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    fun setMusic(uri: Uri?) {
        musicUri = uri
        val probedMs = if (uri != null) probeDurationUs(context, uri)?.let { it / 1000 } else null
        musicDurationMs = probedMs
        val clipDurationMs = (trimEndMs - trimStartMs).coerceAtLeast(0L)
        // Default placement: start at the clip's own beginning, play
        // for as much of the song as fits — user-adjustable via the
        // timeline's music-segment drag handles (setMusicPlacement).
        musicStartOffsetMs = 0L
        musicPlayDurationMs = if (probedMs != null) minOf(probedMs, clipDurationMs) else 0L
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    /**
     * Moves and/or resizes the attached music's placement within the
     * clip's own timeline — [EditorScreen]'s draggable music segment is
     * the caller. Both values are clamped so the segment can never sit
     * outside the clip or exceed the music file's own real length.
     */
    fun setMusicPlacement(startOffsetMs: Long, playDurationMs: Long) {
        val durationMs = musicDurationMs ?: return
        val clipDurationMs = (trimEndMs - trimStartMs).coerceAtLeast(0L)
        val clampedStart = startOffsetMs.coerceIn(0L, clipDurationMs)
        val maxDuration = (clipDurationMs - clampedStart).coerceAtLeast(0L)
        musicStartOffsetMs = clampedStart
        musicPlayDurationMs = playDurationMs.coerceIn(0L, minOf(durationMs, maxDuration))
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    fun rotateNinety() {
        rotationDegrees = (rotationDegrees + 90) % 360
        // No rebuildAndPrepare needed: rotation isn't part of the
        // preview MediaSource anymore (plain ExoPlayer has no live
        // Effects/Transformation pipeline — that's CompositionPlayer/
        // Transformer-only). EditorScreen applies a Compose-level visual
        // rotation to the PlayerSurface directly from this field. The
        // real, pixel-accurate rotation is still applied at export time
        // via ScaleAndRotateTransformation in buildComposition(), below
        // — unaffected by this pivot.
    }

    fun toggleMute() {
        isMuted = !isMuted
        applyPreviewVolume()
    }

    /**
     * Preview audio routing: when music is attached, the preview plays
     * ONLY the music (see this class's own doc comment on why — no live
     * N-way mixing on plain ExoPlayer), so the mute toggle has nothing
     * left to mute there; it still governs the ORIGINAL clip's audio at
     * export time via buildComposition()'s own hasAudio check,
     * unaffected by this. With no music attached, mute genuinely
     * silences the live preview via player volume — the most direct,
     * reliable way to mute a single already-playing audio track,
     * without needing to rebuild/reprepare the MediaSource at all.
     */
    private fun applyPreviewVolume() {
        player.volume = if (musicUri == null && isMuted) 0f else 1f
    }

    /** Rebuilds the preview [MediaSource] from current trim/music state and reloads it into [player]. */
    private fun rebuildAndPrepare(startAt: Long, playWhenReady: Boolean) {
        DebugLog.log(context, "rebuildAndPrepare: start startAt=$startAt playWhenReady=$playWhenReady")
        val mediaSource = buildPreviewMediaSource()
        DebugLog.log(context, "rebuildAndPrepare: preview MediaSource built, calling player.stop()")
        player.stop()
        DebugLog.log(context, "rebuildAndPrepare: player.stop() done, calling setMediaSource")
        player.setMediaSource(mediaSource)
        applyPreviewVolume()
        DebugLog.log(context, "rebuildAndPrepare: setMediaSource done, calling prepare()")
        player.prepare()
        DebugLog.log(context, "rebuildAndPrepare: prepare() done")
        if (startAt > 0) {
            player.seekTo(startAt)
            DebugLog.log(context, "rebuildAndPrepare: seekTo done")
        }
        player.playWhenReady = playWhenReady
        DebugLog.log(context, "rebuildAndPrepare: playWhenReady set, done")
    }

    /**
     * Builds the ExoPlayer [MediaSource] graph for live preview only —
     * see this class's own doc comment for the full pivot rationale.
     * Trim: [ClippingMediaSource], the standard, long-stable ExoPlayer
     * trim mechanism (constructor takes start/end in microseconds,
     * confirmed via the real media3-exoplayer 1.11.0 sources). Music:
     * [FilteringMediaSource] (confirmed real/public in the same sources
     * — "publishes tracks of one type") strips the clip's own audio
     * deterministically, [SilenceMediaSource] + [ConcatenatingMediaSource]
     * reproduce the same "start N ms into the clip" gap the old
     * Composition-based `addGap` gave us, and [MergingMediaSource]
     * combines the video-only branch with the (possibly gapped +
     * clipped) music branch into one Player/one clock — the standard,
     * long-established "video from one source, audio from another"
     * ExoPlayer pattern.
     */
    private fun buildPreviewMediaSource(): MediaSource {
        val dataSourceFactory = DefaultDataSource.Factory(context)
        val mediaSourceFactory = ProgressiveMediaSource.Factory(dataSourceFactory)

        val hasRealTrimWindow = trimEndMs > trimStartMs
        var videoSource: MediaSource =
            mediaSourceFactory.createMediaSource(MediaItem.fromUri(Uri.fromFile(File(sourcePath))))
        if (hasRealTrimWindow) {
            videoSource = ClippingMediaSource(videoSource, trimStartMs * 1000, trimEndMs * 1000)
        }

        val uri = musicUri
        val musicDur = musicDurationMs
        if (uri == null || musicDur == null) {
            return videoSource
        }

        val videoOnlySource = FilteringMediaSource(videoSource, C.TRACK_TYPE_VIDEO)
        var musicSource: MediaSource = mediaSourceFactory.createMediaSource(MediaItem.fromUri(uri))
        val playDurationMs = musicPlayDurationMs.coerceAtLeast(1L)
        musicSource = ClippingMediaSource(musicSource, 0L, playDurationMs * 1000)
        if (musicStartOffsetMs > 0) {
            musicSource = ConcatenatingMediaSource(SilenceMediaSource(musicStartOffsetMs * 1000), musicSource)
        }
        return MergingMediaSource(videoOnlySource, musicSource)
    }

    /**
     * Builds the EXPORT-time [Composition] — this path is completely
     * unaffected by the preview pivot above: it never used
     * CompositionPlayer, only [Transformer], a separate, long-stable
     * pipeline that has never been implicated in any crash this
     * session. Still the one source of truth for what actually gets
     * mixed/rendered into the published Ad.
     */
    private fun buildComposition(): Composition {
        DebugLog.log(context, "buildComposition: start trimStartMs=$trimStartMs trimEndMs=$trimEndMs")
        val hasRealTrimWindow = trimEndMs > trimStartMs
        DebugLog.log(context, "buildComposition: hasRealTrimWindow=$hasRealTrimWindow")
        val clippedVideo = MediaItem.Builder()
            .setUri(Uri.fromFile(File(sourcePath)))
            .apply {
                if (hasRealTrimWindow) {
                    setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(trimStartMs)
                            .setEndPositionMs(trimEndMs)
                            .build(),
                    )
                }
            }
            .build()
        DebugLog.log(context, "buildComposition: clippedVideo MediaItem built")
        val sourceDurationUs = probeDurationUs(context, Uri.fromFile(File(sourcePath)))
        DebugLog.log(context, "buildComposition: sourceDurationUs=$sourceDurationUs")
        val videoItem = EditedMediaItem.Builder(clippedVideo)
            .apply { if (sourceDurationUs != null) setDurationUs(sourceDurationUs) }
            .apply {
                if (rotationDegrees != 0) {
                    val rotateEffect: Effect =
                        ScaleAndRotateTransformation.Builder().setRotationDegrees(rotationDegrees.toFloat()).build()
                    setEffects(Effects(ImmutableList.of<AudioProcessor>(), ImmutableList.of(rotateEffect)))
                }
            }
            .build()
        DebugLog.log(context, "buildComposition: videoItem built rotationDegrees=$rotationDegrees")
        val hasAudio = !isMuted && sourceHasAudioTrack(sourcePath)
        DebugLog.log(context, "buildComposition: sourceHasAudioTrack(effective)=$hasAudio isMuted=$isMuted")
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

        val musicDurationUs = probeDurationUs(context, uri)
        DebugLog.log(
            context,
            "buildComposition: musicDurationUs=$musicDurationUs musicStartOffsetMs=$musicStartOffsetMs " +
                "musicPlayDurationMs=$musicPlayDurationMs",
        )
        val playDurationMs = musicPlayDurationMs.coerceAtLeast(1L)
        val clippedMusic = MediaItem.Builder()
            .setUri(uri)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(0)
                    .setEndPositionMs(playDurationMs)
                    .build(),
            )
            .build()
        val musicItem = EditedMediaItem.Builder(clippedMusic)
            .apply { if (musicDurationUs != null) setDurationUs(musicDurationUs) }
            .build()
        val musicSequence = EditedMediaItemSequence.Builder(ImmutableSet.of(C.TRACK_TYPE_AUDIO))
            .apply { if (musicStartOffsetMs > 0) addGap(musicStartOffsetMs * 1000) }
            .addItem(musicItem)
            .build()

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
        editorScope.cancel()
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

        /**
         * Probes [uri]'s real duration synchronously via
         * [MediaMetadataRetriever] (a plain, stable platform API — not
         * Media3-specific). `setDataSource(Context, Uri)` — not the
         * plain-`String` overload — handles both `file://` (the
         * captured clip) and `content://` (a music file picked via the
         * system audio picker) URIs uniformly.
         */
        fun probeDurationUs(context: Context, uri: Uri): Long? {
            val retriever = MediaMetadataRetriever()
            return try {
                retriever.setDataSource(context, uri)
                val durationMsString = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationMsString?.toLongOrNull()
                if (durationMs != null && durationMs > 0) durationMs * 1000 else null
            } catch (e: Exception) {
                Log.w("EditorViewModel", "probeDurationUs failed for $uri", e)
                null
            } finally {
                retriever.release()
            }
        }
    }
}
