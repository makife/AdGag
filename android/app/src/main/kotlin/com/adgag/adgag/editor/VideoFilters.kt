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
 *
 * Border decorations sit on [borderPoint]s: evenly spaced around the inset
 * rectangle with the four CORNERS shared by both edges, so nothing
 * overlaps or gets cut at a corner (the first version laid each edge on
 * its own grid — user-reported corner mismatches). Colours come from a
 * hash of the point's POSITION, so a corner looks the same from either
 * edge.
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
        vec2 bp = borderPoint(p, 0.11, 0.055);
        vec2 d = p - bp;
        float r = length(d);
        float a = atan(d.y, d.x);
        float petal = 0.05 * (0.45 + 0.55 * (0.5 + 0.5 * cos(5.0 * a)));
        vec3 petalColor = hash(bp) < 0.5 ? vec3(1.0, 0.55, 0.75) : vec3(1.0, 0.95, 0.97);
        vec3 col = c.rgb;
        if (r < petal) col = petalColor;
        if (r < 0.014) col = vec3(1.0, 0.82, 0.25);
        gl_FragColor = vec4(col, c.a);
    """),
    HEARTS("Hearts", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec2 bp = borderPoint(p, 0.1, 0.05);
        vec2 q = (p - bp) / 0.035;
        float k = q.x * q.x + q.y * q.y - 1.0;
        float h = k * k * k - q.x * q.x * q.y * q.y * q.y;
        vec3 col = c.rgb;
        if (h <= 0.0) col = hash(bp) < 0.5 ? vec3(0.95, 0.15, 0.35) : vec3(1.0, 0.45, 0.6);
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
    IVY("Ivy", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        float inset = 0.045;
        vec3 col = c.rgb;
        vec2 rel = abs(p - vec2(uAspect * 0.5, 0.5)) - vec2(uAspect * 0.5 - inset, 0.5 - inset);
        float sd = max(rel.x, rel.y);
        float wave = 0.006 * sin((p.x + p.y) * 70.0);
        if (abs(sd - wave) < 0.0035) col = vec3(0.2, 0.42, 0.16);
        vec2 bp = borderPoint(p, 0.06, inset);
        vec2 q = p - bp;
        float side = hash(bp) < 0.5 ? 1.0 : -1.0;
        bool horizontal = abs(bp.y - inset) < 0.001 || abs(bp.y - (1.0 - inset)) < 0.001;
        vec2 lq = horizontal ? vec2(q.x, q.y - side * 0.018) : vec2(q.x - side * 0.018, q.y);
        vec2 rad = horizontal ? vec2(0.011, 0.02) : vec2(0.02, 0.011);
        vec2 e = lq / rad;
        if (dot(e, e) < 1.0) col = mix(vec3(0.16, 0.45, 0.14), vec3(0.45, 0.75, 0.25), hash(bp + 0.5));
        gl_FragColor = vec4(col, c.a);
    """),
    BALLOONS("Balloons", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec2 bp = borderPoint(p, 0.14, 0.07);
        vec2 q = p - bp;
        vec3 bcol = palette(hash(bp));
        vec3 col = c.rgb;
        if (abs(q.x + 0.004 * sin(q.y * 120.0)) < 0.0018 && q.y < -0.04 && q.y > -0.068) col = vec3(0.95);
        vec2 knot = (q - vec2(0.0, -0.05)) / 0.006;
        if (dot(knot, knot) < 1.0) col = bcol * 0.8;
        vec2 e = q / vec2(0.038, 0.048);
        if (dot(e, e) < 1.0) {
            col = bcol;
            vec2 hl = (q - vec2(-0.012, 0.018)) / vec2(0.008, 0.013);
            if (dot(hl, hl) < 1.0) col = mix(bcol, vec3(1.0), 0.6);
        }
        gl_FragColor = vec4(col, c.a);
    """),
    STARS("Stars", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec2 bp = borderPoint(p, 0.1, 0.05);
        vec2 q = p - bp;
        float r = length(q);
        float a = atan(q.y, q.x) - 1.5708;
        float spike = pow(0.5 + 0.5 * cos(5.0 * a), 3.0);
        float radius = 0.036 * (0.42 + 0.58 * spike);
        float h = hash(bp);
        float twinkle = 0.75 + 0.25 * sin(uTime * 6.0 + h * 6.283);
        vec3 col = c.rgb;
        if (r < radius) col = mix(vec3(1.0, 0.85, 0.3), vec3(1.0), h < 0.5 ? 0.0 : 0.7) * twinkle;
        gl_FragColor = vec4(col, c.a);
    """),
    CONFETTI("Confetti", """
        vec4 c = tex(vUv);
        vec2 p = vec2(vUv.x * uAspect, vUv.y);
        vec2 cell = floor(p / 0.045);
        float h1 = rand(cell);
        float h2 = rand(cell + 17.0);
        float h3 = rand(cell + 41.0);
        vec2 center = (cell + vec2(0.2 + 0.6 * h1, 0.2 + 0.6 * h2)) * 0.045;
        float edgeDist = min(min(center.x, uAspect - center.x), min(center.y, 1.0 - center.y));
        vec3 col = c.rgb;
        if (edgeDist < 0.11 && h3 < 0.7) {
            vec2 q = p - center;
            float ang = h1 * 6.283 + uTime * 2.0 * (h2 - 0.5);
            vec2 rq = vec2(cos(ang) * q.x - sin(ang) * q.y, sin(ang) * q.x + cos(ang) * q.y);
            if (abs(rq.x) < 0.008 && abs(rq.y) < 0.004) col = palette(h3 / 0.7);
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
float hash(vec2 c) { return rand(floor(c * 1000.0 + 0.5)); }
vec3 palette(float h) {
    if (h < 0.25) return vec3(0.95, 0.25, 0.35);
    if (h < 0.5) return vec3(0.25, 0.6, 0.95);
    if (h < 0.75) return vec3(1.0, 0.8, 0.2);
    return vec3(0.6, 0.35, 0.95);
}
vec2 borderPoint(vec2 p, float spacing, float inset) {
    float w = uAspect - 2.0 * inset;
    float h = 1.0 - 2.0 * inset;
    float nx = max(1.0, floor(w / spacing + 0.5));
    float ny = max(1.0, floor(h / spacing + 0.5));
    float sx = w / nx;
    float sy = h / ny;
    float kx = clamp(floor((p.x - inset) / sx + 0.5), 0.0, nx);
    float ky = clamp(floor((p.y - inset) / sy + 0.5), 0.0, ny);
    vec2 c = vec2(inset + kx * sx, inset);
    float d = distance(p, c);
    vec2 c2 = vec2(uAspect - inset, inset + ky * sy);
    if (distance(p, c2) < d) { c = c2; d = distance(p, c2); }
    vec2 c3 = vec2(inset + kx * sx, 1.0 - inset);
    if (distance(p, c3) < d) { c = c3; d = distance(p, c3); }
    vec2 c4 = vec2(inset, inset + ky * sy);
    if (distance(p, c4) < d) { c = c4; }
    return c;
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

    private fun hash(x: Float, y: Float) = rand(floor(x * 1000f + 0.5f), floor(y * 1000f + 0.5f))

    private fun palette(h: Float): Rgb = when {
        h < 0.25f -> Rgb(0.95f, 0.25f, 0.35f)
        h < 0.5f -> Rgb(0.25f, 0.6f, 0.95f)
        h < 0.75f -> Rgb(1f, 0.8f, 0.2f)
        else -> Rgb(0.6f, 0.35f, 0.95f)
    }

    /** Mirrors the GLSL borderPoint(): nearest evenly spaced point on the inset rectangle, corners shared. */
    private fun borderPoint(px: Float, py: Float, spacing: Float, inset: Float, aspect: Float): Pair<Float, Float> {
        val w = aspect - 2f * inset
        val h = 1f - 2f * inset
        val nx = maxOf(1f, floor(w / spacing + 0.5f))
        val ny = maxOf(1f, floor(h / spacing + 0.5f))
        val sx = w / nx
        val sy = h / ny
        val kx = floor((px - inset) / sx + 0.5f).coerceIn(0f, nx)
        val ky = floor((py - inset) / sy + 0.5f).coerceIn(0f, ny)
        var cx = inset + kx * sx
        var cy = inset
        var d = hypot(px - cx, py - cy)
        fun consider(x: Float, y: Float) {
            val dd = hypot(px - x, py - y)
            if (dd < d) { cx = x; cy = y; d = dd }
        }
        consider(aspect - inset, inset + ky * sy)
        consider(inset + kx * sx, 1f - inset)
        consider(inset, inset + ky * sy)
        return cx to cy
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
                val (bx, by) = borderPoint(px, v, 0.11f, 0.055f, aspect)
                val dx = px - bx
                val dy = v - by
                val r = hypot(dx, dy)
                val a = atan2(dy, dx)
                val petal = 0.05f * (0.45f + 0.55f * (0.5f + 0.5f * cos(5f * a)))
                when {
                    r < 0.014f -> Rgb(1f, 0.82f, 0.25f)
                    r < petal -> if (hash(bx, by) < 0.5f) Rgb(1f, 0.55f, 0.75f) else Rgb(1f, 0.95f, 0.97f)
                    else -> tex(u, v)
                }
            }
            VideoFilter.HEARTS -> {
                val px = u * aspect
                val (bx, by) = borderPoint(px, v, 0.1f, 0.05f, aspect)
                val qx = (px - bx) / 0.035f
                val qy = (v - by) / 0.035f
                val k = qx * qx + qy * qy - 1f
                val hh = k * k * k - qx * qx * qy * qy * qy
                if (hh <= 0f) {
                    if (hash(bx, by) < 0.5f) Rgb(0.95f, 0.15f, 0.35f) else Rgb(1f, 0.45f, 0.6f)
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
            VideoFilter.IVY -> {
                val px = u * aspect
                val inset = 0.045f
                var col = tex(u, v)
                val relX = abs(px - aspect * 0.5f) - (aspect * 0.5f - inset)
                val relY = abs(v - 0.5f) - (0.5f - inset)
                val sd = maxOf(relX, relY)
                val wave = 0.006f * sin((px + v) * 70f)
                if (abs(sd - wave) < 0.0035f) col = Rgb(0.2f, 0.42f, 0.16f)
                val (bx, by) = borderPoint(px, v, 0.06f, inset, aspect)
                val qx = px - bx
                val qy = v - by
                val side = if (hash(bx, by) < 0.5f) 1f else -1f
                val horizontal = abs(by - inset) < 0.001f || abs(by - (1f - inset)) < 0.001f
                val lx = if (horizontal) qx else qx - side * 0.018f
                val ly = if (horizontal) qy - side * 0.018f else qy
                val rx = if (horizontal) 0.011f else 0.02f
                val ry = if (horizontal) 0.02f else 0.011f
                if ((lx / rx) * (lx / rx) + (ly / ry) * (ly / ry) < 1f) {
                    col = mix(Rgb(0.16f, 0.45f, 0.14f), Rgb(0.45f, 0.75f, 0.25f), hash(bx + 0.5f, by + 0.5f))
                }
                col
            }
            VideoFilter.BALLOONS -> {
                val px = u * aspect
                val (bx, by) = borderPoint(px, v, 0.14f, 0.07f, aspect)
                val qx = px - bx
                val qy = v - by
                val bcol = palette(hash(bx, by))
                var col = tex(u, v)
                if (abs(qx + 0.004f * sin(qy * 120f)) < 0.0018f && qy < -0.04f && qy > -0.068f) col = Rgb(0.95f, 0.95f, 0.95f)
                val kx = qx / 0.006f
                val ky = (qy + 0.05f) / 0.006f
                if (kx * kx + ky * ky < 1f) col = Rgb(bcol.r * 0.8f, bcol.g * 0.8f, bcol.b * 0.8f)
                val ex = qx / 0.038f
                val ey = qy / 0.048f
                if (ex * ex + ey * ey < 1f) {
                    col = bcol
                    val hx = (qx + 0.012f) / 0.008f
                    val hy = (qy - 0.018f) / 0.013f
                    if (hx * hx + hy * hy < 1f) col = mix(bcol, Rgb(1f, 1f, 1f), 0.6f)
                }
                col
            }
            VideoFilter.STARS -> {
                val px = u * aspect
                val (bx, by) = borderPoint(px, v, 0.1f, 0.05f, aspect)
                val qx = px - bx
                val qy = v - by
                val r = hypot(qx, qy)
                val a = atan2(qy, qx) - 1.5708f
                val base = 0.5f + 0.5f * cos(5f * a)
                val spike = base * base * base
                val radius = 0.036f * (0.42f + 0.58f * spike)
                val h = hash(bx, by)
                val twinkle = 0.75f + 0.25f * sin(T * 6f + h * 6.283f)
                if (r < radius) {
                    val s = mix(Rgb(1f, 0.85f, 0.3f), Rgb(1f, 1f, 1f), if (h < 0.5f) 0f else 0.7f)
                    Rgb(s.r * twinkle, s.g * twinkle, s.b * twinkle)
                } else {
                    tex(u, v)
                }
            }
            VideoFilter.CONFETTI -> {
                val px = u * aspect
                val cx = floor(px / 0.045f)
                val cy = floor(v / 0.045f)
                val h1 = rand(cx, cy)
                val h2 = rand(cx + 17f, cy + 17f)
                val h3 = rand(cx + 41f, cy + 41f)
                val centerX = (cx + 0.2f + 0.6f * h1) * 0.045f
                val centerY = (cy + 0.2f + 0.6f * h2) * 0.045f
                val edgeDist = min(min(centerX, aspect - centerX), min(centerY, 1f - centerY))
                var col = tex(u, v)
                if (edgeDist < 0.11f && h3 < 0.7f) {
                    val qx = px - centerX
                    val qy = v - centerY
                    val ang = h1 * 6.283f + T * 2f * (h2 - 0.5f)
                    val rx = cos(ang) * qx - sin(ang) * qy
                    val ry = sin(ang) * qx + cos(ang) * qy
                    if (abs(rx) < 0.008f && abs(ry) < 0.004f) col = palette(h3 / 0.7f)
                }
                col
            }
        }
        fun ch(x: Float) = (x.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
        return (0xFF shl 24) or (ch(c.r) shl 16) or (ch(c.g) shl 8) or ch(c.b)
    }
}
