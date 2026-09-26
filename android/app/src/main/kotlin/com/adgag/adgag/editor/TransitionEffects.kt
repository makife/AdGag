package com.adgag.adgag.editor

import android.graphics.Matrix
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.RgbMatrix

/**
 * The single definition of what the clip transitions look like — used by
 * the live preview (Compose graphicsLayer/veil, EditorScreen), the
 * picker's animated thumbnails, and the export (per-clip Media3 effects,
 * [clipTransitionEffects]), so what the user previews is what gets
 * rendered.
 */
object TransitionMath {

    /** How a clip is drawn at one instant. Translations are fractions of the frame (x right, y DOWN, screen convention). */
    data class Pose(
        val translateX: Float = 0f,
        val translateY: Float = 0f,
        val scale: Float = 1f,
        val rotationDegrees: Float = 0f,
        /** 0 = black, 1 = normal. */
        val brightness: Float = 1f,
    )

    val Identity = Pose()

    private fun easeOut(t: Float): Float {
        val inv = 1f - t.coerceIn(0f, 1f)
        return 1f - inv * inv * inv
    }

    /** The entrance part of [type] at progress [p] (0 -> 1). */
    private fun entrancePose(type: ClipTransition, p: Float): Pose {
        val r = 1f - p
        return when (type) {
            ClipTransition.NONE, ClipTransition.FADE_OUT -> Identity
            ClipTransition.FADE, ClipTransition.DIP_TO_BLACK -> Pose(brightness = p)
            ClipTransition.SLIDE_FROM_RIGHT -> Pose(translateX = r)
            ClipTransition.SLIDE_FROM_LEFT -> Pose(translateX = -r)
            ClipTransition.SLIDE_FROM_BOTTOM -> Pose(translateY = r)
            ClipTransition.SLIDE_FROM_TOP -> Pose(translateY = -r)
            ClipTransition.ZOOM_IN -> Pose(scale = 0.5f + 0.5f * p)
            ClipTransition.ZOOM_OUT -> Pose(scale = 1.6f - 0.6f * p)
            ClipTransition.SPIN -> Pose(scale = 0.3f + 0.7f * p, rotationDegrees = -180f * r)
        }
    }

    /** How long the ENTRANCE half of [spec] runs on the incoming clip (0 = none). */
    private fun entranceMs(spec: TransitionSpec): Long = when (spec.type) {
        ClipTransition.NONE, ClipTransition.FADE_OUT -> 0L
        ClipTransition.DIP_TO_BLACK -> spec.durationMs / 2
        else -> spec.durationMs
    }

    /** How long the EXIT (fade to black) half of [spec] runs on the outgoing clip (0 = none). */
    private fun exitMs(spec: TransitionSpec): Long = when (spec.type) {
        ClipTransition.FADE_OUT -> spec.durationMs
        ClipTransition.DIP_TO_BLACK -> spec.durationMs / 2
        else -> 0L
    }

    /**
     * A clip's pose at [localMs] into its kept part ([keptMs] long), given
     * the transition INTO it ([entry], null for the first clip) and OUT
     * of it ([exit], null for the last clip). Durations are capped by the
     * clip's own length.
     */
    fun clipPose(entry: TransitionSpec?, exit: TransitionSpec?, keptMs: Long, localMs: Long): Pose {
        var pose = Identity
        if (entry != null) {
            val d = minOf(entranceMs(entry), keptMs)
            if (d > 0 && localMs in 0 until d) {
                pose = entrancePose(entry.type, easeOut(localMs.toFloat() / d))
            }
        }
        if (exit != null) {
            val d = minOf(exitMs(exit), keptMs)
            val remaining = keptMs - localMs
            if (d > 0 && remaining < d) {
                val q = (remaining.toFloat() / d).coerceIn(0f, 1f)
                pose = pose.copy(brightness = pose.brightness * q)
            }
        }
        return pose
    }
}

/**
 * Export-side effects for one clip: a brightness RgbMatrix if its entry or
 * exit fades, and a MatrixTransformation if its entry moves — both
 * driven by [TransitionMath.clipPose], exactly like the preview.
 *
 * Time base: rather than depending on how Transformer offsets frame
 * timestamps for the Nth item of a sequence (an internal detail), each
 * effect takes the FIRST timestamp it is asked about as the clip's own
 * zero. These instances are built fresh per export and per clip, frames
 * reach effects in presentation order, and the matrix getters are only
 * called per frame from DefaultShaderProgram.drawFrame (checked in the
 * media3-effect 1.11.0 sources; GlEffect.isNoOp defaults to false).
 */
@UnstableApi
fun clipTransitionEffects(entry: TransitionSpec?, exit: TransitionSpec?, keptMs: Long): List<Effect> {
    val entryType = entry?.type ?: ClipTransition.NONE
    val exitType = exit?.type ?: ClipTransition.NONE
    val fades = entryType in setOf(ClipTransition.FADE, ClipTransition.DIP_TO_BLACK) ||
        exitType in setOf(ClipTransition.FADE_OUT, ClipTransition.DIP_TO_BLACK)
    val moves = entryType !in setOf(
        ClipTransition.NONE,
        ClipTransition.FADE,
        ClipTransition.FADE_OUT,
        ClipTransition.DIP_TO_BLACK,
    )
    val effects = mutableListOf<Effect>()
    if (moves) effects += PoseMatrixTransformation(entry, exit, keptMs)
    if (fades) effects += PoseBrightnessRgbMatrix(entry, exit, keptMs)
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
private class PoseBrightnessRgbMatrix(
    private val entry: TransitionSpec?,
    private val exit: TransitionSpec?,
    private val keptMs: Long,
) : RgbMatrix {
    private val clock = LocalClock()

    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        val b = TransitionMath.clipPose(entry, exit, keptMs, clock.localMs(presentationTimeUs)).brightness
        // Column-major 4x4, scaling only R/G/B — alpha untouched.
        return floatArrayOf(
            b, 0f, 0f, 0f,
            0f, b, 0f, 0f,
            0f, 0f, b, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}

/**
 * Slide/zoom/spin in normalized device coordinates (x, y in -1..1, y UP).
 * The frame's aspect ratio is factored in around the rotation so a
 * spinning non-square frame doesn't shear; frame SIZE is unchanged.
 */
@UnstableApi
private class PoseMatrixTransformation(
    private val entry: TransitionSpec?,
    private val exit: TransitionSpec?,
    private val keptMs: Long,
) : MatrixTransformation {
    private val clock = LocalClock()
    private var aspect = 1f
    private val matrix = Matrix()

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        if (inputHeight > 0) aspect = inputWidth.toFloat() / inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun getMatrix(presentationTimeUs: Long): Matrix {
        val pose = TransitionMath.clipPose(entry, exit, keptMs, clock.localMs(presentationTimeUs))
        matrix.reset()
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
