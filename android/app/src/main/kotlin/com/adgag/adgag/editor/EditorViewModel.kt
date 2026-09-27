package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.TextureOverlay
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.FilteringMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SilenceMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Native editor state: a sequence of recorded clips (each trimmable),
 * an entrance transition between each pair, optional background music
 * placed on the whole timeline, rotate, mute, export.
 *
 * TIME SYSTEMS — read this before touching any position math:
 * - clip SOURCE time: position inside one clip's own file (trims live here).
 * - GLOBAL time: position on the combined timeline, 0 = first kept frame
 *   of the first clip; clip i starts at [clipStartMs]`(i)`. Music
 *   placement and the timeline's playhead live here.
 * - player time: the preview is an ExoPlayer PLAYLIST of [segments];
 *   `currentPosition` is relative to the current playlist item.
 *   [globalPositionMs]/[seekToGlobal] are the only conversions.
 *
 * PREVIEW vs EXPORT (see the older checkpoint history for why the
 * preview is plain ExoPlayer, not CompositionPlayer): the export goes
 * through Transformer/[Composition] and genuinely mixes the clips' own
 * audio with the music; the preview can't mix, so while music is
 * attached it plays the music only.
 */
@UnstableApi
class EditorViewModel(
    private val context: Context,
    initialState: EditorSessionState,
    /** A clip just recorded via the timeline's "+" — appended before the first preview build. */
    newClipPath: String? = null,
) : ViewModel() {

    val player: ExoPlayer = ExoPlayer.Builder(context)
        // Take audio focus like any media app: another app's playback (or
        // a call) pauses the preview, and so do unplugged headphones.
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            /* handleAudioFocus = */ true,
        )
        .setHandleAudioBecomingNoisy(true)
        .build().apply {
        // The whole playlist loops (REPEAT_MODE_ONE would loop only the
        // current segment). Without a repeat mode a finished player
        // ignores play() — the original "play doesn't work" bug.
        repeatMode = Player.REPEAT_MODE_ALL
    }

    var clips by mutableStateOf(initialState.clips)
        private set
    /** transitions[i] = the boundary between clip i and clip i+1. Always clips.size - 1 long. */
    var transitions by mutableStateOf(normalizeTransitions(initialState.transitions, initialState.clips.size))
        private set
    /** Which clip the trim row below the clip strip is editing. */
    var selectedClipIndex by mutableStateOf(0)
        private set

    /**
     * Whole-video speed (slow motion down to 0.25x). Clip trims and the
     * clip strip stay in SOURCE time; the 30s cap, the music row and the
     * transitions are in OUTPUT time (source / speed).
     */
    var videoSpeed by mutableStateOf(initialState.videoSpeed)
        private set

    /** Sum of the clips' kept parts, SOURCE time. */
    val totalDurationMs: Long get() = clips.sumOf { it.keptDurationMs }
    /** How long the finished Ad plays. */
    val outputDurationMs: Long get() = (totalDurationMs / videoSpeed).toLong()
    /** How much SOURCE time fits under the 30s OUTPUT cap at the current speed. */
    val sourceBudgetMs: Long get() = (MaxTotalDurationMs * videoSpeed).toLong()
    /** SOURCE time still free — also the camera's limit for an extra take. */
    val remainingMs: Long get() = (sourceBudgetMs - totalDurationMs).coerceAtLeast(0L)
    val canAddClip: Boolean get() = remainingMs >= MinClipDurationMs

    fun canUseVideoSpeed(speed: Float): Boolean = (totalDurationMs / speed).toLong() <= MaxTotalDurationMs

    var isPlaying by mutableStateOf(false)
        private set

    /** Absolute path of a private COPY of the picked music (see [setMusic]) — survives the editor being relaunched to record another clip. */
    var musicPath by mutableStateOf(initialState.musicPath)
        private set
    var musicDurationMs by mutableStateOf<Long?>(null)
        private set
    /** Global time where the music starts, and how much of the song (from its own start) plays. */
    var musicStartOffsetMs by mutableStateOf(initialState.musicStartOffsetMs)
        private set
    var musicPlayDurationMs by mutableStateOf(initialState.musicPlayDurationMs)
        private set
    /** Where in the SONG the used part begins — the music row's LEFT trim handle. */
    var musicSourceStartMs by mutableStateOf(initialState.musicSourceStartMs)
        private set
    /** The picked song, untouched; [musicPath] is this re-timed to [musicSpeed]. */
    var musicOriginalPath by mutableStateOf(initialState.musicOriginalPath)
        private set
    var musicSpeed by mutableStateOf(initialState.musicSpeed)
        private set
    var musicFadeInMs by mutableStateOf(initialState.musicFadeInMs)
        private set
    var musicFadeOutMs by mutableStateOf(initialState.musicFadeOutMs)
        private set
    /** Repeat the selected part of the song back to back until the video ends. */
    var musicLoop by mutableStateOf(initialState.musicLoop)
        private set

    /** How much of the timeline the music covers (OUTPUT time): one play, or — looping — up to the video's end. */
    val musicCoveredMs: Long
        get() = if (musicLoop && musicPlayDurationMs > 0) {
            (outputDurationMs - musicStartOffsetMs).coerceAtLeast(musicPlayDurationMs)
        } else {
            musicPlayDurationMs
        }

    /** Each play of the selected part: (OUTPUT start, length). One entry unless looping. */
    fun musicRepetitions(): List<Pair<Long, Long>> {
        val unit = musicPlayDurationMs
        if (musicPath == null || unit <= 0) return emptyList()
        val end = musicStartOffsetMs + musicCoveredMs
        val result = mutableListOf<Pair<Long, Long>>()
        var start = musicStartOffsetMs
        while (start < end && result.size < 200) {
            val len = minOf(unit, end - start)
            // A sliver under 100ms isn't worth its own item (and would click).
            if (len < 100 && result.isNotEmpty()) break
            result += start to len
            start += unit
        }
        return result
    }

    /**
     * PREVIEW-ONLY song file. The preview player runs at [videoSpeed] and
     * that slows/speeds EVERYTHING it plays, music included — so the
     * preview gets the original re-timed to musicSpeed / videoSpeed, which
     * the player then plays back at exactly musicSpeed. (Positions inside
     * it are musicPath positions × videoSpeed.) Null = not ready yet;
     * the preview plays silence meanwhile. Not persisted — rebuilt.
     */
    private var musicPreviewPath: String? = null
    private var musicPreviewDurationMs = 0L
    private var musicJob: Job? = null

    /** A music operation (copy, re-timing) is running. */
    var isAttachingMusic by mutableStateOf(false)
        private set

    var rotationDegrees by mutableStateOf(initialState.rotationDegrees)
        private set

    /** Whole-video look effect (VideoFilters.kt). */
    var videoFilter by mutableStateOf(initialState.videoFilter)
        private set

    /**
     * Captions (TextLayers.kt). Pure overlay state: changing them never
     * rebuilds the player — the preview draws them in Compose over the
     * video, the export adds them as ONE composition-level overlay.
     */
    var textLayers by mutableStateOf(initialState.textLayers)
        private set

    /** Animated stickers (Stickers.kt) — overlay state like the captions. */
    var stickerLayers by mutableStateOf(initialState.stickerLayers)
        private set

    /** The caption OR sticker being edited/dragged in the preview (null = none; ids are unique across both). */
    var selectedTextId by mutableStateOf<String?>(null)

    val fonts = TypefaceCache(context)
    val stickers = StickerStore(context)

    fun addSticker(def: StickerDef): StickerLayer {
        player.pause()
        val total = outputDurationMs.coerceAtLeast(500L)
        val now = (globalPositionMs() / videoSpeed).toLong().coerceIn(0L, total)
        val start = if (total - now < 1_000L) (total - 3_000L).coerceAtLeast(0L) else now
        // Staggered a little so several stickers don't land exactly on top of each other.
        val n = stickerLayers.size % 5
        val layer = StickerLayer(
            stickerId = def.id,
            x = 0.5f + (n - 2) * 0.06f,
            y = 0.32f + (n % 2) * 0.05f,
            startMs = start,
            endMs = minOf(total, start + 3_000L),
        )
        stickerLayers = stickerLayers + layer
        selectedTextId = layer.id
        return layer
    }

    fun updateSticker(layer: StickerLayer) {
        stickerLayers = stickerLayers.map { if (it.id == layer.id) layer else it }
    }

    fun removeSticker(id: String) {
        stickerLayers = stickerLayers.filterNot { it.id == id }
        if (selectedTextId == id) selectedTextId = null
    }

    fun addText(): TextLayer {
        val total = outputDurationMs.coerceAtLeast(500L)
        val now = (globalPositionMs() / videoSpeed).toLong().coerceIn(0L, total)
        val start = if (total - now < 1_000L) (total - 3_000L).coerceAtLeast(0L) else now
        val layer = TextLayer(startMs = start, endMs = minOf(total, start + 3_000L))
        textLayers = textLayers + layer
        selectedTextId = layer.id
        return layer
    }

    fun updateText(layer: TextLayer) {
        textLayers = textLayers.map { if (it.id == layer.id) layer else it }
    }

    fun removeText(id: String) {
        textLayers = textLayers.filterNot { it.id == id }
        if (selectedTextId == id) selectedTextId = null
    }

    /** Timeline drag of a caption's or sticker's timing, clamped to the Ad (OUTPUT time), at least 300ms long. */
    fun setOverlayTiming(id: String, startMs: Long, endMs: Long) {
        val total = outputDurationMs
        val s = startMs.coerceIn(0L, (total - 300L).coerceAtLeast(0L))
        val e = endMs.coerceIn(s + 300L, total.coerceAtLeast(s + 300L))
        textLayers = textLayers.map { if (it.id == id) it.copy(startMs = s, endMs = e) else it }
        stickerLayers = stickerLayers.map { if (it.id == id) it.copy(startMs = s, endMs = e) else it }
    }

    /** Picker thumbnails: each effect applied (on the CPU) to a frame of the first clip. */
    val filterThumbnails = mutableStateMapOf<VideoFilter, Bitmap>()

    /**
     * PREVIEW EFFECTS CRASH GUARD. Showing an effect live means
     * ExoPlayer.setVideoEffects, which builds a GPU frame-processing
     * pipeline — the same kind of GL machinery that made
     * CompositionPlayer.Builder().build() crash natively on the user's
     * device earlier (see the checkpoint history). A native crash can't be
     * caught, so: before the first enable we write "pending" to disk
     * (synchronously), and "ok" once a frame has actually rendered. If a
     * later launch still finds "pending", the process died in between —
     * live preview of effects is switched off on this device (the export,
     * which already runs through Transformer's own GL pipeline, still
     * applies them). Not attempted at all until an effect is chosen, so
     * editing without effects never touches this path.
     */
    private val prefs = context.getSharedPreferences("adgag_editor", Context.MODE_PRIVATE)
    var previewEffectsSupported by mutableStateOf(prefs.getString(PrefPreviewEffects, null) != "pending")
        private set
    private var previewEffectsActive = false
    private var awaitingEffectsFirstFrame = false
    var isMuted by mutableStateOf(initialState.isMuted)
        private set

    /** Per clip path: frames evenly spaced across that clip's SOURCE, as (sourceTimeMs, bitmap). */
    val thumbnails = mutableStateMapOf<String, List<Pair<Long, Bitmap>>>()

    private val editorScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var isExporting by mutableStateOf(false)
        private set
    var exportProgress by mutableStateOf(0f)
        private set
    var exportError by mutableStateOf<String?>(null)
        private set
    var previewError by mutableStateOf<String?>(null)
        private set

    /** One playlist item of the preview — see [buildSegments]. */
    private data class Segment(val clipIndex: Int, val globalStartMs: Long, val lengthMs: Long, val sourceStartMs: Long)

    private var segments: List<Segment> = emptyList()

    /**
     * HARDWARE CODEC BUDGET — the root cause behind three real-device
     * reports at once (editor crashing while opening, preview
     * DECODER_INIT_FAILED with format_supported=YES, export failing with
     * a Codec exception on the Qualcomm encoder): phones have a small
     * number of hardware codec instances, and this screen was asking for
     * too many at the same time — the preview player's decoders, one
     * MediaMetadataRetriever decoder PER CLIP for thumbnails (launched in
     * parallel), and at export time the still-allocated preview decoders
     * plus Transformer's own decoders and encoder. Rules now:
     * - thumbnails wait until the preview is up ([previewReady]) and run
     *   one clip at a time ([thumbnailMutex]);
     * - export releases the preview's codecs first (player.stop()) and
     *   rebuilds the preview afterwards;
     * - a decoder that fails to initialize is retried (codecs released by
     *   a previous screen, e.g. the camera, can take a moment).
     */
    private val previewReady = CompletableDeferred<Unit>()
    private val thumbnailMutex = Mutex()
    private var decoderRetries = 0

    init {
        DebugLog.log(context, "EditorViewModel: init clips=${clips.size}")
        musicDurationMs = musicPath?.let { probeDurationUs(context, Uri.fromFile(File(it)))?.div(1000) }
        if (musicPath != null && musicDurationMs == null) musicPath = null
        if (musicOriginalPath == null) musicOriginalPath = musicPath
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onRenderedFirstFrame() {
                if (awaitingEffectsFirstFrame) {
                    awaitingEffectsFirstFrame = false
                    prefs.edit().putString(PrefPreviewEffects, "ok").commit()
                    DebugLog.log(context, "preview effects: first frame rendered OK")
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) {
                    decoderRetries = 0
                    previewReady.complete(Unit)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e("EditorViewModel", "Preview player error", error)
                if (previewEffectsActive &&
                    (error.errorCode == PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSOR_INIT_FAILED ||
                        error.errorCode == PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED)
                ) {
                    // The GL effects pipeline failed (but didn't crash): stop
                    // previewing effects for this session and carry on.
                    previewEffectsSupported = false
                    DebugLog.log(context, "preview effects failed: ${error.errorCodeName}")
                    val resumeAt = globalPositionMs()
                    editorScope.launch { rebuildAndPrepare(startGlobalMs = resumeAt, playWhenReady = true) }
                    return
                }
                DebugLog.log(context, "player error: ${error.errorCodeName} ${error.message}")
                // Don't hold thumbnails back forever behind a broken preview.
                previewReady.complete(Unit)
                val codecBusy = error.errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED ||
                    error.errorCode == PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED
                if (codecBusy && decoderRetries < 3) {
                    // A codec just released elsewhere (camera, export,
                    // thumbnails) may not be free yet — back off and retry.
                    decoderRetries++
                    val resumeAt = globalPositionMs()
                    editorScope.launch {
                        delay(400L * decoderRetries)
                        rebuildAndPrepare(startGlobalMs = resumeAt, playWhenReady = true)
                    }
                    return
                }
                // Surfaced, not swallowed — a silent player error is
                // exactly what "the video froze" looks like to a user.
                previewError = "${error.errorCodeName}: ${error.message}"
            }
        })
        var startAt = 0L
        if (newClipPath != null && appendClip(newClipPath)) {
            // Show the new clip (and the transition into it) right away.
            startAt = (clipStartMs(clips.lastIndex) - 1000).coerceAtLeast(0L)
        }
        rebuildAndPrepare(startGlobalMs = startAt, playWhenReady = true)
        clips.forEach { generateThumbnails(it.path) }
        // The preview music file isn't persisted across the "+" relaunch.
        if (musicPath != null) refreshPreviewMusic()
    }

    fun sessionState(): EditorSessionState = EditorSessionState(
        clips = clips,
        transitions = transitions,
        musicPath = musicPath,
        musicOriginalPath = musicOriginalPath,
        musicSpeed = musicSpeed,
        musicFadeInMs = musicFadeInMs,
        musicFadeOutMs = musicFadeOutMs,
        musicLoop = musicLoop,
        musicStartOffsetMs = musicStartOffsetMs,
        musicSourceStartMs = musicSourceStartMs,
        musicPlayDurationMs = musicPlayDurationMs,
        rotationDegrees = rotationDegrees,
        isMuted = isMuted,
        videoSpeed = videoSpeed,
        videoFilter = videoFilter,
        textLayers = textLayers,
        stickerLayers = stickerLayers,
    )

    fun clipStartMs(index: Int): Long = clips.take(index).sumOf { it.keptDurationMs }

    /** Current playback position on the GLOBAL timeline. */
    fun globalPositionMs(): Long {
        val seg = segments.getOrNull(player.currentMediaItemIndex) ?: return 0L
        return seg.globalStartMs + player.currentPosition.coerceIn(0L, seg.lengthMs)
    }

    fun seekToGlobal(globalMs: Long) {
        if (segments.isEmpty()) return
        val g = globalMs.coerceIn(0L, (totalDurationMs - 1).coerceAtLeast(0L))
        val index = segments.indexOfLast { it.globalStartMs <= g }.coerceAtLeast(0)
        player.seekTo(index, g - segments[index].globalStartMs)
    }

    fun togglePlayPause() {
        if (player.isPlaying) player.pause() else player.play()
    }

    fun selectClip(index: Int) {
        if (index in clips.indices) selectedClipIndex = index
    }

    /** Trims clip [index] (both values in that clip's SOURCE time). */
    fun setClipTrim(index: Int, startMs: Long, endMs: Long) {
        val clip = clips.getOrNull(index) ?: return
        // The other clips' kept time is fixed; this one may use whatever
        // is left of the 30s cap.
        val othersMs = totalDurationMs - clip.keptDurationMs
        val maxKept = (sourceBudgetMs - othersMs).coerceAtLeast(MinClipDurationMs)
        val start = startMs.coerceIn(0L, clip.sourceDurationMs)
        val end = endMs.coerceIn(start, minOf(clip.sourceDurationMs, start + maxKept))
        clips = clips.toMutableList().also { it[index] = clip.copy(trimStartMs = start, trimEndMs = end) }
        clampMusicToTimeline()
        // Restart from where the edited clip now begins: any old
        // position refers to content that moved.
        rebuildAndPrepare(startGlobalMs = clipStartMs(index), playWhenReady = player.playWhenReady)
    }

    /** Appends a recorded clip, trimmed to whatever is left of the 30s cap. Returns false if it couldn't be read or there's no room. */
    private fun appendClip(path: String): Boolean {
        val sourceMs = probeDurationUs(context, Uri.fromFile(File(path)))?.div(1000) ?: return false
        val kept = minOf(sourceMs, remainingMs)
        if (kept <= 0L) return false
        clips = clips + EditorClip(path, sourceMs, 0L, kept)
        transitions = normalizeTransitions(transitions, clips.size)
        selectedClipIndex = clips.lastIndex
        return true
    }

    fun removeClip(index: Int) {
        if (clips.size <= 1 || index !in clips.indices) return
        clips = clips.toMutableList().also { it.removeAt(index) }
        // Drop the transition INTO the removed clip (or out of it, for the first clip).
        transitions = transitions.toMutableList().also { if (it.isNotEmpty()) it.removeAt((index - 1).coerceAtLeast(0)) }
        selectedClipIndex = selectedClipIndex.coerceIn(0, clips.lastIndex)
        clampMusicToTimeline()
        rebuildAndPrepare(startGlobalMs = 0L, playWhenReady = player.playWhenReady)
    }

    /** [boundaryIndex] 0 = between clip 0 and clip 1. Keeps that boundary's duration. */
    fun setTransitionType(boundaryIndex: Int, type: ClipTransition) {
        if (boundaryIndex !in transitions.indices) return
        transitions = transitions.toMutableList().also { it[boundaryIndex] = it[boundaryIndex].copy(type = type) }
        replayTransition(boundaryIndex)
    }

    /** Updates the duration only (called continuously while the slider moves — no replay here). */
    fun setTransitionDuration(boundaryIndex: Int, durationMs: Long) {
        if (boundaryIndex !in transitions.indices) return
        val d = durationMs.coerceIn(MinTransitionDurationMs, MaxTransitionDurationMs)
        transitions = transitions.toMutableList().also { it[boundaryIndex] = it[boundaryIndex].copy(durationMs = d) }
    }

    /**
     * Plays the boundary so the effect can be seen. Preview transitions
     * are drawn by Compose over the player, so no rebuild — just seek to
     * a bit before the boundary (far enough back to show a fade-out too).
     */
    fun replayTransition(boundaryIndex: Int) {
        val spec = transitions.getOrNull(boundaryIndex) ?: return
        val start = clipStartMs(boundaryIndex + 1)
        // Lead-in is in OUTPUT time; the timeline position is SOURCE time.
        val lead = (maxOf(1000L, spec.durationMs + 500L) * videoSpeed).toLong()
        seekToGlobal((start - lead).coerceAtLeast(0L))
        player.play()
    }

    /**
     * Copies the picked audio into app-private storage first: a
     * content:// grant from the picker doesn't survive this Activity
     * being finished and relaunched for another recording, a file does.
     */
    fun setMusic(uri: Uri?) {
        if (uri == null) {
            removeMusic()
            return
        }
        isAttachingMusic = true
        musicJob?.cancel()
        musicJob = editorScope.launch {
            val copied = withContext(Dispatchers.IO) {
                try {
                    val dest = File(context.filesDir, "editor_music_${System.currentTimeMillis()}")
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        dest.outputStream().use { input.copyTo(it) }
                    } ?: return@withContext null
                    val ms = probeDurationUs(context, Uri.fromFile(dest))?.div(1000)
                    if (ms == null) {
                        dest.delete()
                        null
                    } else {
                        dest.absolutePath to ms
                    }
                } catch (e: Exception) {
                    Log.w("EditorViewModel", "Copying picked music failed", e)
                    null
                }
            }
            if (copied == null) {
                isAttachingMusic = false
                previewError = "Couldn't read that audio file."
                return@launch
            }
            musicOriginalPath = copied.first
            musicPath = copied.first
            musicDurationMs = copied.second
            musicSpeed = 1f
            musicFadeInMs = 0L
            musicFadeOutMs = 0L
            musicStartOffsetMs = 0L
            musicSourceStartMs = 0L
            musicPlayDurationMs = minOf(copied.second, outputDurationMs)
            // A song shorter than the video starts out looping to fill it
            // (switchable in the music sheet).
            musicLoop = copied.second < outputDurationMs
            preparePreviewMusicAndRebuild()
        }
    }

    fun removeMusic() {
        musicJob?.cancel()
        isAttachingMusic = false
        musicPath = null
        musicOriginalPath = null
        musicPreviewPath = null
        musicDurationMs = null
        musicSpeed = 1f
        musicFadeInMs = 0L
        musicFadeOutMs = 0L
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = player.playWhenReady)
    }

    /**
     * Re-times the music (pitch kept). The kept part of the song stays the
     * same stretch of the SONG, so its in-point and length scale by
     * old/new speed.
     */
    fun changeMusicSpeed(speed: Float) {
        val original = musicOriginalPath ?: return
        if (speed == musicSpeed) return
        val oldSpeed = musicSpeed
        isAttachingMusic = true
        musicJob?.cancel()
        musicJob = editorScope.launch {
            try {
                val retimed = if (speed == 1f) original else bakeMusicSpeed(context, original, speed)
                val songMs = probeDurationUs(context, Uri.fromFile(File(retimed)))?.div(1000) ?: return@launch
                musicSpeed = speed
                musicPath = retimed
                musicDurationMs = songMs
                val factor = oldSpeed / speed
                musicSourceStartMs = (musicSourceStartMs * factor).toLong().coerceIn(0L, (songMs - 1).coerceAtLeast(0L))
                musicPlayDurationMs = (musicPlayDurationMs * factor).toLong()
                clampMusicToTimeline()
                preparePreviewMusicAndRebuild()
            } catch (e: CancellationException) {
                throw e // superseded by a newer music change — not an error
            } catch (e: Exception) {
                Log.w("EditorViewModel", "Re-timing music failed", e)
                previewError = "Couldn't change the music speed."
                isAttachingMusic = false
            }
        }
    }

    fun changeMusicLoop(loop: Boolean) {
        if (loop == musicLoop) return
        musicLoop = loop
        setMusicFade(musicFadeInMs, musicFadeOutMs) // re-clamp against the new coverage
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = player.playWhenReady)
    }

    fun setMusicFade(fadeInMs: Long, fadeOutMs: Long) {
        val play = musicCoveredMs.coerceAtLeast(0L)
        musicFadeInMs = fadeInMs.coerceIn(0L, minOf(MaxMusicFadeMs, play))
        musicFadeOutMs = fadeOutMs.coerceIn(0L, minOf(MaxMusicFadeMs, play))
        // No rebuild: the preview applies fades through player volume.
    }

    fun changeVideoSpeed(speed: Float) {
        if (speed == videoSpeed || !canUseVideoSpeed(speed)) return
        videoSpeed = speed
        clampMusicToTimeline()
        if (musicPath != null) {
            refreshPreviewMusic()
        } else {
            rebuildAndPrepare(startGlobalMs = 0L, playWhenReady = true)
        }
    }

    /**
     * Drives the music's fade-in/out in the PREVIEW via player volume (the
     * preview's only audio while music is attached), once per frame from
     * EditorScreen. [globalMs] is the SOURCE-time playhead.
     */
    fun updatePreviewVolume(globalMs: Long) {
        if (musicPath == null) {
            player.volume = if (isMuted) 0f else 1f
            return
        }
        val local = (globalMs / videoSpeed).toLong() - musicStartOffsetMs
        val covered = musicCoveredMs
        // Fades wrap the WHOLE covered span (a loop fades in once, out once).
        player.volume = if (local in 0 until covered) {
            fadeGain(local, musicFadeInMs, musicFadeOutMs, covered)
        } else {
            1f
        }
    }

    private fun refreshPreviewMusic() {
        isAttachingMusic = true
        musicJob?.cancel()
        musicJob = editorScope.launch {
            try {
                preparePreviewMusicAndRebuild()
            } catch (e: CancellationException) {
                throw e // superseded by a newer music change — not an error
            } catch (e: Exception) {
                Log.w("EditorViewModel", "Preparing preview music failed", e)
                previewError = "Couldn't prepare the music preview."
                isAttachingMusic = false
            }
        }
    }

    /** See [musicPreviewPath]: the original re-timed to musicSpeed / videoSpeed. */
    private suspend fun preparePreviewMusicAndRebuild() {
        val original = musicOriginalPath
        val retimed = musicPath
        if (original == null || retimed == null) {
            isAttachingMusic = false
            return
        }
        val ratio = musicSpeed / videoSpeed
        val preview = when {
            videoSpeed == 1f -> retimed
            ratio == 1f -> original
            else -> bakeMusicSpeed(context, original, ratio)
        }
        musicPreviewPath = preview
        musicPreviewDurationMs = probeDurationUs(context, Uri.fromFile(File(preview)))?.div(1000) ?: 0L
        isAttachingMusic = false
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = player.playWhenReady)
    }

    /**
     * Places the music: [startOffsetMs] on the GLOBAL timeline, using the
     * song from [sourceStartMs] for [playDurationMs]. Clamped to the
     * timeline and to the song's own length.
     */
    fun setMusicPlacement(startOffsetMs: Long, sourceStartMs: Long, playDurationMs: Long) {
        val songMs = musicDurationMs ?: return
        val total = outputDurationMs
        val start = startOffsetMs.coerceIn(0L, total)
        val sourceStart = sourceStartMs.coerceIn(0L, (songMs - 1).coerceAtLeast(0L))
        musicStartOffsetMs = start
        musicSourceStartMs = sourceStart
        musicPlayDurationMs = playDurationMs.coerceIn(0L, minOf(songMs - sourceStart, total - start))
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = player.playWhenReady)
    }

    fun rotateNinety() {
        // Preview rotation is a Compose transform on the surface (plain
        // ExoPlayer has no effects pipeline); export bakes the real
        // rotation in via ScaleAndRotateTransformation.
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    fun changeFilter(filter: VideoFilter) {
        if (filter == videoFilter) return
        videoFilter = filter
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = true)
    }

    /** Lets the user retry live effect preview after the crash guard switched it off. */
    fun retryPreviewEffects() {
        prefs.edit().remove(PrefPreviewEffects).commit()
        previewEffectsSupported = true
        rebuildAndPrepare(startGlobalMs = globalPositionMs(), playWhenReady = true)
    }

    /** Renders the picker thumbnails once (from a frame of the first clip), off the main thread. */
    fun ensureFilterThumbnails() {
        if (filterThumbnails.isNotEmpty()) return
        val frames = clips.firstOrNull()?.let { thumbnails[it.path] }.orEmpty()
        val source = frames.getOrNull(frames.size / 2)?.second ?: return
        editorScope.launch {
            val small = withContext(Dispatchers.Default) {
                val w = 72
                val h = (w * source.height.toFloat() / source.width).toInt().coerceAtLeast(1)
                val scaled = Bitmap.createScaledBitmap(source, w, h, true)
                VideoFilter.entries.associateWith { FilterCpu.render(it, scaled) }
            }
            filterThumbnails.putAll(small)
        }
    }

    /**
     * Applies [videoFilter] to the PREVIEW player — see the crash guard on
     * [previewEffectsSupported]. Must run before prepare() (ExoPlayer sets
     * the effects pipeline up at prepare time).
     */
    private fun applyPreviewFilter() {
        if (!previewEffectsSupported) return
        if (videoFilter == VideoFilter.NONE && !previewEffectsActive) return
        if (!previewEffectsActive) {
            prefs.edit().putString(PrefPreviewEffects, "pending").commit()
            DebugLog.log(context, "preview effects: enabling (pending)")
            previewEffectsActive = true
            awaitingEffectsFirstFrame = true
        }
        try {
            player.setVideoEffects(
                if (videoFilter == VideoFilter.NONE) emptyList() else listOf<Effect>(FilterEffect(videoFilter)),
            )
        } catch (e: Exception) {
            Log.w("EditorViewModel", "setVideoEffects failed", e)
            previewEffectsSupported = false
        }
    }

    fun toggleMute() {
        isMuted = !isMuted
        applyPreviewVolume()
    }

    fun clearPreviewError() {
        previewError = null
    }

    private fun applyPreviewVolume() {
        // With music attached the preview carries only the music (no live
        // mixing), so mute only applies to the no-music preview.
        if (musicPath == null) player.volume = if (isMuted) 0f else 1f
    }

    private fun clampMusicToTimeline() {
        if (musicPath == null) return
        val total = outputDurationMs
        musicStartOffsetMs = musicStartOffsetMs.coerceIn(0L, total)
        musicPlayDurationMs = musicPlayDurationMs.coerceIn(0L, total - musicStartOffsetMs)
    }

    private fun generateThumbnails(path: String) {
        if (thumbnails.containsKey(path)) return
        editorScope.launch {
            // See the codec budget note: after the preview is up, one clip at a time, never during export.
            previewReady.await()
            thumbnailMutex.withLock {
                while (isExporting) delay(250)
                if (!thumbnails.containsKey(path)) thumbnails[path] = extractThumbnails(path)
            }
        }
    }

    private suspend fun extractThumbnails(path: String): List<Pair<Long, Bitmap>> =
        withContext(Dispatchers.IO) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val totalMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                if (totalMs == null || totalMs <= 0) {
                    emptyList()
                } else {
                    val count = 10
                    (0 until count).mapNotNull { i ->
                        val timeMs = totalMs * i / count
                        try {
                            val frame = if (android.os.Build.VERSION.SDK_INT >= 27) {
                                retriever.getScaledFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 160, 284)
                            } else {
                                retriever.getFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            }
                            frame?.let { timeMs to it }
                        } catch (e: Exception) {
                            null
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w("EditorViewModel", "Thumbnail generation failed for $path", e)
                emptyList()
            } finally {
                retriever.release()
            }
        }

    /**
     * Splits the timeline into playlist items so music can be attached
     * with MergingMediaSource. MergingMediaSource requires every merged
     * child to have the SAME number of periods (confirmed in the
     * media3-exoplayer 1.11.0 sources: IllegalMergeException
     * REASON_PERIOD_COUNT_MISMATCH) — so "silence + music + silence"
     * concatenated against a one-period clip is illegal (that was the
     * real cause of the music-attached freeze). Instead each clip is cut
     * at the music's start/end, and every piece merges one video slice
     * with exactly one audio piece of the same length: a music slice, or
     * silence. Without music: one segment per clip, its own audio.
     */
    private fun buildSegments(): List<Segment> {
        // Music placement is OUTPUT time; the playlist is SOURCE time. Every
        // repetition's start and end is a cut, so each playlist item holds
        // at most one piece of one repetition.
        val musicCuts = musicRepetitions().flatMap { (start, len) ->
            listOf((start * videoSpeed).toLong(), ((start + len) * videoSpeed).toLong())
        }
        val result = mutableListOf<Segment>()
        var g = 0L
        clips.forEachIndexed { i, clip ->
            val ge = g + clip.keptDurationMs
            val cuts = mutableListOf(g, ge)
            // Skip cut points hugging a clip edge — a few-ms playlist item only adds a hiccup.
            musicCuts.forEach { c -> if (c > g + 50 && c < ge - 50) cuts += c }
            val sorted = cuts.distinct().sorted()
            for (k in 0 until sorted.size - 1) {
                val a = sorted[k]
                val b = sorted[k + 1]
                if (b - a <= 0) continue
                result += Segment(clipIndex = i, globalStartMs = a, lengthMs = b - a, sourceStartMs = clip.trimStartMs + (a - g))
            }
            g = ge
        }
        return result
    }

    private fun rebuildAndPrepare(startGlobalMs: Long, playWhenReady: Boolean) {
        previewError = null
        segments = buildSegments()
        // Constant-bitrate seeking: music is sliced at clip boundaries, so
        // a slice can start mid-song — a VBR MP3 without a seek table is
        // otherwise "unseekable" and ClippingMediaSource rejects a
        // non-zero start (IllegalClippingException).
        val factory = ProgressiveMediaSource.Factory(
            DefaultDataSource.Factory(context),
            DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true),
        )
        val music = musicPath
        val previewMusic = musicPreviewPath
        val repetitions = musicRepetitions()
        val sources = segments.map { seg ->
            val clip = clips[seg.clipIndex]
            val video: MediaSource = ClippingMediaSource(
                factory.createMediaSource(MediaItem.fromUri(Uri.fromFile(File(clip.path)))),
                seg.sourceStartMs * 1000,
                (seg.sourceStartMs + seg.lengthMs) * 1000,
            )
            if (music == null) {
                video
            } else {
                val s = videoSpeed
                // Which repetition this piece belongs to — by its midpoint:
                // cuts within 50ms of a clip edge are skipped (buildSegments),
                // so a piece can straddle a boundary by a few ms.
                val midOut = ((seg.globalStartMs + seg.lengthMs / 2) / s).toLong()
                val rep = repetitions.firstOrNull { (start, len) -> midOut >= start && midOut < start + len }
                val songMs = musicPreviewDurationMs
                val audio: MediaSource = if (previewMusic != null && rep != null && songMs > 0) {
                    val repStartSrc = (rep.first * s).toLong()
                    // Preview-file position = musicPath position × videoSpeed (see musicPreviewPath).
                    val fromMs = ((musicSourceStartMs * s).toLong() + seg.globalStartMs - repStartSrc)
                        .coerceIn(0L, (songMs - 1).coerceAtLeast(0L))
                    ClippingMediaSource(
                        factory.createMediaSource(MediaItem.fromUri(Uri.fromFile(File(previewMusic)))),
                        fromMs * 1000,
                        minOf(fromMs + seg.lengthMs, songMs) * 1000,
                    )
                } else {
                    SilenceMediaSource(seg.lengthMs * 1000)
                }
                MergingMediaSource(
                    /* adjustPeriodTimeOffsets = */ true,
                    /* clipDurations = */ true,
                    FilteringMediaSource(video, C.TRACK_TYPE_VIDEO),
                    audio,
                )
            }
        }
        DebugLog.log(context, "rebuildAndPrepare: ${sources.size} segments startGlobalMs=$startGlobalMs")
        player.stop()
        applyPreviewFilter()
        player.setMediaSources(sources)
        applyPreviewVolume()
        // With music attached the preview carries only the (pre-timed)
        // music, which must keep its pitch; without music, lower the pitch
        // with the speed like the export's slow motion does.
        player.playbackParameters = PlaybackParameters(videoSpeed, if (music != null) 1f else videoSpeed)
        player.prepare()
        seekToGlobal(startGlobalMs)
        player.playWhenReady = playWhenReady
        DebugLog.log(context, "rebuildAndPrepare: prepared, playWhenReady=$playWhenReady")
    }

    /**
     * The EXPORT composition — Transformer genuinely mixes clip audio with
     * music here. [reducedSize] is the automatic second attempt after an
     * encoder failure: output capped at 720p on the short side, which a
     * resource-starved hardware encoder is far more likely to accept.
     */
    private fun buildComposition(reducedSize: Boolean = false): Composition {
        val targetSize = if (clips.size > 1) exportFrameSize() else null
        val items = clips.mapIndexed { i, clip ->
            val mediaItem = MediaItem.Builder()
                .setUri(Uri.fromFile(File(clip.path)))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clip.trimStartMs)
                        .setEndPositionMs(clip.trimEndMs)
                        .build(),
                )
                .build()
            val videoEffects = mutableListOf<Effect>()
            if (rotationDegrees != 0) {
                videoEffects += ScaleAndRotateTransformation.Builder().setRotationDegrees(rotationDegrees.toFloat()).build()
            }
            // Clips can differ in size/orientation (front vs back camera);
            // normalize every clip to the first one's frame so the
            // encoder sees one resolution. Only needed with 2+ clips.
            if (targetSize != null) {
                videoEffects += Presentation.createForWidthAndHeight(
                    targetSize.first,
                    targetSize.second,
                    Presentation.LAYOUT_SCALE_TO_FIT,
                )
            }
            // The look effect goes BEFORE the transitions, matching the
            // preview (where the filter is applied inside the player and the
            // transition is a Compose transform of the result).
            if (videoFilter != VideoFilter.NONE) videoEffects += FilterEffect(videoFilter)
            if (reducedSize) videoEffects += Presentation.createForShortSide(720)
            // Transition timing is OUTPUT time: with setSpeed, Transformer
            // re-times samples at the source (SpeedChangingMediaSource), so
            // effects already see sped-up/slowed-down timestamps.
            videoEffects += clipTransitionEffects(
                entry = transitions.getOrNull(i - 1),
                exit = transitions.getOrNull(i),
                keptMs = (clip.keptDurationMs / videoSpeed).toLong(),
            )
            EditedMediaItem.Builder(mediaItem)
                .setDurationUs(clip.sourceDurationMs * 1000)
                .apply { if (videoSpeed != 1f) setSpeed(ConstantSpeedProvider(videoSpeed)) }
                .apply {
                    if (videoEffects.isNotEmpty()) {
                        setEffects(Effects(ImmutableList.of<AudioProcessor>(), ImmutableList.copyOf(videoEffects)))
                    }
                }
                .build()
        }
        val hasAudio = !isMuted && clips.all { sourceHasAudioTrack(it.path) }
        val videoSequence = if (hasAudio) {
            EditedMediaItemSequence.withAudioAndVideoFrom(items)
        } else {
            EditedMediaItemSequence.withVideoFrom(items)
        }

        val music = musicPath
        if (music == null || musicPlayDurationMs <= 0) {
            return Composition.Builder(ImmutableList.of(videoSequence)).withTextOverlay().build()
        }
        val musicUri = Uri.fromFile(File(music))
        val songDurationUs = probeDurationUs(context, musicUri)
        // One item per play of the selected part (just one unless looping),
        // back to back. The fade-in belongs to the first, the fade-out to
        // the last — a loop fades in once and out once.
        val repetitions = musicRepetitions()
        val musicItems = repetitions.mapIndexed { k, (_, len) ->
            val fadeIn = if (k == 0) musicFadeInMs else 0L
            val fadeOut = if (k == repetitions.lastIndex) musicFadeOutMs else 0L
            EditedMediaItem.Builder(
                MediaItem.Builder()
                    .setUri(musicUri)
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(musicSourceStartMs)
                            .setEndPositionMs(musicSourceStartMs + len)
                            .build(),
                    )
                    .build(),
            )
                .apply { songDurationUs?.let { setDurationUs(it) } }
                .apply {
                    if (fadeIn > 0 || fadeOut > 0) {
                        setEffects(
                            Effects(
                                ImmutableList.of<AudioProcessor>(MusicFadeAudioProcessor(fadeIn, fadeOut, len)),
                                ImmutableList.of(),
                            ),
                        )
                    }
                }
                .build()
        }
        val musicSequence = EditedMediaItemSequence.Builder(ImmutableSet.of(C.TRACK_TYPE_AUDIO))
            .apply { if (musicStartOffsetMs > 0) addGap(musicStartOffsetMs * 1000) }
            .addItems(musicItems)
            .build()
        return Composition.Builder(ImmutableList.of(videoSequence, musicSequence)).withTextOverlay().build()
    }

    /**
     * Captions go in as ONE composition-level overlay (over every clip, not
     * moved by per-clip transitions; the composition effects see the final,
     * speed-adjusted OUTPUT timeline — the same time base as [TextLayer]).
     */
    private fun Composition.Builder.withTextOverlay(): Composition.Builder {
        val visible = textLayers.filter { it.text.isNotBlank() && it.endMs > it.startMs }
        val visibleStickers = stickerLayers.filter { it.endMs > it.startMs && stickers.byId(it.stickerId) != null }
        if (visible.isEmpty() && visibleStickers.isEmpty()) return this
        val overlay = OverlayEffect(
            ImmutableList.of<TextureOverlay>(TextOverlayEffectBitmap(visible, fonts, visibleStickers, stickers)),
        )
        return setEffects(Effects(ImmutableList.of<AudioProcessor>(), ImmutableList.of<Effect>(overlay)))
    }

    private val displaySizeCache = mutableMapOf<String, Pair<Int, Int>?>()

    /**
     * Width / height of the exported frame (first clip's displayed size,
     * then the user's rotation) — the rectangle captions are laid out in,
     * so the preview overlay can be drawn over exactly that frame.
     */
    val outputAspect: Float
        get() {
            val path = clips.firstOrNull()?.path ?: return 9f / 16f
            val size = displaySizeCache.getOrPut(path) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
                    val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
                    val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                    if (w == null || h == null || w <= 0 || h <= 0) null else if (rot % 180 == 90) h to w else w to h
                } catch (e: Exception) {
                    null
                } finally {
                    retriever.release()
                }
            } ?: return 9f / 16f
            val (w, h) = if (rotationDegrees % 180 == 90) size.second to size.first else size
            return w.toFloat() / h
        }

    /** First clip's displayed size (container rotation applied, then the user's own rotation), even-numbered for the encoder. */
    private fun exportFrameSize(): Pair<Int, Int>? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(clips.first().path)
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: return null
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: return null
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            var (dw, dh) = if (rot % 180 == 90) h to w else w to h
            if (rotationDegrees % 180 == 90) dw = dh.also { dh = dw }
            (dw / 2 * 2) to (dh / 2 * 2)
        } catch (e: Exception) {
            Log.w("EditorViewModel", "exportFrameSize probe failed", e)
            null
        } finally {
            retriever.release()
        }
    }

    fun export(outputPath: String, onComplete: (String?, String?) -> Unit) {
        isExporting = true
        exportProgress = 0f
        exportError = null
        // Release the preview's decoders (pause() keeps them allocated) so
        // Transformer's decoders + encoder fit in the codec budget.
        val resumeAt = globalPositionMs()
        player.stop()
        DebugLog.log(context, "export: preview stopped, starting transformer clips=${clips.size}")
        startTransformer(outputPath, reducedSize = false, resumeAt = resumeAt, onComplete = onComplete)
    }

    private fun startTransformer(outputPath: String, reducedSize: Boolean, resumeAt: Long, onComplete: (String?, String?) -> Unit) {
        File(outputPath).delete()
        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    DebugLog.log(context, "export: completed reducedSize=$reducedSize")
                    isExporting = false
                    onComplete(outputPath, null)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    DebugLog.log(context, "export: error reducedSize=$reducedSize ${exportException.errorCodeName}")
                    Log.e("EditorViewModel", "Export failed (reducedSize=$reducedSize)", exportException)
                    if (!reducedSize) {
                        // One automatic retry at 720p before bothering the user.
                        exportProgress = 0f
                        startTransformer(outputPath, reducedSize = true, resumeAt = resumeAt, onComplete = onComplete)
                        return
                    }
                    isExporting = false
                    val message = "${exportException.errorCodeName}: ${exportException.message ?: "Export failed"}"
                    exportError = message
                    // Staying on this screen — bring the preview back.
                    rebuildAndPrepare(startGlobalMs = resumeAt, playWhenReady = false)
                    onComplete(null, message)
                }
            })
            .build()

        transformer.start(buildComposition(reducedSize), outputPath)

        // Transformer's progress is polled, not pushed.
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val progressHolder = ProgressHolder()
        val poll = object : Runnable {
            override fun run() {
                if (!isExporting) return
                if (transformer.getProgress(progressHolder) != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    exportProgress = progressHolder.progress / 100f
                }
                handler.postDelayed(this, 200)
            }
        }
        handler.postDelayed(poll, 200)
    }

    override fun onCleared() {
        editorScope.cancel()
        player.release()
    }

    companion object {
        private const val PrefPreviewEffects = "preview_effects_state"

        /** The state for a brand-new session from a single captured clip — capped at the 30s total. */
        fun initialStateFor(context: Context, path: String): EditorSessionState {
            val sourceMs = probeDurationUs(context, Uri.fromFile(File(path)))?.div(1000) ?: 0L
            return EditorSessionState(
                clips = listOf(EditorClip(path, sourceMs, 0L, minOf(sourceMs, MaxTotalDurationMs))),
                transitions = emptyList(),
                musicPath = null,
                musicOriginalPath = null,
                musicSpeed = 1f,
                musicFadeInMs = 0L,
                musicFadeOutMs = 0L,
                musicLoop = false,
                musicStartOffsetMs = 0L,
                musicSourceStartMs = 0L,
                musicPlayDurationMs = 0L,
                rotationDegrees = 0,
                isMuted = false,
                videoSpeed = 1f,
                videoFilter = VideoFilter.NONE,
            )
        }

        private fun normalizeTransitions(list: List<TransitionSpec>, clipCount: Int): List<TransitionSpec> {
            val wanted = (clipCount - 1).coerceAtLeast(0)
            return List(wanted) { i -> list.getOrElse(i) { TransitionSpec() } }
        }

        private val audioTrackCache = mutableMapOf<String, Boolean>()

        private fun sourceHasAudioTrack(path: String): Boolean = audioTrackCache.getOrPut(path) {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(path)
                (0 until extractor.trackCount).any { i ->
                    extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                }
            } catch (e: Exception) {
                Log.w("EditorViewModel", "sourceHasAudioTrack probe failed, assuming no audio track", e)
                false
            } finally {
                extractor.release()
            }
        }

        /**
         * Probes [uri]'s duration synchronously. Transformer requires
         * every EditedMediaItem's duration up front (checkArgument in
         * CompositionPlayer/Transformer sources) — see the checkpoint
         * history.
         */
        fun probeDurationUs(context: Context, uri: Uri): Long? {
            val retriever = MediaMetadataRetriever()
            return try {
                retriever.setDataSource(context, uri)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?.takeIf { it > 0 }
                    ?.times(1000)
            } catch (e: Exception) {
                Log.w("EditorViewModel", "probeDurationUs failed for $uri", e)
                null
            } finally {
                retriever.release()
            }
        }
    }
}
