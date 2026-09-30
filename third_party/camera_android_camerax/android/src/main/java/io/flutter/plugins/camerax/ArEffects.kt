// ADGAG PATCH — the live AR effects' artwork (see AdGagAr.kt).
package io.flutter.plugins.camerax

import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.sin

/**
 * Every effect is drawn procedurally in FACE UNITS (AdGagAr's face frame):
 * origin between the eyes, x: 1 = the distance between the eyes, +y down the
 * face. Rough landmarks in these units: eyes (±0.5, 0), nose base ≈ (0, 0.7),
 * mouth ≈ (0, 1.05), cheeks ≈ (±0.75, 0.75), chin ≈ 1.6, forehead top ≈ -1.0,
 * face edges ≈ ±1.1. The real nose/mouth/cheeks come from the face
 * ([FaceGeom.toLocal]). No bitmaps: nothing to license, sharp at any size.
 *
 * Animated effects are STATELESS functions of time [t] (seconds): particles
 * are placed from a hash of their index and the time, so nothing is stored
 * per face or per frame.
 *
 * All artwork is left-right SYMMETRIC on purpose: the front camera's preview
 * is mirrored but its recording isn't, so anything asymmetric (text!) would
 * read backwards in one of them.
 *
 * The ids are the contract with the app (lib/.../ar_effects.dart).
 */
object ArEffects {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    fun draw(c: Canvas, id: String, face: FaceGeom, t: Float) {
        fill.shader = null
        fill.alpha = 255
        stroke.shader = null
        stroke.alpha = 255
        when (id) {
            "sunglasses" -> sunglasses(c)
            "nerd" -> nerdGlasses(c)
            "crown" -> crown(c, t)
            "flower_crown" -> flowerCrown(c)
            "party" -> partyHat(c, t)
            "viking" -> viking(c)
            "devil" -> devil(c, t)
            "halo" -> halo(c, t)
            "cat" -> cat(c, face)
            "bunny" -> bunny(c, face)
            "puppy" -> puppy(c, face)
            "alien" -> alien(c, t)
            "heart_eyes" -> heartEyes(c, t)
            "star_eyes" -> starEyes(c, t)
            "blush" -> blush(c, face)
            "tears" -> tears(c, t)
            "hearts" -> floatingHearts(c, t)
            "money_rain" -> moneyRain(c, t)
            "sparkles" -> sparkles(c, t)
            "rainbow" -> rainbowMouth(c, face, t)
            "mustache" -> mustache(c, face)
            "clown" -> clown(c, face)
        }
    }

    // ---------------------------------------------------------------- glasses

    private fun sunglasses(c: Canvas) {
        for (side in SIDES) {
            val cx = 0.52f * side
            val lens = RectF(cx - 0.43f, -0.25f, cx + 0.43f, 0.3f)
            fill.shader = LinearGradient(0f, -0.25f, 0f, 0.3f, Color.rgb(40, 40, 55), Color.rgb(4, 4, 10), Shader.TileMode.CLAMP)
            c.drawRoundRect(lens, 0.22f, 0.22f, fill)
            fill.shader = null
            stroke.color = Color.rgb(15, 15, 15)
            stroke.strokeWidth = 0.08f
            c.drawRoundRect(lens, 0.22f, 0.22f, stroke)
            fill.color = Color.argb(140, 255, 255, 255)
            c.drawPath(Path().apply {
                moveTo(cx - 0.32f, -0.15f); lineTo(cx - 0.1f, -0.15f); lineTo(cx - 0.3f, 0.14f); close()
            }, fill)
            fill.color = Color.argb(90, 255, 255, 255)
            c.drawCircle(cx + 0.24f, 0.16f, 0.04f, fill)
        }
        stroke.color = Color.rgb(15, 15, 15)
        stroke.strokeWidth = 0.09f
        c.drawLine(-0.1f, -0.13f, 0.1f, -0.13f, stroke)
        c.drawLine(-0.95f, -0.12f, -1.22f, -0.2f, stroke)
        c.drawLine(0.95f, -0.12f, 1.22f, -0.2f, stroke)
    }

    private fun nerdGlasses(c: Canvas) {
        for (side in SIDES) {
            val cx = 0.5f * side
            fill.color = Color.argb(45, 180, 220, 255)
            c.drawCircle(cx, 0.02f, 0.36f, fill)
            stroke.color = Color.rgb(25, 20, 18)
            stroke.strokeWidth = 0.12f
            c.drawCircle(cx, 0.02f, 0.36f, stroke)
            stroke.color = Color.argb(160, 255, 255, 255)
            stroke.strokeWidth = 0.04f
            c.drawArc(RectF(cx - 0.26f, -0.24f, cx + 0.26f, 0.28f), 200f, 60f, false, stroke)
        }
        stroke.color = Color.rgb(25, 20, 18)
        stroke.strokeWidth = 0.1f
        c.drawArc(RectF(-0.16f, -0.12f, 0.16f, 0.12f), 200f, 140f, false, stroke)
        c.drawLine(-0.86f, -0.04f, -1.2f, -0.12f, stroke)
        c.drawLine(0.86f, -0.04f, 1.2f, -0.12f, stroke)
        // Tape on the bridge.
        fill.color = Color.rgb(245, 245, 235)
        c.drawRect(-0.07f, -0.14f, 0.07f, 0.0f, fill)
    }

    // ------------------------------------------------------------- headwear

    private fun crown(c: Canvas, t: Float) {
        val path = Path().apply {
            moveTo(-0.85f, -1.15f)
            lineTo(-0.9f, -1.95f)
            lineTo(-0.45f, -1.55f)
            lineTo(0f, -2.15f)
            lineTo(0.45f, -1.55f)
            lineTo(0.9f, -1.95f)
            lineTo(0.85f, -1.15f)
            close()
        }
        fill.shader = LinearGradient(0f, -2.15f, 0f, -1.15f, Color.rgb(255, 232, 120), Color.rgb(205, 140, 15), Shader.TileMode.CLAMP)
        c.drawPath(path, fill)
        fill.shader = null
        stroke.color = Color.rgb(140, 90, 5)
        stroke.strokeWidth = 0.05f
        c.drawPath(path, stroke)
        fill.color = Color.rgb(170, 110, 10)
        c.drawRect(-0.86f, -1.32f, 0.86f, -1.15f, fill)
        fill.color = Color.rgb(255, 245, 170)
        for (x in floatArrayOf(-0.9f, 0f, 0.9f)) c.drawCircle(x, if (x == 0f) -2.17f else -1.97f, 0.1f, fill)
        gem(c, 0f, -1.47f, 0.15f, Color.rgb(230, 30, 70))
        gem(c, -0.5f, -1.4f, 0.1f, Color.rgb(40, 120, 240))
        gem(c, 0.5f, -1.4f, 0.1f, Color.rgb(40, 120, 240))
        // Twinkles on the tips.
        for ((i, x) in floatArrayOf(-0.9f, 0f, 0.9f).withIndex()) {
            val tw = twinkle(t, i)
            if (tw > 0.05f) sparkle(c, x, if (x == 0f) -2.25f else -2.05f, 0.18f * tw, Color.WHITE)
        }
    }

    private fun flowerCrown(c: Canvas) {
        val colors = intArrayOf(
            Color.rgb(255, 120, 170), Color.rgb(255, 210, 80), Color.rgb(170, 130, 255),
            Color.rgb(255, 150, 90), Color.rgb(120, 200, 255),
        )
        val n = 9
        // Leaves first (under the flowers).
        fill.color = Color.rgb(90, 170, 90)
        for (i in 0 until n - 1) {
            val a = arcPoint(i + 0.5f, n)
            c.save()
            c.translate(a.x, a.y)
            c.rotate(if (a.x < 0) -30f else 30f)
            c.drawOval(RectF(-0.07f, -0.16f, 0.07f, 0.16f), fill)
            c.restore()
        }
        for (i in 0 until n) {
            val p = arcPoint(i.toFloat(), n)
            // Mirror-symmetric colours: index from the centre.
            val k = abs(i - n / 2) % colors.size
            flower(c, p.x, p.y, if (i == n / 2) 0.24f else 0.19f, colors[k])
        }
    }

    /** Points on the arc over the forehead, from ear to ear. */
    private fun arcPoint(i: Float, n: Int): PointF {
        val a = PI.toFloat() * (0.12f + 0.76f * i / (n - 1))
        return PointF(-cos(a) * 1.15f, -0.95f - sin(a) * 0.45f)
    }

    private fun partyHat(c: Canvas, t: Float) {
        val hat = Path().apply { moveTo(-0.6f, -1.2f); lineTo(0f, -2.65f); lineTo(0.6f, -1.2f); close() }
        fill.shader = LinearGradient(-0.6f, 0f, 0.6f, 0f, Color.rgb(14, 170, 166), Color.rgb(40, 220, 210), Shader.TileMode.MIRROR)
        c.drawPath(hat, fill)
        fill.shader = null
        c.save()
        c.clipPath(hat)
        fill.color = Color.rgb(255, 214, 64)
        var y = -2.55f
        while (y < -1.1f) {
            c.drawRect(-1f, y, 1f, y + 0.12f, fill)
            y += 0.32f
        }
        c.restore()
        fill.color = Color.rgb(255, 90, 140)
        c.drawCircle(0f, -2.68f, 0.17f, fill)
        stroke.color = Color.WHITE
        stroke.strokeWidth = 0.06f
        c.drawLine(-0.62f, -1.2f, 0.62f, -1.2f, stroke)
        // Confetti falling around the head.
        val confetti = intArrayOf(Color.rgb(255, 90, 140), Color.rgb(255, 214, 64), Color.rgb(22, 197, 192), Color.rgb(140, 110, 255))
        for (i in 0 until 16) {
            val side = if (i % 2 == 0) -1f else 1f
            val x = side * (0.8f + 1.0f * hash(i, 1))
            val y = fall(t, i, 0.35f, -2.8f, 2.2f)
            c.save()
            c.translate(x, y)
            c.rotate(t * 240f * (0.5f + hash(i, 2)) * side)
            fill.color = confetti[i % confetti.size]
            c.drawRect(-0.06f, -0.03f, 0.06f, 0.03f, fill)
            c.restore()
        }
    }

    private fun viking(c: Canvas) {
        // Horns first (behind the helmet).
        for (side in SIDES) {
            val horn = Path().apply {
                moveTo(0.78f * side, -1.2f)
                cubicTo(1.3f * side, -1.25f, 1.55f * side, -1.7f, 1.35f * side, -2.25f)
                cubicTo(1.25f * side, -1.85f, 1.1f * side, -1.55f, 0.72f * side, -1.48f)
                close()
            }
            fill.shader = LinearGradient(0.8f * side, -1.2f, 1.35f * side, -2.25f, Color.rgb(250, 240, 215), Color.rgb(200, 180, 140), Shader.TileMode.CLAMP)
            c.drawPath(horn, fill)
            fill.shader = null
            stroke.color = Color.rgb(150, 130, 95)
            stroke.strokeWidth = 0.03f
            c.drawPath(horn, stroke)
        }
        val dome = RectF(-0.95f, -2.0f, 0.95f, -0.5f)
        fill.shader = LinearGradient(-0.9f, -2f, 0.9f, -1f, Color.rgb(200, 205, 215), Color.rgb(110, 115, 125), Shader.TileMode.MIRROR)
        c.drawArc(dome, 180f, 180f, true, fill)
        fill.shader = null
        fill.color = Color.rgb(150, 110, 60)
        c.drawRect(-0.98f, -1.33f, 0.98f, -1.13f, fill)
        c.drawRect(-0.08f, -2.0f, 0.08f, -1.25f, fill)
        fill.color = Color.rgb(230, 200, 120)
        for (x in floatArrayOf(-0.7f, -0.35f, 0f, 0.35f, 0.7f)) c.drawCircle(x, -1.23f, 0.045f, fill)
    }

    private fun devil(c: Canvas, t: Float) {
        val pulse = 0.5f + 0.5f * sin(t * 4f)
        for (side in SIDES) {
            val horn = Path().apply {
                moveTo(0.3f * side, -1.05f)
                cubicTo(0.45f * side, -1.5f, 0.75f * side, -1.75f, 0.95f * side, -1.95f)
                cubicTo(0.85f * side, -1.55f, 0.8f * side, -1.25f, 0.7f * side, -1.0f)
                close()
            }
            glow.color = Color.argb((80 + 80 * pulse).toInt(), 255, 40, 20)
            glow.maskFilter = BlurMaskFilter(0.15f, BlurMaskFilter.Blur.NORMAL)
            c.drawPath(horn, glow)
            glow.maskFilter = null
            fill.shader = LinearGradient(0.3f * side, -1.0f, 0.95f * side, -1.95f, Color.rgb(200, 10, 20), Color.rgb(255, 80, 60), Shader.TileMode.CLAMP)
            c.drawPath(horn, fill)
            fill.shader = null
        }
    }

    private fun halo(c: Canvas, t: Float) {
        val pulse = 0.75f + 0.25f * sin(t * 3f)
        val bob = 0.04f * sin(t * 2f)
        val ring = RectF(-0.8f, -2.12f + bob, 0.8f, -1.76f + bob)
        stroke.color = Color.argb((110 * pulse).toInt(), 255, 230, 120)
        stroke.strokeWidth = 0.32f
        c.drawOval(ring, stroke)
        stroke.color = Color.rgb(255, 215, 70)
        stroke.strokeWidth = 0.11f
        c.drawOval(ring, stroke)
        stroke.color = Color.argb(230, 255, 250, 225)
        stroke.strokeWidth = 0.035f
        c.drawOval(ring, stroke)
    }

    // --------------------------------------------------------------- animals

    private fun cat(c: Canvas, face: FaceGeom) {
        for (side in SIDES) {
            val outer = Path().apply {
                moveTo(0.35f * side, -1.05f); lineTo(0.95f * side, -1.95f); lineTo(1.1f * side, -0.85f); close()
            }
            fill.color = Color.rgb(70, 60, 60)
            c.drawPath(outer, fill)
            val inner = Path().apply {
                moveTo(0.52f * side, -1.07f); lineTo(0.92f * side, -1.68f); lineTo(1.0f * side, -0.98f); close()
            }
            fill.color = Color.rgb(255, 160, 185)
            c.drawPath(inner, fill)
        }
        val nose = face.toLocal(face.nose)
        val ny = nose.y - 0.12f
        fill.color = Color.rgb(255, 130, 160)
        c.drawPath(Path().apply { moveTo(-0.14f, ny - 0.05f); lineTo(0.14f, ny - 0.05f); lineTo(0f, ny + 0.1f); close() }, fill)
        stroke.color = Color.argb(230, 40, 35, 35)
        stroke.strokeWidth = 0.025f
        for (side in SIDES) {
            for (k in -1..1) {
                c.drawLine(0.22f * side, ny + 0.08f + 0.05f * k, 0.95f * side, ny + 0.02f + 0.14f * k, stroke)
            }
        }
    }

    private fun bunny(c: Canvas, face: FaceGeom) {
        for (side in SIDES) {
            c.save()
            c.translate(0.45f * side, -1.1f)
            c.rotate(12f * side)
            fill.color = Color.rgb(250, 250, 250)
            c.drawOval(RectF(-0.25f, -1.35f, 0.25f, 0.1f), fill)
            stroke.color = Color.rgb(220, 220, 225)
            stroke.strokeWidth = 0.03f
            c.drawOval(RectF(-0.25f, -1.35f, 0.25f, 0.1f), stroke)
            fill.color = Color.rgb(255, 180, 200)
            c.drawOval(RectF(-0.13f, -1.2f, 0.13f, -0.05f), fill)
            c.restore()
        }
        val nose = face.toLocal(face.nose)
        fill.color = Color.rgb(255, 140, 170)
        c.drawOval(RectF(-0.12f, nose.y - 0.2f, 0.12f, nose.y - 0.04f), fill)
        val mouth = face.toLocal(face.mouth)
        fill.color = Color.WHITE
        stroke.color = Color.rgb(190, 190, 190)
        stroke.strokeWidth = 0.02f
        for (side in SIDES) {
            val r = RectF(if (side < 0) -0.13f else 0.005f, mouth.y - 0.04f, if (side < 0) -0.005f else 0.13f, mouth.y + 0.2f)
            c.drawRoundRect(r, 0.03f, 0.03f, fill)
            c.drawRoundRect(r, 0.03f, 0.03f, stroke)
        }
    }

    private fun puppy(c: Canvas, face: FaceGeom) {
        for (side in SIDES) {
            c.save()
            c.translate(1.05f * side, -0.95f)
            c.rotate(-18f * side)
            fill.shader = LinearGradient(0f, -0.55f, 0f, 0.75f, Color.rgb(150, 95, 50), Color.rgb(95, 60, 30), Shader.TileMode.CLAMP)
            c.drawOval(RectF(-0.32f, -0.55f, 0.32f, 0.75f), fill)
            fill.shader = null
            fill.color = Color.rgb(230, 150, 150)
            c.drawOval(RectF(-0.16f, -0.3f, 0.16f, 0.5f), fill)
            c.restore()
        }
        val nose = face.toLocal(face.nose)
        val cy = nose.y - 0.1f
        fill.color = Color.rgb(25, 20, 20)
        c.drawOval(RectF(-0.24f, cy - 0.16f, 0.24f, cy + 0.14f), fill)
        fill.color = Color.argb(160, 255, 255, 255)
        c.drawOval(RectF(-0.1f, cy - 0.12f, 0.1f, cy - 0.05f), fill)
        // Tongue only while the mouth is open.
        val open = face.mouthOpen()
        if (open > 0.15f) {
            val mb = face.toLocal(face.mouthBottom)
            val len = 0.25f + 0.35f * open
            fill.color = Color.rgb(240, 90, 110)
            c.drawRoundRect(RectF(-0.17f, mb.y - 0.15f, 0.17f, mb.y - 0.15f + len), 0.17f, 0.17f, fill)
            stroke.color = Color.rgb(200, 50, 70)
            stroke.strokeWidth = 0.03f
            c.drawLine(0f, mb.y - 0.1f, 0f, mb.y - 0.2f + len, stroke)
        }
    }

    private fun alien(c: Canvas, t: Float) {
        for (side in SIDES) {
            val sway = 12f * sin(t * 3f + if (side < 0) 0f else 1.3f)
            c.save()
            c.translate(0.35f * side, -1.05f)
            c.rotate(20f * side + sway)
            stroke.color = Color.rgb(90, 200, 90)
            stroke.strokeWidth = 0.06f
            c.drawLine(0f, 0f, 0f, -0.9f, stroke)
            fill.shader = RadialGradient(-0.05f, -0.97f, 0.2f, Color.rgb(200, 255, 170), Color.rgb(60, 180, 60), Shader.TileMode.CLAMP)
            c.drawCircle(0f, -0.95f, 0.16f, fill)
            fill.shader = null
            c.restore()
        }
    }

    // ------------------------------------------------------------------ eyes

    private fun heartEyes(c: Canvas, t: Float) {
        val beat = 1f + 0.12f * max(0f, sin(t * 7f))
        for (side in SIDES) {
            val cx = 0.5f * side
            val s = 0.34f * beat
            fill.shader = RadialGradient(cx - s * 0.3f, -s * 0.3f, s * 1.4f, Color.rgb(255, 90, 120), Color.rgb(210, 15, 55), Shader.TileMode.CLAMP)
            c.drawPath(heart(cx, 0.05f, s), fill)
            fill.shader = null
            fill.color = Color.argb(170, 255, 255, 255)
            c.drawCircle(cx - s * 0.45f, 0.05f - s * 0.45f, s * 0.14f, fill)
        }
    }

    private fun starEyes(c: Canvas, t: Float) {
        for (side in SIDES) {
            c.save()
            c.translate(0.5f * side, 0.02f)
            c.rotate(t * 90f * side)
            fill.shader = RadialGradient(0f, 0f, 0.42f, Color.rgb(255, 250, 180), Color.rgb(255, 190, 20), Shader.TileMode.CLAMP)
            c.drawPath(star(0f, 0f, 0.42f, 0.18f, 5), fill)
            fill.shader = null
            stroke.color = Color.rgb(220, 140, 0)
            stroke.strokeWidth = 0.03f
            c.drawPath(star(0f, 0f, 0.42f, 0.18f, 5), stroke)
            c.restore()
        }
    }

    private fun tears(c: Canvas, t: Float) {
        for (side in SIDES) {
            val x0 = 0.52f * side
            // A streak down the cheek plus drops running along it.
            fill.shader = LinearGradient(0f, 0.15f, 0f, 1.3f, Color.argb(150, 120, 190, 255), Color.argb(20, 120, 190, 255), Shader.TileMode.CLAMP)
            c.drawRoundRect(RectF(x0 - 0.06f, 0.15f, x0 + 0.06f, 1.3f), 0.06f, 0.06f, fill)
            fill.shader = null
            for (i in 0 until 3) {
                val y = fall(t, i + if (side < 0) 0 else 7, 0.9f, 0.2f, 1.6f)
                val a = (255 * (1f - ((y - 0.2f) / 1.4f).coerceIn(0f, 1f))).toInt()
                fill.color = Color.argb(a, 110, 180, 255)
                c.drawPath(drop(x0, y, 0.09f), fill)
            }
        }
    }

    // ------------------------------------------------------------------ face

    private fun blush(c: Canvas, face: FaceGeom) {
        for (cheek in listOf(face.toLocal(face.leftCheek), face.toLocal(face.rightCheek))) {
            fill.shader = RadialGradient(cheek.x, cheek.y, 0.32f, Color.argb(150, 255, 90, 120), Color.argb(0, 255, 90, 120), Shader.TileMode.CLAMP)
            c.drawCircle(cheek.x, cheek.y, 0.32f, fill)
            fill.shader = null
            stroke.color = Color.argb(170, 255, 255, 255)
            stroke.strokeWidth = 0.025f
            for (k in 0..2) {
                val x = cheek.x - 0.12f + 0.12f * k
                c.drawLine(x, cheek.y - 0.06f, x - 0.05f, cheek.y + 0.06f, stroke)
            }
        }
    }

    private fun mustache(c: Canvas, face: FaceGeom) {
        val nose = face.toLocal(face.nose)
        val mouth = face.toLocal(face.mouth)
        val y = nose.y + (mouth.y - nose.y) * 0.45f
        val half = Path().apply {
            moveTo(0f, y - 0.05f)
            cubicTo(0.18f, y - 0.2f, 0.45f, y - 0.16f, 0.55f, y + 0.02f)
            cubicTo(0.62f, y + 0.12f, 0.74f, y + 0.12f, 0.8f, y - 0.02f)
            cubicTo(0.76f, y + 0.24f, 0.5f, y + 0.26f, 0.35f, y + 0.12f)
            cubicTo(0.22f, y + 0.02f, 0.1f, y + 0.08f, 0f, y + 0.12f)
            close()
        }
        fill.shader = LinearGradient(0f, y - 0.2f, 0f, y + 0.25f, Color.rgb(80, 50, 30), Color.rgb(35, 20, 12), Shader.TileMode.CLAMP)
        c.drawPath(half, fill)
        c.save()
        c.scale(-1f, 1f)
        c.drawPath(half, fill)
        c.restore()
        fill.shader = null
    }

    private fun clown(c: Canvas, face: FaceGeom) {
        // Curly hair tufts by the temples.
        val hair = intArrayOf(Color.rgb(255, 80, 60), Color.rgb(255, 150, 40))
        for (side in SIDES) {
            for (k in 0 until 5) {
                fill.color = hair[k % 2]
                c.drawCircle((1.0f + 0.12f * (k % 2)) * side, -0.95f + 0.28f * k - 0.2f, 0.22f, fill)
            }
        }
        val nose = face.toLocal(face.nose)
        val cy = nose.y - 0.08f
        fill.shader = RadialGradient(-0.08f, cy - 0.1f, 0.34f, Color.rgb(255, 100, 100), Color.rgb(190, 0, 20), Shader.TileMode.CLAMP)
        c.drawCircle(0f, cy, 0.28f, fill)
        fill.shader = null
        fill.color = Color.argb(200, 255, 255, 255)
        c.drawOval(RectF(-0.14f, cy - 0.19f, -0.02f, cy - 0.09f), fill)
    }

    private fun rainbowMouth(c: Canvas, face: FaceGeom, t: Float) {
        val open = face.mouthOpen()
        if (open < 0.2f) return
        val mb = face.toLocal(face.mouthBottom)
        val mouth = face.toLocal(face.mouth)
        val top = (mouth.y + mb.y) / 2f
        val colors = intArrayOf(
            Color.rgb(255, 60, 60), Color.rgb(255, 150, 40), Color.rgb(255, 225, 50),
            Color.rgb(70, 200, 90), Color.rgb(50, 140, 255), Color.rgb(140, 80, 230),
        )
        val len = 1.4f + 1.6f * open
        val band = 0.075f
        val width = band * colors.size
        for ((i, col) in colors.withIndex()) {
            val x = -width / 2f + band * (i + 0.5f)
            val p = Path().apply {
                moveTo(x, top)
                var y = top
                while (y < top + len) {
                    y += 0.1f
                    val spread = (y - top) * 0.35f
                    lineTo(x * (1f + spread * 3f) + 0.05f * sin(y * 6f - t * 10f), y)
                }
            }
            stroke.color = col
            stroke.strokeWidth = band * 1.15f
            stroke.strokeCap = Paint.Cap.BUTT
            c.drawPath(p, stroke)
        }
        stroke.strokeCap = Paint.Cap.ROUND
    }

    // ------------------------------------------------------------ particles

    private fun floatingHearts(c: Canvas, t: Float) {
        for (i in 0 until 10) {
            val side = if (i % 2 == 0) -1f else 1f
            val y = rise(t, i, 0.25f, 1.6f, -2.4f)
            val progress = ((1.6f - y) / 4f).coerceIn(0f, 1f)
            val x = side * (0.95f + 0.7f * hash(i, 3)) + 0.12f * sin(t * 2f + i)
            val s = 0.14f + 0.12f * hash(i, 4)
            fill.color = if (i % 3 == 0) Color.rgb(255, 120, 170) else Color.rgb(240, 40, 80)
            fill.alpha = (255 * (1f - progress * progress)).toInt()
            c.drawPath(heart(x, y, s), fill)
        }
        fill.alpha = 255
    }

    private fun moneyRain(c: Canvas, t: Float) {
        for (i in 0 until 14) {
            val side = if (i % 2 == 0) -1f else 1f
            val x = side * (0.2f + 1.7f * hash(i, 5))
            val y = fall(t, i, 0.3f + 0.2f * hash(i, 6), -2.8f, 2.4f)
            val spin = abs(cos(t * 5f + i))
            coin(c, x, y, 0.17f, spin)
        }
    }

    private fun sparkles(c: Canvas, t: Float) {
        for (i in 0 until 14) {
            val a = 2f * PI.toFloat() * hash(i, 7)
            val r = 1.3f + 0.6f * hash(i, 8)
            val x = cos(a) * r * 1.1f
            val y = -0.4f + sin(a) * r
            val tw = twinkle(t, i)
            if (tw > 0.05f) sparkle(c, x, y, 0.26f * tw, if (i % 3 == 0) Color.rgb(255, 230, 120) else Color.WHITE)
        }
    }

    // --------------------------------------------------------------- helpers

    private val SIDES = floatArrayOf(-1f, 1f)

    /** Stable pseudo-random 0..1 for particle [i], channel [k]. */
    private fun hash(i: Int, k: Int): Float {
        val v = sin(i * 12.9898f + k * 78.233f) * 43758.547f
        return v - floor(v)
    }

    /** Particle y falling from [from] to [to], [speed] loops per second, looping. */
    private fun fall(t: Float, i: Int, speed: Float, from: Float, to: Float): Float {
        val p = t * speed + hash(i, 9)
        return from + (to - from) * (p - floor(p))
    }

    private fun rise(t: Float, i: Int, speed: Float, from: Float, to: Float) = fall(t, i, speed, from, to)

    /** 0..1 twinkle: short flashes at a per-particle phase. */
    private fun twinkle(t: Float, i: Int): Float {
        val p = t * (0.7f + 0.6f * hash(i, 10)) + hash(i, 11)
        val f = p - floor(p)
        return max(0f, sin(f * PI.toFloat() * 2f)).let { it * it }
    }

    private fun heart(cx: Float, cy: Float, s: Float) = Path().apply {
        moveTo(cx, cy + s * 0.9f)
        cubicTo(cx - s * 1.6f, cy - s * 0.2f, cx - s * 0.7f, cy - s * 1.4f, cx, cy - s * 0.5f)
        cubicTo(cx + s * 0.7f, cy - s * 1.4f, cx + s * 1.6f, cy - s * 0.2f, cx, cy + s * 0.9f)
        close()
    }

    private fun star(cx: Float, cy: Float, outer: Float, inner: Float, points: Int) = Path().apply {
        for (k in 0 until points * 2) {
            val r = if (k % 2 == 0) outer else inner
            val a = -PI.toFloat() / 2f + k * PI.toFloat() / points
            val x = cx + cos(a) * r
            val y = cy + sin(a) * r
            if (k == 0) moveTo(x, y) else lineTo(x, y)
        }
        close()
    }

    private fun drop(cx: Float, cy: Float, s: Float) = Path().apply {
        moveTo(cx, cy - s * 1.6f)
        cubicTo(cx + s, cy - s * 0.4f, cx + s, cy + s, cx, cy + s)
        cubicTo(cx - s, cy + s, cx - s, cy - s * 0.4f, cx, cy - s * 1.6f)
        close()
    }

    private fun sparkle(c: Canvas, cx: Float, cy: Float, s: Float, color: Int) {
        fill.color = color
        c.drawPath(Path().apply {
            moveTo(cx, cy - s)
            quadTo(cx, cy, cx + s, cy)
            quadTo(cx, cy, cx, cy + s)
            quadTo(cx, cy, cx - s, cy)
            quadTo(cx, cy, cx, cy - s)
            close()
        }, fill)
    }

    private fun gem(c: Canvas, cx: Float, cy: Float, r: Float, color: Int) {
        fill.shader = RadialGradient(cx - r * 0.3f, cy - r * 0.3f, r * 1.3f, Color.WHITE, color, Shader.TileMode.CLAMP)
        c.drawCircle(cx, cy, r, fill)
        fill.shader = null
    }

    private fun flower(c: Canvas, cx: Float, cy: Float, r: Float, color: Int) {
        fill.color = color
        for (k in 0 until 5) {
            val a = 2f * PI.toFloat() * k / 5 - PI.toFloat() / 2f
            c.drawCircle(cx + cos(a) * r * 0.55f, cy + sin(a) * r * 0.55f, r * 0.48f, fill)
        }
        fill.color = Color.rgb(255, 235, 120)
        c.drawCircle(cx, cy, r * 0.35f, fill)
    }

    /** A gold coin turning around its vertical axis ([spin] 0..1 = its visible width). */
    private fun coin(c: Canvas, cx: Float, cy: Float, r: Float, spin: Float) {
        val w = r * (0.15f + 0.85f * spin)
        fill.shader = LinearGradient(cx - w, cy - r, cx + w, cy + r, Color.rgb(255, 235, 130), Color.rgb(210, 150, 20), Shader.TileMode.CLAMP)
        c.drawOval(RectF(cx - w, cy - r, cx + w, cy + r), fill)
        fill.shader = null
        stroke.color = Color.rgb(180, 120, 10)
        stroke.strokeWidth = r * 0.12f
        c.drawOval(RectF(cx - w * 0.72f, cy - r * 0.72f, cx + w * 0.72f, cy + r * 0.72f), stroke)
        if (spin > 0.5f) {
            fill.color = Color.rgb(255, 245, 190)
            c.drawPath(star(cx, cy, r * 0.42f * spin, r * 0.18f * spin, 5), fill)
        }
    }
}
