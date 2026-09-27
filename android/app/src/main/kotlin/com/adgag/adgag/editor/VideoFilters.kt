package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Bitmap
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

/**
 * Whole-video look effects ("Effects" tool). These are NOT AR effects (no
 * face/scene tracking) — they're per-frame image effects on the recorded
 * video: colour looks, lens/TV distortions, and decorative borders drawn
 * procedurally (no bitmap assets, so they fit any output size).
 *
 * Every effect exists twice, kept deliberately line-for-line parallel:
 * - [fragment]: a GLSL ES 1.00 fragment shader body, run by Media3 both in
 *   the live preview (ExoPlayer.setVideoEffects) and in the export
 *   (Transformer) through [FilterEffect];
 * - [FilterCpu]: the same formula in Kotlin, used only to draw the picker's
 *   thumbnails from a frame of the user's own clip.
 * Coordinates: uv in 0..1 with y UP (GL convention); p = (uv.x * aspect,
 * uv.y) measures in "frame heights" so shapes stay round on any aspect.
 */
enum class VideoFilter(val label: String, val fragment: String?) {
    NONE("Original", null),
    BW("B&W", """
        vec4 c = tex(vUv);
        gl_FragColor = vec4(vec3(luma(c.rgb)), c.a);
    """),
    SEPIA("Sepia", """
        vec4 c = tex(vUv);
        gl_FragColor = vec4(sepia(c.rgb), c.a);
    """),
    VINTAGE("Vintage", """
        vec4 c = tex(vUv);
        vec3 col = mix(c.rgb, sepia(c.rgb), 0.6);
        col = col * 0.82 + 0.1;
        col *= vignette(vUv, 0.6);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a);
    """),
    COOL("Cool", """
        vec4 c = tex(vUv);
        gl_FragColor = vec4(clamp(c.rgb * vec3(0.88, 1.0, 1.18), 0.0, 1.0), c.a);
    """),
    WARM("Warm", """
        vec4 c = tex(vUv);
        gl_FragColor = vec4(clamp(c.rgb * vec3(1.15, 1.02, 0.84), 0.0, 1.0), c.a);
    """),
    VIVID("Vivid", """
        vec4 c = tex(vUv);
        float l = luma(c.rgb);
        gl_FragColor = vec4(clamp(mix(vec3(l), c.rgb, 1.7), 0.0, 1.0), c.a);
    """),
    INVERT("Negative", """
        vec4 c = tex(vUv);
        gl_FragColor = vec4(1.0 - c.rgb, c.a);
    """),
    FISHEYE("Fisheye", """
        vec2 p = vUv * 2.0 - 1.0;
        p.x *= uAspect;
        float maxR = length(vec2(uAspect, 1.0));
        float rn = length(p) / maxR;
        vec2 q = p * (0.55 + 0.45 * rn * rn);
        q.x /= uAspect;
        vec4 c = tex(q * 0.5 + 0.5);
        float edge = 1.0 - smoothstep(0.82, 1.0, rn);
        gl_FragColor = vec4(c.rgb * edge, c.a);
    """),
    OLD_TV("Old TV", """
        vec4 c = tex(vUv);
        vec3 col = vec3(luma(c.rgb)) * 1.1;
        col *= 0.8 + 0.2 * sin(vUv.y * 1400.0);
        float n = rand(vUv * 500.0 + uTime);
        col += (n - 0.5) * 0.18;
        col *= 0.94 + 0.06 * sin(uTime * 50.0);
        col *= vignette(vUv, 0.8);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a);
    """),
    STATIC("Static", """
        vec4 c = tex(vUv);
        float n = rand(floor(vUv * vec2(270.0, 480.0)) + fract(uTime * 13.0) * 100.0);
        float band = step(0.93, rand(vec2(floor(vUv.y * 40.0), floor(uTime * 12.0))));
        vec3 col = mix(c.rgb, vec3(n), 0.45 + 0.3 * band);
        gl_FragColor = vec4(col, c.a);
    """),
    VHS("VHS", """
        float line = floor(vUv.y * 90.0);
        float t = floor(uTime * 10.0);
        float jump = step(0.95, rand(vec2(line, t)));
        vec2 uv = vUv + vec2((rand(vec2(t, line)) - 0.5) * 0.04 * jump, 0.0);
        float off = 0.005;
        vec4 c = tex(uv);
        vec3 col = vec3(tex(uv + vec2(off, 0.0)).r, c.g, tex(uv - vec2(off, 0.0)).b);
        col *= 0.93 + 0.07 * sin(vUv.y * 900.0);
        col += (rand(vUv * 300.0 + uTime) - 0.5) * 0.08;
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a);
    """),
    GLITCH("Glitch", """
        float t = floor(uTime * 8.0);
        float on = step(0.55, rand(vec2(t, 3.0)));
        float shift = (rand(vec2(floor(vUv.y * 18.0), t)) - 0.5) * 0.12 * on;
        vec2 uv = vUv + vec2(shift, 0.0);
        float split = 0.012 + 0.02 * on;
        vec4 c = tex(uv);
        vec3 col = vec3(tex(uv + vec2(split, 0.0)).r, c.g, tex(uv - vec2(split, 0.0)).b);
        gl_FragColor = vec4(col, c.a);
    """),
    PIXELATE("Pixel", """
        vec2 cells = vec2(36.0, 36.0 / uAspect);
        vec2 uv = (floor(vUv * cells) + 0.5) / cells;
        gl_FragColor = tex(uv);
    """),
    MIRROR("Mirror", """
        vec2 uv = vec2(vUv.x < 0.5 ? vUv.x : 1.0 - vUv.x, vUv.y);
        gl_FragColor = tex(uv);
    """),
    FLOWERS("Flowers", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec3 bc = borderCenter(p, 0.11, 0.055);
        vec2 d = p - bc.xy;
        float r = length(d);
        float a = atan(d.y, d.x);
        float petal = 0.05 * (0.45 + 0.55 * (0.5 + 0.5 * cos(5.0 * a)));
        vec3 petalColor = mod(bc.z, 2.0) < 1.0 ? vec3(1.0, 0.55, 0.75) : vec3(1.0, 0.95, 0.97);
        vec3 col = c.rgb;
        if (r < petal) col = petalColor;
        if (r < 0.014) col = vec3(1.0, 0.82, 0.25);
        gl_FragColor = vec4(col, c.a);
    """),
    HEARTS("Hearts", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec3 bc = borderCenter(p, 0.1, 0.05);
        vec2 q = (p - bc.xy) / 0.035;
        float k = q.x * q.x + q.y * q.y - 1.0;
        float h = k * k * k - q.x * q.x * q.y * q.y * q.y;
        vec3 col = c.rgb;
        if (h <= 0.0) col = mod(bc.z, 2.0) < 1.0 ? vec3(0.95, 0.15, 0.35) : vec3(1.0, 0.45, 0.6);
        gl_FragColor = vec4(col, c.a);
    """),
    FILM("Film", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec3 col = mix(c.rgb, sepia(c.rgb), 0.35);
        float bar = 0.075;
        float fromEdge = min(p.x, uAspect - p.x);
        if (fromEdge < bar) {
            col = vec3(0.05);
            float hy = abs(fract(p.y / 0.055) - 0.5);
            float hx = abs(fromEdge - bar * 0.5);
            if (hy < 0.2 && hx < bar * 0.22) col = vec3(0.92);
        }
        gl_FragColor = vec4(col, c.a);
    """),
}

/** Shared GLSL: precision, inputs and helpers every [VideoFilter.fragment] body can use. */
internal const val FilterShaderHeader = """
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D uTexSampler;
uniform float uTime;
uniform float uAspect;
varying vec2 vUv;
float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3 sepia(vec3 c) {
    return clamp(vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131))), 0.0, 1.0);
}
float vignette(vec2 uv, float amount) { return 1.0 - smoothstep(0.35, 0.85, distance(uv, vec2(0.5))) * amount; }
vec4 tex(vec2 uv) { return texture2D(uTexSampler, clamp(uv, 0.0, 1.0)); }
vec3 borderCenter(vec2 p, float spacing, float inset) {
    float ix = floor(p.x / spacing);
    float iy = floor(p.y / spacing);
    vec2 c = vec2((ix + 0.5) * spacing, inset);
    float idx = ix;
    float d = distance(p, c);
    vec2 c2 = vec2((ix + 0.5) * spacing, 1.0 - inset);
    if (distance(p, c2) < d) { c = c2; d = distance(p, c2); idx = ix + 1.0; }
    vec2 c3 = vec2(inset, (iy + 0.5) * spacing);
    if (distance(p, c3) < d) { c = c3; d = distance(p, c3); idx = iy; }
    vec2 c4 = vec2(uAspect - inset, (iy + 0.5) * spacing);
    if (distance(p, c4) < d) { c = c4; d = distance(p, c4); idx = iy + 1.0; }
    return vec3(c, idx);
}
"""

internal const val FilterVertexShader = """
attribute vec4 aFramePosition;
varying vec2 vUv;
void main() {
    gl_Position = aFramePosition;
    vUv = (aFramePosition.xy + 1.0) * 0.5;
}
"""

fun filterFragmentShader(filter: VideoFilter): String =
    FilterShaderHeader + "void main() {\n" + (filter.fragment ?: "gl_FragColor = tex(vUv);") + "\n}\n"

/** The Media3 effect for [filter] — used by the preview player and the export alike. */
@UnstableApi
class FilterEffect(private val filter: VideoFilter) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        FilterShaderProgram(filterFragmentShader(filter))
}

/**
 * Full-frame pass running one filter's fragment shader. Built on Media3's
 * BaseGlShaderProgram exactly like its own ColorLutShaderProgram (checked
 * in the media3-effect 1.11.0 sources); uniforms are set with the
 * *IfPresent* setter because GLSL compilers strip unused uniforms and the
 * plain setters throw on a missing one.
 */
@UnstableApi
private class FilterShaderProgram(fragmentShader: String) :
    BaseGlShaderProgram(/* useHighPrecisionColorComponents = */ false, /* texturePoolCapacity = */ 1) {

    private val glProgram: GlProgram = try {
        GlProgram(FilterVertexShader, fragmentShader)
    } catch (e: GlUtil.GlException) {
        throw VideoFrameProcessingException(e)
    }
    private var aspect = 9f / 16f

    init {
        glProgram.setBufferAttribute(
            "aFramePosition",
            GlUtil.getNormalizedCoordinateBounds(),
            GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
        )
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        if (inputHeight > 0) aspect = inputWidth.toFloat() / inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            glProgram.use()
            glProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, /* texUnitIndex = */ 0)
            glProgram.setFloatsUniformIfPresent("uTime", floatArrayOf((presentationTimeUs % 3_600_000_000L) / 1_000_000f))
            glProgram.setFloatsUniformIfPresent("uAspect", floatArrayOf(aspect))
            glProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            glProgram.delete()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }
}

/**
 * CPU twin of the shaders, for the picker thumbnails only (a ~90px frame
 * of the user's own clip). Mirrors each GLSL body above; t is a fixed
 * moment so the animated effects show a representative still.
 */
object FilterCpu {
    private const val T = 0.37f

    fun render(filter: VideoFilter, src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val input = IntArray(w * h)
        src.getPixels(input, 0, w, 0, 0, w, h)
        val out = IntArray(w * h)
        val aspect = w.toFloat() / h
        for (py in 0 until h) {
            for (px in 0 until w) {
                val u = (px + 0.5f) / w
                val v = 1f - (py + 0.5f) / h // y up, like GL
                out[py * w + px] = shade(filter, u, v, aspect, input, w, h)
            }
        }
        return Bitmap.createBitmap(out, w, h, Bitmap.Config.ARGB_8888)
    }

    private class Rgb(var r: Float, var g: Float, var b: Float)

    private fun sample(u: Float, v: Float, input: IntArray, w: Int, h: Int): Rgb {
        val x = (u.coerceIn(0f, 1f) * (w - 1)).toInt()
        val y = ((1f - v.coerceIn(0f, 1f)) * (h - 1)).toInt()
        val c = input[y * w + x]
        return Rgb(((c shr 16) and 0xFF) / 255f, ((c shr 8) and 0xFF) / 255f, (c and 0xFF) / 255f)
    }

    private fun fract(x: Float) = x - floor(x)
    private fun rand(x: Float, y: Float) = fract(sin(x * 12.9898f + y * 78.233f) * 43758.5453f)
    private fun luma(c: Rgb) = c.r * 0.299f + c.g * 0.587f + c.b * 0.114f
    private fun smoothstep(e0: Float, e1: Float, x: Float): Float {
        val t = ((x - e0) / (e1 - e0)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }
    private fun vignette(u: Float, v: Float, amount: Float) =
        1f - smoothstep(0.35f, 0.85f, hypot(u - 0.5f, v - 0.5f)) * amount
    private fun sepia(c: Rgb) = Rgb(
        (c.r * 0.393f + c.g * 0.769f + c.b * 0.189f).coerceIn(0f, 1f),
        (c.r * 0.349f + c.g * 0.686f + c.b * 0.168f).coerceIn(0f, 1f),
        (c.r * 0.272f + c.g * 0.534f + c.b * 0.131f).coerceIn(0f, 1f),
    )
    private fun mix(a: Rgb, b: Rgb, k: Float) = Rgb(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)

    /** Mirrors the GLSL borderCenter(): nearest decoration centre on the frame's edge, plus its index. */
    private fun borderCenter(px: Float, py: Float, spacing: Float, inset: Float, aspect: Float): Triple<Float, Float, Float> {
        val ix = floor(px / spacing)
        val iy = floor(py / spacing)
        var cx = (ix + 0.5f) * spacing
        var cy = inset
        var idx = ix
        var d = hypot(px - cx, py - cy)
        fun consider(x: Float, y: Float, i: Float) {
            val dd = hypot(px - x, py - y)
            if (dd < d) { cx = x; cy = y; d = dd; idx = i }
        }
        consider((ix + 0.5f) * spacing, 1f - inset, ix + 1f)
        consider(inset, (iy + 0.5f) * spacing, iy)
        consider(aspect - inset, (iy + 0.5f) * spacing, iy + 1f)
        return Triple(cx, cy, idx)
    }

    private fun shade(f: VideoFilter, u: Float, v: Float, aspect: Float, input: IntArray, w: Int, h: Int): Int {
        fun tex(x: Float, y: Float) = sample(x, y, input, w, h)
        val c: Rgb = when (f) {
            VideoFilter.NONE -> tex(u, v)
            VideoFilter.BW -> tex(u, v).let { val l = luma(it); Rgb(l, l, l) }
            VideoFilter.SEPIA -> sepia(tex(u, v))
            VideoFilter.VINTAGE -> {
                val s = tex(u, v)
                val m = mix(s, sepia(s), 0.6f)
                val vg = vignette(u, v, 0.6f)
                Rgb((m.r * 0.82f + 0.1f) * vg, (m.g * 0.82f + 0.1f) * vg, (m.b * 0.82f + 0.1f) * vg)
            }
            VideoFilter.COOL -> tex(u, v).let { Rgb(it.r * 0.88f, it.g, it.b * 1.18f) }
            VideoFilter.WARM -> tex(u, v).let { Rgb(it.r * 1.15f, it.g * 1.02f, it.b * 0.84f) }
            VideoFilter.VIVID -> tex(u, v).let { val l = luma(it); Rgb(l + (it.r - l) * 1.7f, l + (it.g - l) * 1.7f, l + (it.b - l) * 1.7f) }
            VideoFilter.INVERT -> tex(u, v).let { Rgb(1f - it.r, 1f - it.g, 1f - it.b) }
            VideoFilter.FISHEYE -> {
                val x = (u * 2f - 1f) * aspect
                val y = v * 2f - 1f
                val maxR = hypot(aspect, 1f)
                val rn = hypot(x, y) / maxR
                val k = 0.55f + 0.45f * rn * rn
                val s = tex((x * k / aspect) * 0.5f + 0.5f, (y * k) * 0.5f + 0.5f)
                val edge = 1f - smoothstep(0.82f, 1f, rn)
                Rgb(s.r * edge, s.g * edge, s.b * edge)
            }
            VideoFilter.OLD_TV -> {
                var l = luma(tex(u, v)) * 1.1f
                l *= 0.8f + 0.2f * sin(v * 1400f)
                l += (rand(u * 500f + T, v * 500f + T) - 0.5f) * 0.18f
                l *= 0.94f + 0.06f * sin(T * 50f)
                l *= vignette(u, v, 0.8f)
                Rgb(l, l, l)
            }
            VideoFilter.STATIC -> {
                val s = tex(u, v)
                val n = rand(floor(u * 270f) + fract(T * 13f) * 100f, floor(v * 480f) + fract(T * 13f) * 100f)
                val band = if (rand(floor(v * 40f), floor(T * 12f)) >= 0.93f) 1f else 0f
                mix(s, Rgb(n, n, n), 0.45f + 0.3f * band)
            }
            VideoFilter.VHS -> {
                val line = floor(v * 90f)
                val t = floor(T * 10f)
                val jump = if (rand(line, t) >= 0.95f) 1f else 0f
                val uu = u + (rand(t, line) - 0.5f) * 0.04f * jump
                val off = 0.005f
                val s = tex(uu, v)
                val scan = 0.93f + 0.07f * sin(v * 900f)
                val n = (rand(u * 300f + T, v * 300f + T) - 0.5f) * 0.08f
                Rgb(tex(uu + off, v).r * scan + n, s.g * scan + n, tex(uu - off, v).b * scan + n)
            }
            VideoFilter.GLITCH -> {
                val t = floor(T * 8f)
                val on = if (rand(t, 3f) >= 0.55f) 1f else 0f
                val shift = (rand(floor(v * 18f), t) - 0.5f) * 0.12f * on
                val uu = u + shift
                val split = 0.012f + 0.02f * on
                Rgb(tex(uu + split, v).r, tex(uu, v).g, tex(uu - split, v).b)
            }
            VideoFilter.PIXELATE -> {
                val cx = 36f
                val cy = 36f / aspect
                tex((floor(u * cx) + 0.5f) / cx, (floor(v * cy) + 0.5f) / cy)
            }
            VideoFilter.MIRROR -> tex(if (u < 0.5f) u else 1f - u, v)
            VideoFilter.FLOWERS -> {
                val px = u * aspect
                val (bx, by, idx) = borderCenter(px, v, 0.11f, 0.055f, aspect)
                val dx = px - bx
                val dy = v - by
                val r = hypot(dx, dy)
                val a = atan2(dy, dx)
                val petal = 0.05f * (0.45f + 0.55f * (0.5f + 0.5f * cos(5f * a)))
                when {
                    r < 0.014f -> Rgb(1f, 0.82f, 0.25f)
                    r < petal -> if (idx.mod(2f) < 1f) Rgb(1f, 0.55f, 0.75f) else Rgb(1f, 0.95f, 0.97f)
                    else -> tex(u, v)
                }
            }
            VideoFilter.HEARTS -> {
                val px = u * aspect
                val (bx, by, idx) = borderCenter(px, v, 0.1f, 0.05f, aspect)
                val qx = (px - bx) / 0.035f
                val qy = (v - by) / 0.035f
                val k = qx * qx + qy * qy - 1f
                val hh = k * k * k - qx * qx * qy * qy * qy
                if (hh <= 0f) {
                    if (idx.mod(2f) < 1f) Rgb(0.95f, 0.15f, 0.35f) else Rgb(1f, 0.45f, 0.6f)
                } else {
                    tex(u, v)
                }
            }
            VideoFilter.FILM -> {
                val px = u * aspect
                val bar = 0.075f
                val fromEdge = min(px, aspect - px)
                if (fromEdge < bar) {
                    val hy = abs(fract(v / 0.055f) - 0.5f)
                    val hx = abs(fromEdge - bar * 0.5f)
                    if (hy < 0.2f && hx < bar * 0.22f) Rgb(0.92f, 0.92f, 0.92f) else Rgb(0.05f, 0.05f, 0.05f)
                } else {
                    val s = tex(u, v)
                    mix(s, sepia(s), 0.35f)
                }
            }
        }
        fun ch(x: Float) = (x.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
        return (0xFF shl 24) or (ch(c.r) shl 16) or (ch(c.g) shl 8) or ch(c.b)
    }
}
