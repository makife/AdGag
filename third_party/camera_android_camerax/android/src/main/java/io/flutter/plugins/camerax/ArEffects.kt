// ADGAG PATCH — the live AR effects' artwork (see AdGagAr.kt).
package io.flutter.plugins.camerax

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader

/**
 * Every effect is drawn procedurally in FACE UNITS (AdGagAr's face frame):
 * origin between the eyes, 1 = the distance between the eyes, +y down the
 * face. Eyes sit at (±0.5, 0); the nose base and mouth come from the face
 * itself ([FaceGeom.toLocal]). No bitmaps: nothing to license, sharp at
 * any size.
 *
 * All artwork is left-right SYMMETRIC on purpose: the front camera's
 * preview is mirrored but its recording isn't, so anything asymmetric
 * (text!) would read backwards in one of them.
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

    fun draw(c: Canvas, id: String, face: FaceGeom) {
        // Reset shaders left over from the previous effect/face.
        fill.shader = null
        stroke.shader = null
        when (id) {
            "sunglasses" -> sunglasses(c)
            "crown" -> crown(c)
            "mustache" -> mustache(c, face)
            "clown" -> clownNose(c, face)
            "party" -> partyHat(c)
            "heart_eyes" -> heartEyes(c)
            "halo" -> halo(c)
            "puppy" -> puppy(c, face)
        }
    }

    private fun sunglasses(c: Canvas) {
        for (side in floatArrayOf(-1f, 1f)) {
            val cx = 0.52f * side
            val lens = RectF(cx - 0.42f, -0.24f, cx + 0.42f, 0.3f)
            fill.shader = LinearGradient(0f, -0.24f, 0f, 0.3f, Color.rgb(30, 30, 40), Color.rgb(5, 5, 10), Shader.TileMode.CLAMP)
            c.drawRoundRect(lens, 0.2f, 0.2f, fill)
            fill.shader = null
            stroke.color = Color.BLACK
            stroke.strokeWidth = 0.07f
            c.drawRoundRect(lens, 0.2f, 0.2f, stroke)
            // Shine.
            fill.color = Color.argb(150, 255, 255, 255)
            c.drawPath(Path().apply {
                moveTo(cx - 0.3f, -0.14f); lineTo(cx - 0.12f, -0.14f); lineTo(cx - 0.3f, 0.12f); close()
            }, fill)
        }
        stroke.color = Color.BLACK
        stroke.strokeWidth = 0.08f
        c.drawLine(-0.1f, -0.12f, 0.1f, -0.12f, stroke) // bridge
        c.drawLine(-0.94f, -0.12f, -1.2f, -0.18f, stroke) // temples
        c.drawLine(0.94f, -0.12f, 1.2f, -0.18f, stroke)
    }

    private fun crown(c: Canvas) {
        val gold = LinearGradient(0f, -2.0f, 0f, -1.2f, Color.rgb(255, 224, 102), Color.rgb(214, 150, 20), Shader.TileMode.CLAMP)
        val path = Path().apply {
            moveTo(-0.8f, -1.2f)
            lineTo(-0.8f, -1.95f)
            lineTo(-0.4f, -1.55f)
            lineTo(0f, -2.1f)
            lineTo(0.4f, -1.55f)
            lineTo(0.8f, -1.95f)
            lineTo(0.8f, -1.2f)
            close()
        }
        fill.shader = gold
        c.drawPath(path, fill)
        fill.shader = null
        stroke.color = Color.rgb(150, 100, 10)
        stroke.strokeWidth = 0.05f
        c.drawPath(path, stroke)
        fill.color = Color.rgb(255, 240, 150)
        for (x in floatArrayOf(-0.8f, 0f, 0.8f)) c.drawCircle(x, if (x == 0f) -2.12f else -1.97f, 0.09f, fill)
        fill.color = Color.rgb(220, 30, 60)
        c.drawCircle(0f, -1.4f, 0.13f, fill)
        fill.color = Color.rgb(40, 110, 230)
        c.drawCircle(-0.48f, -1.36f, 0.09f, fill)
        c.drawCircle(0.48f, -1.36f, 0.09f, fill)
    }

    private fun mustache(c: Canvas, face: FaceGeom) {
        val nose = face.toLocal(face.nose)
        val mouth = face.toLocal(face.mouth)
        // Between the nose base and the upper lip.
        val y = nose.y + (mouth.y - nose.y) * 0.3f
        val half = Path().apply {
            moveTo(0f, y - 0.05f)
            cubicTo(0.18f, y - 0.2f, 0.45f, y - 0.16f, 0.55f, y + 0.02f)
            cubicTo(0.62f, y + 0.12f, 0.74f, y + 0.12f, 0.8f, y - 0.02f)
            cubicTo(0.76f, y + 0.24f, 0.5f, y + 0.26f, 0.35f, y + 0.12f)
            cubicTo(0.22f, y + 0.02f, 0.1f, y + 0.08f, 0f, y + 0.12f)
            close()
        }
        fill.color = Color.rgb(45, 28, 18)
        c.drawPath(half, fill)
        c.save()
        c.scale(-1f, 1f)
        c.drawPath(half, fill)
        c.restore()
    }

    private fun clownNose(c: Canvas, face: FaceGeom) {
        val nose = face.toLocal(face.nose)
        val cy = nose.y - 0.08f
        fill.shader = RadialGradient(-0.08f, cy - 0.1f, 0.34f, Color.rgb(255, 90, 90), Color.rgb(190, 0, 20), Shader.TileMode.CLAMP)
        c.drawCircle(0f, cy, 0.27f, fill)
        fill.shader = null
        fill.color = Color.argb(200, 255, 255, 255)
        c.drawOval(RectF(-0.14f, cy - 0.18f, -0.02f, cy - 0.08f), fill)
    }

    private fun partyHat(c: Canvas) {
        val hat = Path().apply { moveTo(-0.6f, -1.2f); lineTo(0f, -2.6f); lineTo(0.6f, -1.2f); close() }
        fill.color = Color.rgb(22, 197, 192) // brand turquoise
        c.drawPath(hat, fill)
        c.save()
        c.clipPath(hat)
        fill.color = Color.rgb(255, 214, 64)
        var y = -2.5f
        while (y < -1.1f) {
            c.drawRect(-1f, y, 1f, y + 0.12f, fill)
            y += 0.3f
        }
        c.restore()
        fill.color = Color.rgb(255, 90, 140)
        c.drawCircle(0f, -2.62f, 0.16f, fill)
        stroke.color = Color.WHITE
        stroke.strokeWidth = 0.05f
        c.drawLine(-0.62f, -1.2f, 0.62f, -1.2f, stroke)
    }

    private fun heartEyes(c: Canvas) {
        for (side in floatArrayOf(-1f, 1f)) {
            val cx = 0.5f * side
            val s = 0.34f
            val heart = Path().apply {
                moveTo(cx, 0.1f + s * 0.9f)
                cubicTo(cx - s * 1.6f, 0.1f - s * 0.2f, cx - s * 0.7f, 0.1f - s * 1.4f, cx, 0.1f - s * 0.5f)
                cubicTo(cx + s * 0.7f, 0.1f - s * 1.4f, cx + s * 1.6f, 0.1f - s * 0.2f, cx, 0.1f + s * 0.9f)
                close()
            }
            fill.color = Color.rgb(235, 30, 70)
            c.drawPath(heart, fill)
            fill.color = Color.argb(170, 255, 255, 255)
            c.drawCircle(cx - s * 0.45f, 0.1f - s * 0.45f, s * 0.14f, fill)
        }
    }

    private fun halo(c: Canvas) {
        val ring = RectF(-0.8f, -2.1f, 0.8f, -1.75f)
        stroke.color = Color.argb(90, 255, 230, 120)
        stroke.strokeWidth = 0.28f
        c.drawOval(ring, stroke)
        stroke.color = Color.rgb(255, 215, 70)
        stroke.strokeWidth = 0.11f
        c.drawOval(ring, stroke)
        stroke.color = Color.argb(220, 255, 250, 220)
        stroke.strokeWidth = 0.035f
        c.drawOval(ring, stroke)
    }

    private fun puppy(c: Canvas, face: FaceGeom) {
        for (side in floatArrayOf(-1f, 1f)) {
            c.save()
            c.translate(1.05f * side, -0.95f)
            c.rotate(-18f * side)
            fill.color = Color.rgb(120, 75, 40)
            c.drawOval(RectF(-0.32f, -0.55f, 0.32f, 0.75f), fill)
            fill.color = Color.rgb(230, 150, 150)
            c.drawOval(RectF(-0.16f, -0.3f, 0.16f, 0.5f), fill)
            c.restore()
        }
        val nose = face.toLocal(face.nose)
        val cy = nose.y - 0.1f
        fill.color = Color.rgb(25, 20, 20)
        c.drawOval(RectF(-0.24f, cy - 0.16f, 0.24f, cy + 0.14f), fill)
        fill.color = Color.argb(160, 255, 255, 255)
        c.drawOval(RectF(-0.12f, cy - 0.12f, 0f, cy - 0.04f), fill)
        val mouth = face.toLocal(face.mouth)
        fill.color = Color.rgb(240, 90, 110)
        c.drawRoundRect(RectF(-0.16f, mouth.y - 0.08f, 0.16f, mouth.y + 0.42f), 0.16f, 0.16f, fill)
        stroke.color = Color.rgb(200, 50, 70)
        stroke.strokeWidth = 0.03f
        c.drawLine(0f, mouth.y - 0.02f, 0f, mouth.y + 0.26f, stroke)
    }
}
