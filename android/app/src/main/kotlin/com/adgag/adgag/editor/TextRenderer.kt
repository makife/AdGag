package com.adgag.adgag.editor

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import androidx.media3.common.C
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Draws [TextLayer]s onto an Android Canvas — the ONE implementation used
 * by the live preview (Compose's native canvas) and the export
 * ([TextOverlayEffectBitmap], a full-frame Media3 overlay), so preview and
 * export match. All sizes derive from the frame height, all positions from
 * frame fractions, so any resolution works.
 *
 * Structure: layout (lines → glyphs with advances) → whole-block transform
 * (position, rotation, scale, entrance/loop motion) → per-line backgrounds
 * (Box/Pill/Marker) → per-glyph passes for the style (outline, glow…) with
 * per-letter motion (wave, jump, typewriter, rise, drop) → optional mirror.
 */
object TextRenderer {
    /** How long entrance animations take. */
    const val ENTRANCE_MS = 600L

    class Line(val glyphs: List<String>, val advances: FloatArray, val width: Float)

    class Layout(
        val lines: List<Line>,
        val sizePx: Float,
        val lineHeight: Float,
        val width: Float,
        val height: Float,
        val paint: Paint,
    )

    private data class Motion(
        var dx: Float = 0f,
        var dy: Float = 0f,
        var scale: Float = 1f,
        var rotation: Float = 0f,
        var alpha: Float = 1f,
    )

    // --- layout ---------------------------------------------------------------

    fun basePaint(layer: TextLayer, frameH: Float, fonts: TypefaceCache): Paint {
        val font = TextFonts.byId(layer.fontId)
        return Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = fonts.get(font)
            textSize = max(1f, layer.sizeFrac * frameH)
            if (Build.VERSION.SDK_INT >= 26 && font.weight != null) {
                fontVariationSettings = "'wght' ${font.weight}"
            }
        }
    }

    private fun splitGlyphs(s: String): List<String> {
        val out = ArrayList<String>(s.length)
        var i = 0
        while (i < s.length) {
            val n = Character.charCount(s.codePointAt(i))
            out += s.substring(i, i + n)
            i += n
        }
        return out
    }

    fun layout(layer: TextLayer, frameH: Float, fonts: TypefaceCache): Layout {
        val paint = basePaint(layer, frameH, fonts)
        val sizePx = paint.textSize
        val spacing = layer.letterSpacing * sizePx
        val lines = layer.text.ifEmpty { " " }.split("\n").map { raw ->
            val glyphs = splitGlyphs(raw)
            val advances = FloatArray(glyphs.size) { paint.measureText(glyphs[it]) + spacing }
            Line(glyphs, advances, max(0f, advances.sum() - if (glyphs.isNotEmpty()) spacing else 0f))
        }
        val lineHeight = sizePx * 1.18f
        return Layout(lines, sizePx, lineHeight, lines.maxOf { it.width }, lines.size * lineHeight, paint)
    }

    // --- motion ---------------------------------------------------------------

    private fun easeOut(t: Float): Float {
        val inv = 1f - t.coerceIn(0f, 1f)
        return 1f - inv * inv * inv
    }

    private fun backOut(t: Float): Float {
        val c1 = 1.70158f
        val c3 = c1 + 1f
        val x = t.coerceIn(0f, 1f) - 1f
        return 1f + c3 * x * x * x + c1 * x * x
    }

    private fun bounceOut(t0: Float): Float {
        val t = t0.coerceIn(0f, 1f)
        val n1 = 7.5625f
        val d1 = 2.75f
        return when {
            t < 1f / d1 -> n1 * t * t
            t < 2f / d1 -> { val u = t - 1.5f / d1; n1 * u * u + 0.75f }
            t < 2.5f / d1 -> { val u = t - 2.25f / d1; n1 * u * u + 0.9375f }
            else -> { val u = t - 2.625f / d1; n1 * u * u + 0.984375f }
        }
    }

    /** Whole-block motion at [localMs] into the layer. Offsets are in font-size units. */
    private fun blockMotion(anim: TextAnimation, localMs: Long): Motion {
        val m = Motion()
        val p = (localMs.toFloat() / ENTRANCE_MS).coerceIn(0f, 1f)
        val e = easeOut(p)
        val t = localMs / 1000f
        when (anim) {
            TextAnimation.FADE -> m.alpha = p
            TextAnimation.POP -> { m.scale = max(0.01f, backOut(p)); m.alpha = min(1f, p * 3f) }
            TextAnimation.BOUNCE -> { m.dy = -(1f - bounceOut(p)) * 4f; m.alpha = min(1f, p * 4f) }
            TextAnimation.ZOOM -> { m.scale = 0.2f + 0.8f * e; m.alpha = p }
            TextAnimation.SPIN -> { m.rotation = -360f * (1f - e); m.scale = max(0.01f, e) }
            TextAnimation.SLIDE_UP -> { m.dy = (1f - e) * 3f; m.alpha = p }
            TextAnimation.SLIDE_DOWN -> { m.dy = -(1f - e) * 3f; m.alpha = p }
            TextAnimation.SLIDE_LEFT -> { m.dx = (1f - e) * 5f; m.alpha = p }
            TextAnimation.SLIDE_RIGHT -> { m.dx = -(1f - e) * 5f; m.alpha = p }
            TextAnimation.SHAKE -> { m.dx = sin(t * 40f) * 0.06f; m.rotation = sin(t * 33f) * 2f }
            TextAnimation.PULSE -> m.scale = 1f + 0.08f * sin(t * 2f * PI.toFloat() * 1.5f)
            TextAnimation.SWING -> m.rotation = sin(t * 2f * PI.toFloat() * 0.8f) * 8f
            TextAnimation.FLICKER -> m.alpha = if (sin(t * 23f) + sin(t * 37f) > 1.2f) 0.25f else 1f
            else -> Unit
        }
        return m
    }

    /** Per-letter motion for glyph [i] of [count]. Returns (dy in font units, alpha), or null to hide it. */
    private fun glyphMotion(anim: TextAnimation, localMs: Long, i: Int, count: Int): Pair<Float, Float>? {
        val t = localMs / 1000f
        return when (anim) {
            TextAnimation.TYPEWRITER -> if (localMs >= i * 70L) 0f to 1f else null
            TextAnimation.RISE -> {
                val q = ((localMs - i * 45f) / 350f).coerceIn(0f, 1f)
                (1f - easeOut(q)) * 1f to q
            }
            TextAnimation.DROP -> {
                val q = ((localMs - i * 50f) / 500f).coerceIn(0f, 1f)
                -(1f - bounceOut(q)) * 2.5f to min(1f, q * 4f)
            }
            TextAnimation.WAVE -> sin(t * 6f - i * 0.6f) * 0.12f to 1f
            TextAnimation.JUMP -> {
                val periodMs = count * 120f + 600f
                val phase = (localMs % periodMs.toLong()) - i * 120f
                (if (phase in 0f..300f) -sin(phase / 300f * PI.toFloat()) * 0.35f else 0f) to 1f
            }
            else -> 0f to 1f
        }
    }

    /** How long exit effects take (less on very short captions). */
    const val EXIT_MS = 500L

    fun exitMsOf(layer: TextLayer): Long = minOf(EXIT_MS, (layer.endMs - layer.startMs) / 2)

    /** 0 while the caption is fully on screen, rising to 1 at its end while its exit plays. */
    fun exitProgress(layer: TextLayer, tMs: Long): Float {
        if (layer.exit == TextExit.NONE) return 0f
        val d = exitMsOf(layer)
        val remaining = layer.endMs - tMs
        if (d <= 0 || remaining >= d) return 0f
        return (1f - remaining.toFloat() / d).coerceIn(0f, 1f)
    }

    private fun easeIn(t: Float): Float {
        val x = t.coerceIn(0f, 1f)
        return x * x * x
    }

    /** Applies the whole-block part of an exit to [m] at progress [q] (0..1). */
    private fun applyExit(exit: TextExit, q: Float, m: Motion) {
        if (q <= 0f) return
        val e = easeIn(q)
        when (exit) {
            TextExit.FADE -> m.alpha *= 1f - q
            TextExit.SHRINK -> m.scale *= (1f - e).coerceAtLeast(0.01f)
            TextExit.BLOW_UP -> { m.scale *= 1f + 1.5f * e; m.alpha *= 1f - q }
            TextExit.SPIN -> { m.rotation += 360f * e; m.scale *= (1f - e).coerceAtLeast(0.01f) }
            TextExit.SLIDE_UP -> { m.dy -= 3f * e; m.alpha *= 1f - e }
            TextExit.SLIDE_DOWN -> { m.dy += 3f * e; m.alpha *= 1f - e }
            TextExit.SLIDE_LEFT -> { m.dx -= 5f * e; m.alpha *= 1f - e }
            TextExit.SLIDE_RIGHT -> { m.dx += 5f * e; m.alpha *= 1f - e }
            TextExit.FLICKER_OUT -> m.alpha *= if (q > 0.85f || sin(q * 60f) > 0.2f) 0f else 1f
            else -> Unit
        }
    }

    /** Per-letter part of an exit: (extra dy in font units, alpha multiplier), or null to hide the glyph. */
    private fun glyphExit(exit: TextExit, q: Float, i: Int, count: Int): Pair<Float, Float>? {
        if (q <= 0f) return 0f to 1f
        return when (exit) {
            TextExit.ERASE -> if (i < count * (1f - q)) 0f to 1f else null
            TextExit.FALL -> {
                val k = (q * 1.6f - i.toFloat() / count.coerceAtLeast(1) * 0.6f).coerceIn(0f, 1f)
                3f * easeIn(k) to 1f - k
            }
            TextExit.SCATTER -> {
                val k = easeIn(q)
                val dir = if (i % 2 == 0) -1f else 1f
                dir * 2.5f * k * (1f + (i % 3) * 0.4f) to 1f - q
            }
            else -> 0f to 1f
        }
    }

    /** True while this layer looks different from one frame to the next (entrance running or a loop). */
    fun isAnimatingAt(layer: TextLayer, tMs: Long): Boolean {
        val local = tMs - layer.startMs
        if (layer.exit != TextExit.NONE && layer.endMs - tMs < exitMsOf(layer) + 50) return true
        return when (layer.animation) {
            TextAnimation.NONE -> false
            TextAnimation.WAVE, TextAnimation.JUMP, TextAnimation.SHAKE, TextAnimation.PULSE,
            TextAnimation.SWING, TextAnimation.FLICKER, TextAnimation.RAINBOW -> true
            TextAnimation.TYPEWRITER -> local < layer.text.length * 70L + 100
            TextAnimation.RISE, TextAnimation.DROP -> local < layer.text.length * 50L + 600
            else -> local < ENTRANCE_MS + 50
        }
    }

    // --- drawing --------------------------------------------------------------

    private fun withAlpha(color: Int, a: Float): Int =
        Color.argb((Color.alpha(color) * a.coerceIn(0f, 1f)).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    private fun lerpColor(a: Int, b: Int, t: Float): Int = Color.argb(
        (Color.alpha(a) + (Color.alpha(b) - Color.alpha(a)) * t).toInt(),
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt(),
    )

    private fun darker(c: Int, f: Float): Int =
        Color.argb(Color.alpha(c), (Color.red(c) * f).toInt(), (Color.green(c) * f).toInt(), (Color.blue(c) * f).toInt())

    private fun gradientFor(layer: TextLayer, layout: Layout): Shader? {
        val w = layout.width / 2
        val h = layout.height / 2
        val s = layout.sizePx
        return when (layer.style) {
            TextStyleEffect.CHROME -> LinearGradient(0f, -h, 0f, h,
                intArrayOf(0xFFFFFFFF.toInt(), 0xFFB0BEC5.toInt(), 0xFF37474F.toInt(), 0xFFECEFF1.toInt(), 0xFF90A4AE.toInt()),
                floatArrayOf(0f, 0.4f, 0.52f, 0.7f, 1f), Shader.TileMode.CLAMP)
            TextStyleEffect.FIRE -> LinearGradient(0f, -h, 0f, h,
                intArrayOf(0xFFD50000.toInt(), 0xFFFF6D00.toInt(), 0xFFFFD600.toInt()), null, Shader.TileMode.CLAMP)
            TextStyleEffect.ICE -> LinearGradient(0f, -h, 0f, h,
                intArrayOf(0xFFFFFFFF.toInt(), 0xFFB3E5FC.toInt(), 0xFF29B6F6.toInt()), null, Shader.TileMode.CLAMP)
            TextStyleEffect.SPLIT -> LinearGradient(0f, -h, 0f, h,
                intArrayOf(layer.color, layer.color, layer.accentColor, layer.accentColor),
                floatArrayOf(0f, 0.5f, 0.5f, 1f), Shader.TileMode.CLAMP)
            TextStyleEffect.CANDY -> LinearGradient(0f, 0f, 0.18f * s, 0.18f * s,
                intArrayOf(layer.color, layer.color, layer.accentColor, layer.accentColor),
                floatArrayOf(0f, 0.5f, 0.5f, 1f), Shader.TileMode.REPEAT)
            TextStyleEffect.GOLD -> LinearGradient(0f, -h, 0f, h,
                intArrayOf(0xFFFFF3B0.toInt(), 0xFFFFC837.toInt(), 0xFFB8860B.toInt(), 0xFFFFE08A.toInt()),
                floatArrayOf(0f, 0.45f, 0.7f, 1f), Shader.TileMode.CLAMP)
            TextStyleEffect.SUNSET -> LinearGradient(-w, 0f, w, 0f,
                intArrayOf(0xFFFFD000.toInt(), 0xFFFF6A00.toInt(), 0xFFFF2E93.toInt()), null, Shader.TileMode.CLAMP)
            TextStyleEffect.OCEAN -> LinearGradient(-w, 0f, w, 0f,
                intArrayOf(0xFF00F5D4.toInt(), 0xFF00BBF9.toInt(), 0xFF3A0CA3.toInt()), null, Shader.TileMode.CLAMP)
            TextStyleEffect.RAINBOW_FILL -> LinearGradient(-w, 0f, w, 0f,
                intArrayOf(0xFFFF1744.toInt(), 0xFFFF9100.toInt(), 0xFFFFEA00.toInt(), 0xFF00E676.toInt(),
                    0xFF2979FF.toInt(), 0xFFD500F9.toInt()), null, Shader.TileMode.CLAMP)
            else -> null
        }
    }

    /** Block bounds in the layer's own (unrotated, unscaled) space, centred on 0,0 — plus style padding. */
    fun localBounds(layout: Layout): RectF {
        val pad = layout.sizePx * 0.3f
        return RectF(-layout.width / 2 - pad, -layout.height / 2 - pad, layout.width / 2 + pad, layout.height / 2 + pad)
    }

    /** Is ([px], [py]) (frame pixels) on this layer? For tap-to-select / drag. */
    fun hitTest(layer: TextLayer, frameW: Float, frameH: Float, px: Float, py: Float, fonts: TypefaceCache): Boolean {
        val layout = layout(layer, frameH, fonts)
        val cx = layer.x * frameW
        val cy = layer.y * frameH
        val rad = -layer.rotationDeg * PI.toFloat() / 180f
        val dx = px - cx
        val dy = py - cy
        val lx = (dx * cos(rad) - dy * sin(rad)) / layer.scale
        val ly = (dx * sin(rad) + dy * cos(rad)) / layer.scale
        return localBounds(layout).contains(lx, ly)
    }

    fun draw(canvas: Canvas, layer: TextLayer, frameW: Float, frameH: Float, tMs: Long, fonts: TypefaceCache) {
        if (tMs < layer.startMs || tMs >= layer.endMs || layer.text.isBlank()) return
        val local = tMs - layer.startMs
        val layout = layout(layer, frameH, fonts)
        val s = layout.sizePx
        val motion = blockMotion(layer.animation, local)
        val exitQ = exitProgress(layer, tMs)
        applyExit(layer.exit, exitQ, motion)
        val alpha = (layer.opacity * motion.alpha).coerceIn(0f, 1f)
        if (alpha <= 0.001f) return

        canvas.save()
        canvas.translate(layer.x * frameW + motion.dx * s, layer.y * frameH + motion.dy * s)
        canvas.rotate(layer.rotationDeg + motion.rotation)
        canvas.scale(layer.scale * motion.scale, layer.scale * motion.scale)

        val fm = layout.paint.fontMetrics
        val glyphHeight = fm.descent - fm.ascent
        val top0 = -layout.height / 2
        val baseOffset = (layout.lineHeight - glyphHeight) / 2 - fm.ascent

        fun lineStartX(line: Line): Float = when (layer.align) {
            TextAlignment.LEFT -> -layout.width / 2
            TextAlignment.CENTER -> -line.width / 2
            TextAlignment.RIGHT -> layout.width / 2 - line.width
        }

        // Per-line backgrounds.
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = withAlpha(layer.accentColor, alpha) }
        layout.lines.forEachIndexed { li, line ->
            if (line.width <= 0f) return@forEachIndexed
            val x0 = lineStartX(line)
            val top = top0 + li * layout.lineHeight
            when (layer.style) {
                TextStyleEffect.BOX ->
                    canvas.drawRoundRect(RectF(x0 - 0.25f * s, top + 0.02f * s, x0 + line.width + 0.25f * s, top + layout.lineHeight - 0.02f * s), 0.12f * s, 0.12f * s, bg)
                TextStyleEffect.PILL -> {
                    val r = RectF(x0 - 0.45f * s, top + 0.04f * s, x0 + line.width + 0.45f * s, top + layout.lineHeight - 0.04f * s)
                    canvas.drawRoundRect(r, r.height() / 2, r.height() / 2, bg)
                }
                TextStyleEffect.HIGHLIGHT -> {
                    bg.color = withAlpha(layer.accentColor, alpha * 0.85f)
                    canvas.drawRect(RectF(x0 - 0.1f * s, top + layout.lineHeight * 0.45f, x0 + line.width + 0.1f * s, top + layout.lineHeight * 0.92f), bg)
                }
                else -> Unit
            }
        }

        drawGlyphs(canvas, layer, layout, local, alpha, lineStartX = ::lineStartX, top0 = top0, baseOffset = baseOffset, mirror = false, exitQ = exitQ)

        if (layer.style == TextStyleEffect.REFLECTION) {
            val bottom = top0 + layout.height
            val gap = 0.04f * s
            val region = RectF(-layout.width / 2 - s, bottom + gap, layout.width / 2 + s, bottom + gap + layout.height)
            val sc = canvas.saveLayer(region, null)
            canvas.save()
            canvas.translate(0f, 2 * bottom + gap)
            canvas.scale(1f, -1f)
            drawGlyphs(canvas, layer, layout, local, alpha * 0.45f, lineStartX = ::lineStartX, top0 = top0, baseOffset = baseOffset, mirror = true, exitQ = exitQ)
            canvas.restore()
            val fade = Paint().apply {
                shader = LinearGradient(0f, region.top, 0f, region.bottom, Color.BLACK, Color.TRANSPARENT, Shader.TileMode.CLAMP)
                xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
            }
            canvas.drawRect(region, fade)
            canvas.restoreToCount(sc)
        }
        canvas.restore()
    }

    private fun drawGlyphs(
        canvas: Canvas,
        layer: TextLayer,
        layout: Layout,
        local: Long,
        alpha: Float,
        lineStartX: (Line) -> Float,
        top0: Float,
        baseOffset: Float,
        mirror: Boolean,
        exitQ: Float,
    ) {
        val s = layout.sizePx
        val fill = Paint(layout.paint)
        val shader = gradientFor(layer, layout)
        val stroke = Paint(layout.paint).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
        }
        val extra = Paint(layout.paint)
        val total = layout.lines.sumOf { it.glyphs.size }
        var index = 0

        layout.lines.forEachIndexed { li, line ->
            var x = lineStartX(line)
            val baseline = top0 + li * layout.lineHeight + baseOffset
            line.glyphs.forEachIndexed { gi, g ->
                val gm = glyphMotion(layer.animation, local, index, total)
                val ge = glyphExit(layer.exit, exitQ, index, total)
                val i = index
                index++
                if (gm == null || ge == null) { x += line.advances[gi]; return@forEachIndexed }
                val a = alpha * gm.second * ge.second
                val y = baseline + (gm.first + ge.first) * s
                val color = if (layer.animation == TextAnimation.RAINBOW) {
                    Color.HSVToColor(floatArrayOf(((local / 1000f) * 120f + i * 25f) % 360f, 0.85f, 1f))
                } else {
                    layer.color
                }

                if (!mirror) {
                    when (layer.style) {
                        TextStyleEffect.OUTLINE -> {
                            stroke.color = withAlpha(layer.accentColor, a); stroke.strokeWidth = 0.1f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.SHADOW -> {
                            extra.shader = null; extra.clearShadowLayer(); extra.color = withAlpha(layer.accentColor, a * 0.8f)
                            canvas.drawText(g, x + 0.05f * s, y + 0.06f * s, extra)
                        }
                        TextStyleEffect.GLOW -> {
                            extra.shader = null; extra.color = withAlpha(color, a)
                            extra.setShadowLayer(0.35f * s, 0f, 0f, withAlpha(layer.accentColor, a))
                            canvas.drawText(g, x, y, extra); extra.clearShadowLayer()
                        }
                        TextStyleEffect.NEON -> {
                            extra.shader = null; extra.color = withAlpha(layer.accentColor, a)
                            extra.setShadowLayer(0.5f * s, 0f, 0f, withAlpha(layer.accentColor, a))
                            canvas.drawText(g, x, y, extra)
                            extra.setShadowLayer(0.18f * s, 0f, 0f, withAlpha(layer.accentColor, a))
                            canvas.drawText(g, x, y, extra); extra.clearShadowLayer()
                        }
                        TextStyleEffect.EXTRUDE -> {
                            extra.shader = null; extra.clearShadowLayer(); extra.color = withAlpha(darker(layer.accentColor, 0.75f), a)
                            for (k in 6 downTo 1) canvas.drawText(g, x + k * 0.015f * s, y + k * 0.015f * s, extra)
                        }
                        TextStyleEffect.COMIC -> {
                            extra.shader = null; extra.clearShadowLayer(); extra.color = withAlpha(Color.BLACK, a)
                            canvas.drawText(g, x + 0.07f * s, y + 0.08f * s, extra)
                            stroke.color = withAlpha(Color.BLACK, a); stroke.strokeWidth = 0.14f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.RETRO -> {
                            stroke.color = withAlpha(layer.accentColor, a); stroke.strokeWidth = 0.24f * s
                            canvas.drawText(g, x, y, stroke)
                            stroke.color = withAlpha(Color.WHITE, a); stroke.strokeWidth = 0.11f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.GLITCH -> {
                            extra.shader = null; extra.clearShadowLayer()
                            extra.color = withAlpha(0xFF00E5FF.toInt(), a * 0.85f)
                            canvas.drawText(g, x - 0.05f * s, y, extra)
                            extra.color = withAlpha(0xFFFF1744.toInt(), a * 0.85f)
                            canvas.drawText(g, x + 0.05f * s, y, extra)
                        }
                        TextStyleEffect.GOLD -> {
                            stroke.color = withAlpha(0xFF6B4A00.toInt(), a); stroke.strokeWidth = 0.05f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.STICKER -> {
                            stroke.color = withAlpha(Color.WHITE, a); stroke.strokeWidth = 0.3f * s
                            stroke.setShadowLayer(0.12f * s, 0f, 0.06f * s, withAlpha(Color.BLACK, a * 0.45f))
                            canvas.drawText(g, x, y, stroke); stroke.clearShadowLayer()
                        }
                        TextStyleEffect.LONG_SHADOW -> {
                            extra.shader = null; extra.clearShadowLayer(); extra.color = withAlpha(layer.accentColor, a)
                            for (k in 18 downTo 1) canvas.drawText(g, x + k * 0.02f * s, y + k * 0.02f * s, extra)
                        }
                        TextStyleEffect.DOUBLE_OUTLINE -> {
                            stroke.color = withAlpha(color, a); stroke.strokeWidth = 0.32f * s
                            canvas.drawText(g, x, y, stroke)
                            stroke.color = withAlpha(layer.accentColor, a); stroke.strokeWidth = 0.18f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.CHROME -> {
                            stroke.color = withAlpha(0xFF263238.toInt(), a); stroke.strokeWidth = 0.06f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.FIRE -> {
                            extra.shader = null; extra.color = withAlpha(0xFFFF6D00.toInt(), a)
                            extra.setShadowLayer(0.4f * s, 0f, -0.08f * s, withAlpha(0xFFFF3D00.toInt(), a))
                            canvas.drawText(g, x, y, extra); extra.clearShadowLayer()
                        }
                        TextStyleEffect.ICE -> {
                            extra.shader = null; extra.color = withAlpha(0xFF81D4FA.toInt(), a)
                            extra.setShadowLayer(0.3f * s, 0f, 0f, withAlpha(0xFF00E5FF.toInt(), a))
                            canvas.drawText(g, x, y, extra); extra.clearShadowLayer()
                            stroke.color = withAlpha(Color.WHITE, a); stroke.strokeWidth = 0.05f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        TextStyleEffect.CANDY -> {
                            stroke.color = withAlpha(Color.WHITE, a); stroke.strokeWidth = 0.12f * s
                            canvas.drawText(g, x, y, stroke)
                        }
                        else -> Unit
                    }
                }

                if (layer.style == TextStyleEffect.HOLLOW && !mirror) {
                    stroke.color = withAlpha(color, a); stroke.strokeWidth = 0.07f * s
                    canvas.drawText(g, x, y, stroke)
                } else if (layer.style != TextStyleEffect.GLOW || mirror) {
                    if (shader != null && layer.animation != TextAnimation.RAINBOW) {
                        fill.shader = shader; fill.alpha = (255 * a).toInt()
                    } else {
                        fill.shader = null
                        fill.color = withAlpha(
                            if (layer.style == TextStyleEffect.NEON && !mirror) lerpColor(color, Color.WHITE, 0.6f) else color, a,
                        )
                    }
                    canvas.drawText(g, x, y, fill)
                }
                x += line.advances[gi]
            }
        }
    }
}

/**
 * Export side: a full-frame Media3 overlay (added at COMPOSITION level, so
 * it sits over every clip and isn't moved by clip transitions) whose
 * bitmap is redrawn with [TextRenderer] only when something changed — an
 * unchanged bitmap keeps its generation id, so Media3 skips re-uploading it.
 *
 * Time base: the first presentation timestamp seen = 0 of the OUTPUT (the
 * same robustness trick as the transition effects — no reliance on how
 * Transformer offsets timestamps internally).
 */
@UnstableApi
class TextOverlayEffectBitmap(
    private val layers: List<TextLayer>,
    private val fonts: TypefaceCache,
    /** Animated stickers, drawn under the captions (they always animate, so redraw while one is on screen). */
    private val stickers: List<StickerLayer> = emptyList(),
    private val stickerStore: StickerStore? = null,
) : BitmapOverlay() {
    private var bitmap: Bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
    private var canvas = Canvas(bitmap)
    private var firstUs = C.TIME_UNSET
    private var lastKey: String? = null

    override fun configure(videoSize: Size) {
        super.configure(videoSize)
        bitmap = Bitmap.createBitmap(max(2, videoSize.width), max(2, videoSize.height), Bitmap.Config.ARGB_8888)
        canvas = Canvas(bitmap)
        lastKey = null
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        if (firstUs == C.TIME_UNSET) firstUs = presentationTimeUs
        val tMs = (presentationTimeUs - firstUs) / 1000
        val active = layers.filter { tMs >= it.startMs && tMs < it.endMs }
        val activeStickers = if (stickerStore == null) emptyList() else stickers.filter { tMs >= it.startMs && tMs < it.endMs }
        val key = (active.map { it.id } + activeStickers.map { it.id }).joinToString(",")
        val animating = activeStickers.isNotEmpty() || active.any { TextRenderer.isAnimatingAt(it, tMs) }
        if (animating || key != lastKey) {
            bitmap.eraseColor(Color.TRANSPARENT)
            val w = bitmap.width.toFloat()
            val h = bitmap.height.toFloat()
            stickerStore?.let { store -> activeStickers.forEach { StickerRenderer.draw(canvas, it, w, h, tMs, store) } }
            active.forEach { TextRenderer.draw(canvas, it, w, h, tMs, fonts) }
            lastKey = key
        }
        return bitmap
    }
}
