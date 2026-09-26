package com.adgag.adgag.editor

import android.graphics.Matrix
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.RgbMatrix

/**
 * The single definition of what every [ClipTransition] looks like at a
 * given point of its run — used by BOTH the live preview (a Compose
 * graphicsLayer/overlay on the player surface, EditorScreen) and the
 * export (per-clip Media3 effects, [transitionEffectsFor]), so what the
 * user previews is what gets rendered.
 */
object TransitionMath {

    /** Where the incoming clip is, [progress] 0 -> 1 across the transition. Translations are fractions of the frame (x right, y DOWN, screen convention). */
    data class Pose(
        val translateX: Float = 0f,
        val translateY: Float = 0f,
        val scale: Float = 1f,
        val rotationDegrees: Float = 0f,
        /** 0 = black, 1 = normal. */
        val brightness: Float = 1f,
    )

    val Identity = Pose()

    /** Ease-out cubic of [localMs] (time since the clip started) — null once the transition is over. */
    fun progress(localMs: Long): Float? {
        if (localMs < 0 || localMs >= TransitionDurationMs) return null
        val t = localMs.toFloat() / TransitionDurationMs
        val inv = 1f - t
        return 1f - inv * inv * inv
    }

    fun pose(transition: ClipTransition, p: Float): Pose {
        val r = 1f - p
        return when (transition) {
            ClipTransition.NONE -> Identity
            ClipTransition.FADE -> Pose(brightness = p)
            ClipTransition.SLIDE_FROM_RIGHT -> Pose(translateX = r)
            ClipTransition.SLIDE_FROM_LEFT -> Pose(translateX = -r)
            ClipTransition.SLIDE_FROM_BOTTOM -> Pose(translateY = r)
            ClipTransition.SLIDE_FROM_TOP -> Pose(translateY = -r)
            ClipTransition.ZOOM_IN -> Pose(scale = 0.5f + 0.5f * p)
            ClipTransition.ZOOM_OUT -> Pose(scale = 1.6f - 0.6f * p)
            ClipTransition.SPIN -> Pose(scale = 0.3f + 0.7f * p, rotationDegrees = -180f * r)
        }
    }
}

/**
 * Export-side effects for a clip that enters with [transition] — empty
 * for [ClipTransition.NONE].
 *
 * Time base: rather than depending on how Transformer offsets frame
 * timestamps for the Nth item of a sequence (an internal detail), each
 * effect takes the FIRST timestamp it is asked about as the clip's own
 * zero. These effect instances are built fresh per export and per clip,
 * frames reach effects in presentation order, and `GlEffect.isNoOp`
 * defaults to false (checked in the media3-effect 1.11.0 sources), so
 * no configuration-time call can poison that first timestamp.
 */
@UnstableApi
fun transitionEffectsFor(transition: ClipTransition): List<Effect> {
    if (transition == ClipTransition.NONE) return emptyList()
    val effects = mutableListOf<Effect>()
    if (transition == ClipTransition.FADE) {
        effects += FadeInRgbMatrix()
    } else {
        effects += EntranceMatrixTransformation(transition)
    }
    return effects
}

/** Shared "first timestamp seen = clip start" bookkeeping. */
private class LocalClock {
    private var firstUs = C.TIME_UNSET
    fun localMs(presentationTimeUs: Long): Long {
        if (firstUs == C.TIME_UNSET) firstUs = presentationTimeUs
        return (presentationTimeUs - firstUs) / 1000
    }
}

@UnstableApi
private class FadeInRgbMatrix : RgbMatrix {
    private val clock = LocalClock()

    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        val p = TransitionMath.progress(clock.localMs(presentationTimeUs)) ?: 1f
        // Column-major 4x4, scaling only R/G/B — alpha untouched.
        return floatArrayOf(
            p, 0f, 0f, 0f,
            0f, p, 0f, 0f,
            0f, 0f, p, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}

/**
 * Slide/zoom/spin in normalized device coordinates (x, y in -1..1, y UP).
 * The frame's own aspect ratio is factored in around the rotation so a
 * spinning non-square frame doesn't shear; frame SIZE is unchanged
 * ([configure] returns the input size — the default, kept explicit here
 * because we also need the dimensions).
 */
@UnstableApi
private class EntranceMatrixTransformation(private val transition: ClipTransition) : MatrixTransformation {
    private val clock = LocalClock()
    private var aspect = 1f
    private val matrix = Matrix()

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        if (inputHeight > 0) aspect = inputWidth.toFloat() / inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun getMatrix(presentationTimeUs: Long): Matrix {
        val p = TransitionMath.progress(clock.localMs(presentationTimeUs))
        matrix.reset()
        if (p == null) return matrix
        val pose = TransitionMath.pose(transition, p)
        matrix.postScale(pose.scale, pose.scale)
        if (pose.rotationDegrees != 0f) {
            matrix.postScale(aspect, 1f)
            matrix.postRotate(pose.rotationDegrees)
            matrix.postScale(1f / aspect, 1f)
        }
        // NDC spans 2 units per frame width/height; y is up in NDC but
        // Pose uses screen convention (y down).
        matrix.postTranslate(pose.translateX * 2f, -pose.translateY * 2f)
        return matrix
    }
}
