package com.adgag.adgag.editor

import org.json.JSONArray
import org.json.JSONObject

/** Hard cap on the whole Ad (all clips' kept portions together) — mirrors Dart's `VideoConstraints.max` and the `ads.duration_range` CHECK. */
const val MaxTotalDurationMs = 30_000L

/** Shortest clip worth adding — mirrors Dart's `VideoConstraints.min`; the "+" button hides once less than this remains. */
const val MinClipDurationMs = 1_500L

/** How long every clip-entry transition runs, in both the live preview and the export. */
const val TransitionDurationMs = 500L

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
 * How a clip ENTERS, after the previous one — the effect sits between
 * two thumbnails on the timeline. Every one of these is an entrance
 * effect on the incoming clip (no overlap with the outgoing clip),
 * which is what lets the plain-ExoPlayer preview show it faithfully
 * (a Compose transform/overlay on the surface) and the export render it
 * as a per-item Media3 effect (see TransitionEffects.kt) — no dual-
 * decoder compositing needed on either side.
 */
enum class ClipTransition(val label: String) {
    NONE("Cut"),
    FADE("Fade in"),
    SLIDE_FROM_RIGHT("Slide ←"),
    SLIDE_FROM_LEFT("Slide →"),
    SLIDE_FROM_BOTTOM("Slide ↑"),
    SLIDE_FROM_TOP("Slide ↓"),
    ZOOM_IN("Zoom in"),
    ZOOM_OUT("Zoom out"),
    SPIN("Spin"),
}

/**
 * Everything needed to rebuild the editor after it's closed to record
 * another clip (the camera is Flutter's own, so the native Activity has
 * to finish and be relaunched) — handed to Dart as an opaque JSON
 * string and passed straight back, never parsed on the Dart side.
 */
data class EditorSessionState(
    val clips: List<EditorClip>,
    val transitions: List<ClipTransition>,
    val musicPath: String?,
    val musicStartOffsetMs: Long,
    val musicPlayDurationMs: Long,
    val rotationDegrees: Int,
    val isMuted: Boolean,
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
        put("transitions", JSONArray().apply { transitions.forEach { put(it.name) } })
        if (musicPath != null) put("musicPath", musicPath)
        put("musicStartOffsetMs", musicStartOffsetMs)
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
                runCatching { ClipTransition.valueOf(tJson.getString(i)) }.getOrDefault(ClipTransition.NONE)
            }
            return EditorSessionState(
                clips = clips,
                transitions = transitions,
                musicPath = if (o.has("musicPath")) o.getString("musicPath") else null,
                musicStartOffsetMs = o.optLong("musicStartOffsetMs", 0L),
                musicPlayDurationMs = o.optLong("musicPlayDurationMs", 0L),
                rotationDegrees = o.optInt("rotationDegrees", 0),
                isMuted = o.optBoolean("isMuted", false),
            )
        }
    }
}
