package com.adgag.adgag.editor

import org.json.JSONArray
import org.json.JSONObject

/** Hard cap on the whole Ad (all clips' kept portions together) — mirrors Dart's `VideoConstraints.max` and the `ads.duration_range` CHECK. */
const val MaxTotalDurationMs = 30_000L

/** Shortest clip worth adding — mirrors Dart's `VideoConstraints.min`; the "+" button hides once less than this remains. */
const val MinClipDurationMs = 1_500L

/** Transition length bounds and default (user-adjustable per boundary; 500ms read as "too fast" on a device). */
const val DefaultTransitionDurationMs = 800L
const val MinTransitionDurationMs = 200L
const val MaxTransitionDurationMs = 2_000L

/** Whole-video speed choices (slow motion down to 0.25x). The 30s cap applies to the OUTPUT, so slower speeds need shorter clips. */
val VideoSpeedOptions = listOf(0.25f, 0.5f, 0.75f, 1f)

/** Music speed choices (pitch kept). */
val MusicSpeedOptions = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)

const val MaxMusicFadeMs = 5_000L

/**
 * One recorded clip on the timeline. [trimStartMs]/[trimEndMs] are in
 * this clip's own SOURCE time (0 = start of its file); the kept part is
 * what plays, back to back with the other clips.
 */
data class EditorClip(
    val path: String,
    val sourceDurationMs: Long,
    val trimStartMs: Long,
    val trimEndMs: Long,
) {
    val keptDurationMs: Long get() = (trimEndMs - trimStartMs).coerceAtLeast(0L)
}

/**
 * What happens at the boundary between two clips. None of these overlap
 * the two clips (no dual-decoder compositing): each is an effect on the
 * END of the outgoing clip, the START of the incoming one, or both —
 * which is what lets the plain-ExoPlayer preview show it faithfully (a
 * Compose transform/veil on the surface) and the export render it as
 * per-clip Media3 effects (TransitionEffects.kt).
 */
enum class ClipTransition(val label: String) {
    NONE("Cut"),
    FADE("Fade in"),
    FADE_OUT("Fade out"),
    DIP_TO_BLACK("Dip to black"),
    SLIDE_FROM_RIGHT("Slide ←"),
    SLIDE_FROM_LEFT("Slide →"),
    SLIDE_FROM_BOTTOM("Slide ↑"),
    SLIDE_FROM_TOP("Slide ↓"),
    ZOOM_IN("Zoom in"),
    ZOOM_OUT("Zoom out"),
    SPIN("Spin"),
}

/** One boundary's transition: which effect, and how long it runs. */
data class TransitionSpec(
    val type: ClipTransition = ClipTransition.NONE,
    val durationMs: Long = DefaultTransitionDurationMs,
)

/**
 * Everything needed to rebuild the editor after it's closed to record
 * another clip (the camera is Flutter's own, so the native Activity has
 * to finish and be relaunched) — handed to Dart as an opaque JSON
 * string and passed straight back, never parsed on the Dart side.
 */
data class EditorSessionState(
    val clips: List<EditorClip>,
    val transitions: List<TransitionSpec>,
    /** The song actually used — [musicOriginalPath] re-timed to [musicSpeed] (the same file when 1x). */
    val musicPath: String?,
    /** Private copy of the picked song, untouched — re-timing always starts from here. */
    val musicOriginalPath: String?,
    val musicSpeed: Float,
    val musicFadeInMs: Long,
    val musicFadeOutMs: Long,
    /** GLOBAL placement of the music, in OUTPUT time (after [videoSpeed]). */
    val musicStartOffsetMs: Long,
    /** Where in the SONG the used part begins (the music row's left trim). */
    val musicSourceStartMs: Long,
    val musicPlayDurationMs: Long,
    val rotationDegrees: Int,
    val isMuted: Boolean,
    val videoSpeed: Float,
) {
    fun toJson(): String = JSONObject().apply {
        put("clips", JSONArray().apply {
            clips.forEach { c ->
                put(JSONObject().apply {
                    put("path", c.path)
                    put("sourceDurationMs", c.sourceDurationMs)
                    put("trimStartMs", c.trimStartMs)
                    put("trimEndMs", c.trimEndMs)
                })
            }
        })
        put("transitions", JSONArray().apply {
            transitions.forEach { t ->
                put(JSONObject().apply {
                    put("type", t.type.name)
                    put("durationMs", t.durationMs)
                })
            }
        })
        if (musicPath != null) put("musicPath", musicPath)
        if (musicOriginalPath != null) put("musicOriginalPath", musicOriginalPath)
        put("musicSpeed", musicSpeed.toDouble())
        put("musicFadeInMs", musicFadeInMs)
        put("musicFadeOutMs", musicFadeOutMs)
        put("videoSpeed", videoSpeed.toDouble())
        put("musicStartOffsetMs", musicStartOffsetMs)
        put("musicSourceStartMs", musicSourceStartMs)
        put("musicPlayDurationMs", musicPlayDurationMs)
        put("rotationDegrees", rotationDegrees)
        put("isMuted", isMuted)
    }.toString()

    companion object {
        fun fromJson(json: String): EditorSessionState {
            val o = JSONObject(json)
            val clipsJson = o.getJSONArray("clips")
            val clips = (0 until clipsJson.length()).map { i ->
                val c = clipsJson.getJSONObject(i)
                EditorClip(
                    path = c.getString("path"),
                    sourceDurationMs = c.getLong("sourceDurationMs"),
                    trimStartMs = c.getLong("trimStartMs"),
                    trimEndMs = c.getLong("trimEndMs"),
                )
            }
            val tJson = o.optJSONArray("transitions") ?: JSONArray()
            val transitions = (0 until tJson.length()).map { i ->
                val entry = tJson.opt(i)
                // Older sessions stored just the type name.
                val (name, duration) = if (entry is JSONObject) {
                    entry.optString("type") to entry.optLong("durationMs", DefaultTransitionDurationMs)
                } else {
                    entry.toString() to DefaultTransitionDurationMs
                }
                TransitionSpec(
                    type = runCatching { ClipTransition.valueOf(name) }.getOrDefault(ClipTransition.NONE),
                    durationMs = duration.coerceIn(MinTransitionDurationMs, MaxTransitionDurationMs),
                )
            }
            val musicPath = if (o.has("musicPath")) o.getString("musicPath") else null
            return EditorSessionState(
                clips = clips,
                transitions = transitions,
                musicPath = musicPath,
                musicOriginalPath = if (o.has("musicOriginalPath")) o.getString("musicOriginalPath") else musicPath,
                musicSpeed = o.optDouble("musicSpeed", 1.0).toFloat(),
                musicFadeInMs = o.optLong("musicFadeInMs", 0L),
                musicFadeOutMs = o.optLong("musicFadeOutMs", 0L),
                musicStartOffsetMs = o.optLong("musicStartOffsetMs", 0L),
                musicSourceStartMs = o.optLong("musicSourceStartMs", 0L),
                musicPlayDurationMs = o.optLong("musicPlayDurationMs", 0L),
                rotationDegrees = o.optInt("rotationDegrees", 0),
                isMuted = o.optBoolean("isMuted", false),
                videoSpeed = o.optDouble("videoSpeed", 1.0).toFloat(),
            )
        }
    }
}
