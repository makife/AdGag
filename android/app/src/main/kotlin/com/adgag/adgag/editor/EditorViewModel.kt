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
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
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
        // New crash found on a real device, at a genuinely different
        // point than the two already fixed this session (video-clip/
        // duration ones): the checkpoint log stopped right after this
        // exact log line, with NOTHING after it — not even a "built OK"
        // — meaning the crash is inside CompositionPlayer.Builder(context)
        // .build() itself, before any composition/source file is even
        // involved. That call does real, heavy native work internally
        // (confirmed by reading CompositionPlayer's own constructor: it
        // starts a new HandlerThread at THREAD_PRIORITY_AUDIO and sets
        // up its own GL-backed video graph pipeline) — plausible to fail
        // under real device resource pressure. The reporting screenshot
        // showed the device at 6% battery, a real, non-code confounding
        // factor worth ruling out before assuming this is a code bug —
        // retest with the device charged before trusting this repros
        // reliably. Splitting the builder/build() call in two here so
        // the NEXT log, if it crashes again, at least confirms whether
        // Builder(context) itself (construction) or .build() (which
        // does the heavy HandlerThread/GL work) is the actual site.
        val builder = CompositionPlayer.Builder(context)
        DebugLog.log(context, "EditorViewModel: CompositionPlayer.Builder(context) constructed, calling build()")
        val built = builder.build()
        DebugLog.log(context, "EditorViewModel: builder.build() returned")
        // REAL BUG found via user report ("video sürekli tekrarlı
        // akmıyor... play butonu çalışmıyor"): repeatMode was never set
        // anywhere, so a plain STATE_ENDED was reached at the end of
        // every playthrough — and per standard ExoPlayer/Player
        // semantics, calling play() again on an ENDED player does
        // nothing at all without an explicit seekTo(0) first. This is
        // very likely the SAME root cause behind "video stops when
        // music is added" too: if the user attached music while
        // scrubbed near the clip's own end, the rebuilt player could
        // land in/near ENDED with no repeat mode to recover from it,
        // looking exactly like "stopped and won't resume." The Flutter
        // editor this replaces always called setLooping(true) on its
        // preview controller — this is the direct Player-interface
        // equivalent, just never carried over.
        built.repeatMode = Player.REPEAT_MODE_ONE
        DebugLog.log(context, "EditorViewModel: CompositionPlayer built OK, repeatMode=ONE")
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
        // that no longer fits — buildComposition()'s own clamping would
        // still keep the export correct even without this, but leaving
        // stale, now-out-of-range values in musicStartOffsetMs/
        // musicPlayDurationMs would make the timeline's own displayed
        // numbers wrong until the user happened to touch the music
        // segment again.
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
        // for as much of the song as fits — the same sensible default
        // the deleted Flutter editor used, now user-adjustable via the
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
        val wasPlaying = player.isPlaying
        val resumeAt = player.currentPosition
        rebuildAndPrepare(startAt = resumeAt, playWhenReady = wasPlaying)
    }

    fun toggleMute() {
        isMuted = !isMuted
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
        // REAL CRASH FOUND via the on-device checkpoint log: the very
        // FIRST call to this method (from init{}'s initial
        // rebuildAndPrepare, called before the player has ever reported
        // a real duration) ran with trimStartMs=0 and trimEndMs=0 — the
        // untouched defaults. The old code below always applied SOME
        // clipping configuration regardless, falling back to
        // `trimStartMs + 1` when trimEndMs wasn't yet meaningfully set,
        // which meant this first-ever composition was clipped to
        // [0ms, 1ms] — a degenerate, near-zero-length clip handed
        // straight into CompositionPlayer.setComposition(). The
        // checkpoint log confirmed the crash happens exactly at that
        // call, immediately after logging trimStartMs=0/trimEndMs=0 —
        // consistent with this being the actual cause, not just a
        // plausible theory. Fixed: only apply a ClippingConfiguration
        // once there's a genuine, positive-length trim window (either
        // the real duration has been learned and trimEndMs defaulted to
        // it, or the user actually dragged a trim handle) — otherwise
        // play the source unclipped, exactly like "no edit yet" should.
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
        // SECOND real crash found via the checkpoint log, after the 1ms-
        // clip fix (above) didn't actually resolve it: read
        // CompositionPlayer's own source directly
        // (createNonLoopingMediaSource in CompositionPlayer.java) and
        // found `checkArgument(editedMediaItem.durationUs != C.TIME_UNSET)`
        // — unlike Transformer (export), where setDurationUs is optional
        // and can be inferred from the file itself,
        // EditedMediaItem.Builder's own doc comment confirms this is
        // NOT optional for the player: it needs every item's duration
        // known upfront to build its internal playback graph before
        // decoding starts. This project's EditedMediaItems never called
        // setDurationUs at all — every single setComposition() call was
        // hitting this checkArgument. Probed with MediaMetadataRetriever
        // (durationUs must reflect the SOURCE's full, untrimmed length
        // per the setter's own doc comment, not the clipped range).
        val sourceDurationUs = probeDurationUs(context, Uri.fromFile(File(sourcePath)))
        DebugLog.log(context, "buildComposition: sourceDurationUs=$sourceDurationUs")
        val videoItem = EditedMediaItem.Builder(clippedVideo)
            .apply { if (sourceDurationUs != null) setDurationUs(sourceDurationUs) }
            .apply {
                // ScaleAndRotateTransformation confirmed usable here by
                // reading its real source: it implements
                // MatrixTransformation -> GlMatrixTransformation ->
                // GlEffect -> Effect, so it's a valid Effects.videoEffects
                // entry directly — not guessed.
                if (rotationDegrees != 0) {
                    val rotateEffect: Effect =
                        ScaleAndRotateTransformation.Builder().setRotationDegrees(rotationDegrees.toFloat()).build()
                    setEffects(Effects(ImmutableList.of<AudioProcessor>(), ImmutableList.of(rotateEffect)))
                }
            }
            .build()
        DebugLog.log(context, "buildComposition: videoItem built rotationDegrees=$rotationDegrees")
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
        // Mute forces video-only regardless of what the source actually
        // has, reusing the exact same withVideoFrom path already proven
        // safe for a genuinely audio-less source above — no new API
        // surface for this feature.
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

        // Volume/gain control (GainProcessor) is a deliberate phase-2
        // follow-up, not shipped blind here — its exact constructor
        // needs verifying against the real media3-common 1.11.0 sources
        // (same verification method used for EditedMediaItemSequence
        // above) rather than guessed, since a wrong signature is a build
        // break, not a soft failure. Music plays at its own source level
        // for now.
        val musicDurationUs = probeDurationUs(context, uri)
        DebugLog.log(
            context,
            "buildComposition: musicDurationUs=$musicDurationUs musicStartOffsetMs=$musicStartOffsetMs " +
                "musicPlayDurationMs=$musicPlayDurationMs",
        )
        // Real feature added via user report ("eklenen müziği
        // kesemiyorum" / can't cut the added music): the music
        // MediaItem is now clipped to [0, musicPlayDurationMs] — the
        // exact same ClippingConfiguration pattern already proven safe
        // for the video above — so a user-shortened segment actually
        // only plays that much of the song, not the whole file.
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
        // Real feature added: musicStartOffsetMs positions the segment
        // within the clip's own timeline via addGap — confirmed usable
        // here by reading EditedMediaItemSequence's own real source
        // (Builder.addGap(durationUs), the same mechanism
        // withAudioFrom's own implementation is built on internally),
        // not guessed. isLooping=false (unchanged): this app's
        // BackgroundAudio model never asked for the music to loop past
        // the clip's own end.
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
         * Media3-specific), needed because [CompositionPlayer] requires
         * every [EditedMediaItem]'s `durationUs` known upfront (see the
         * call site's own comment on the real crash this fixes).
         * `setDataSource(Context, Uri)` — not the plain-`String`
         * overload — handles both `file://` (the captured clip) and
         * `content://` (a music file picked via the system audio
         * picker) URIs uniformly.
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
