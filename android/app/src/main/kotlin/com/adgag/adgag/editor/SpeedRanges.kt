package com.adgag.adgag.editor

import androidx.media3.common.C
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.roundToLong

/** Slow-motion choices for a speed range (the rest of the Ad plays at 1x). */
val SpeedRangeOptions = listOf(0.25f, 0.5f, 0.75f)

/** Shortest speed range kept after an edit (shorter ones are dropped). */
const val MinSpeedRangeMs = 300L

/** Length of a newly added range (before the user drags its edges). */
const val DefaultSpeedRangeMs = 2_000L

/**
 * A stretch of the Ad played at [speed] — slow motion on just a part of
 * the video, not the whole thing. [startMs]/[endMs] are GLOBAL SOURCE time
 * (the clip strip's time base: 0 = first kept frame of the first clip), so
 * a range stays on the same content while the rest of the timeline is
 * edited — [EditorViewModel] remaps ranges whenever a trim or a removed
 * clip moves content around. Ranges never overlap.
 */
data class SpeedRange(
    val startMs: Long,
    val endMs: Long,
    val speed: Float,
    val id: String = UUID.randomUUID().toString(),
) {
    val lengthMs: Long get() = (endMs - startMs).coerceAtLeast(0L)

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("startMs", startMs)
        put("endMs", endMs)
        put("speed", speed.toDouble())
    }

    companion object {
        fun listToJson(list: List<SpeedRange>): JSONArray = JSONArray().apply { list.forEach { put(it.toJson()) } }

        fun listFromJson(array: JSONArray?): List<SpeedRange> {
            if (array == null) return emptyList()
            return (0 until array.length()).mapNotNull { i ->
                val o = array.optJSONObject(i) ?: return@mapNotNull null
                SpeedRange(
                    startMs = o.optLong("startMs"),
                    endMs = o.optLong("endMs"),
                    speed = o.optDouble("speed", 1.0).toFloat(),
                    id = o.optString("id").ifEmpty { UUID.randomUUID().toString() },
                )
            }.filter { it.lengthMs > 0 && it.speed > 0f }
        }
    }
}

/**
 * The time map between SOURCE time (what's recorded — the clip strip,
 * trims, the preview playlist) and OUTPUT time (what the finished Ad
 * plays — the 30s cap, captions, stickers, music, transitions). Piecewise
 * linear: 1x outside every range, `1 / speed` slower inside one. The only
 * place that conversion is defined — never divide by a speed anywhere else.
 */
class SpeedMap(ranges: List<SpeedRange>) {
    private val ranges = ranges.filter { it.lengthMs > 0 }.sortedBy { it.startMs }

    val isIdentity: Boolean get() = ranges.isEmpty()

    fun speedAt(sourceMs: Long): Float = ranges.firstOrNull { sourceMs >= it.startMs && sourceMs < it.endMs }?.speed ?: 1f

    fun toOutput(sourceMs: Long): Long {
        var out = 0.0
        var cursor = 0L
        for (r in ranges) {
            if (sourceMs <= r.startMs) break
            out += r.startMs - cursor
            val end = minOf(sourceMs, r.endMs)
            out += (end - r.startMs) / r.speed.toDouble()
            cursor = r.endMs
            if (sourceMs <= r.endMs) return out.roundToLong()
        }
        return (out + (sourceMs - cursor).coerceAtLeast(0L)).roundToLong()
    }

    fun toSource(outputMs: Long): Long {
        var out = 0.0
        var cursor = 0L
        for (r in ranges) {
            val plainLen = (r.startMs - cursor).toDouble()
            if (outputMs <= out + plainLen) return (cursor + (outputMs - out)).roundToLong()
            out += plainLen
            val slowLen = r.lengthMs / r.speed.toDouble()
            if (outputMs <= out + slowLen) return (r.startMs + (outputMs - out) * r.speed).roundToLong()
            out += slowLen
            cursor = r.endMs
        }
        return (cursor + (outputMs - out)).roundToLong()
    }

    /** Source times where the speed changes, strictly inside (from, to). */
    fun boundariesIn(fromMs: Long, toMs: Long): List<Long> =
        ranges.flatMap { listOf(it.startMs, it.endMs) }.filter { it > fromMs && it < toMs }.distinct().sorted()

    /** The next speed change strictly after [sourceMs], or null. */
    fun nextBoundaryAfter(sourceMs: Long): Long? =
        ranges.asSequence().flatMap { sequenceOf(it.startMs, it.endMs) }.filter { it > sourceMs }.minOrNull()

    /** Lowest speed anywhere in [fromMs, toMs) — 1 if no range overlaps. */
    fun minSpeedIn(fromMs: Long, toMs: Long): Float =
        ranges.filter { it.startMs < toMs && it.endMs > fromMs }.minOfOrNull { it.speed }?.coerceAtMost(1f) ?: 1f
}

/**
 * EXPORT speed for one clip: the part of [map] between that clip's GLOBAL
 * [clipStartMs] and [clipEndMs]. Media3 calls this with time measured from
 * the start of the clip's KEPT part (verified in the media3-transformer
 * 1.11.0 sources: SpeedChangingMediaSource subtracts the clipping start
 * before asking the provider, and SpeedChangingAudioProcessor counts
 * samples from the item's own start), so a clip-local time t is GLOBAL
 * clipStart + t. Video timestamps and audio (tape-style, pitch drops) are
 * both re-timed from this one provider.
 */
@UnstableApi
class RangeSpeedProvider(
    private val map: SpeedMap,
    private val clipStartMs: Long,
    private val clipEndMs: Long,
) : SpeedProvider {
    override fun getSpeed(timeUs: Long): Float = map.speedAt(clipStartMs + timeUs.coerceAtLeast(0L) / 1000)

    override fun getNextSpeedChangeTimeUs(timeUs: Long): Long {
        val next = map.nextBoundaryAfter(clipStartMs + timeUs.coerceAtLeast(0L) / 1000) ?: return C.TIME_UNSET
        if (next >= clipEndMs) return C.TIME_UNSET
        // Strictly after timeUs, as the interface requires.
        return maxOf((next - clipStartMs) * 1000, timeUs + 1)
    }
}

/**
 * Moves every range edge through [map] (a content-preserving mapping of
 * old SOURCE positions to new ones, e.g. after a trim) and drops ranges
 * that became too short.
 */
fun List<SpeedRange>.remapped(totalMs: Long, map: (Long) -> Long): List<SpeedRange> =
    mapNotNull { r ->
        val s = map(r.startMs).coerceIn(0L, totalMs)
        val e = map(r.endMs).coerceIn(0L, totalMs)
        if (e - s < MinSpeedRangeMs) null else r.copy(startMs = s, endMs = e)
    }
