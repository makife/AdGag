package com.adgag.adgag.editor

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * "Magnet" rules for moving/rotating captions and stickers on the preview
 * (user request: getting a twisted caption straight again was hard; wanted
 * snapping to the video's centre and to other captions, like other
 * editors). Pure math — the gesture code feeds it the RAW value the fingers
 * produced (accumulated over the gesture) and applies what comes back, so
 * pulling further than the threshold breaks free again. Mirrored in
 * ios/Runner/Editor/EditorSnapping.swift.
 */
object Snapping {
    /** Degrees within which a rotation sticks to a multiple of 90°. */
    const val ANGLE_THRESHOLD_DEG = 7f

    /** Distance (dp) within which a centre sticks to a guide line. */
    const val POSITION_THRESHOLD_DP = 10f

    /** Caption size (fraction of frame height): same range for pinch and the Size slider. */
    const val MIN_SIZE_FRAC = 0.02f
    const val MAX_SIZE_FRAC = 0.4f

    /** [deg] snapped to the nearest multiple of 90° when close enough; [snapped] tells whether it did. */
    data class Angle(val deg: Float, val snapped: Boolean)

    fun angle(rawDeg: Float, threshold: Float = ANGLE_THRESHOLD_DEG): Angle {
        val nearest = (rawDeg / 90f).roundToInt() * 90f
        return if (abs(rawDeg - nearest) <= threshold) Angle(nearest, true) else Angle(rawDeg, false)
    }

    /** [value] snapped to the closest of [targets] within [threshold]; [guide] = the target used, or null. */
    data class Axis(val value: Float, val guide: Float?)

    fun axis(raw: Float, targets: List<Float>, threshold: Float): Axis {
        var best: Float? = null
        var bestDist = threshold
        for (t in targets) {
            val d = abs(raw - t)
            if (d <= bestDist) {
                bestDist = d
                best = t
            }
        }
        return Axis(best ?: raw, best)
    }
}
