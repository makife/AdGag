package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.util.LruCache
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Animated stickers ("Stickers" tool). Media3 itself has no sticker/GIF
 * library — only the overlay plumbing — so the stickers are Google's Noto
 * Animated Emoji (CC BY 4.0, assets/stickers/LICENSE.txt), pre-packed
 * offline into one sprite sheet per sticker (frames resampled to a uniform
 * 50ms step, 192px, WebP) + assets/stickers/stickers.json. A sprite sheet
 * lets preview AND export draw ANY frame at ANY time — no animated-image
 * decoder, which on Android can't seek (AnimatedImageDrawable runs on its
 * own clock). The iOS editor uses the very same files.
 *
 * Geometry like captions: centre as frame fractions, size a fraction of
 * the frame HEIGHT, OUTPUT-time start/end. Drawn with [StickerRenderer]
 * by the preview overlay and the export overlay alike.
 */
data class StickerLayer(
    val id: String = UUID.randomUUID().toString(),
    val stickerId: String,
    val sizeFrac: Float = 0.16f,
    val x: Float = 0.5f,
    val y: Float = 0.35f,
    val rotationDeg: Float = 0f,
    val scale: Float = 1f,
    val flipX: Boolean = false,
    val startMs: Long = 0L,
    val endMs: Long = 3_000L,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("stickerId", stickerId); put("sizeFrac", sizeFrac.toDouble())
        put("x", x.toDouble()); put("y", y.toDouble()); put("rotationDeg", rotationDeg.toDouble())
        put("scale", scale.toDouble()); put("flipX", flipX); put("startMs", startMs); put("endMs", endMs)
    }

    companion object {
        fun fromJson(o: JSONObject): StickerLayer = StickerLayer(
            id = o.optString("id", UUID.randomUUID().toString()),
            stickerId = o.optString("stickerId", ""),
            sizeFrac = o.optDouble("sizeFrac", 0.16).toFloat(),
            x = o.optDouble("x", 0.5).toFloat(),
            y = o.optDouble("y", 0.35).toFloat(),
            rotationDeg = o.optDouble("rotationDeg", 0.0).toFloat(),
            scale = o.optDouble("scale", 1.0).toFloat(),
            flipX = o.optBoolean("flipX", false),
            startMs = o.optLong("startMs", 0L),
            endMs = o.optLong("endMs", 3_000L),
        )

        fun listToJson(layers: List<StickerLayer>): JSONArray = JSONArray().apply { layers.forEach { put(it.toJson()) } }

        fun listFromJson(array: JSONArray?): List<StickerLayer> =
            if (array == null) emptyList() else (0 until array.length()).map { fromJson(array.getJSONObject(it)) }
    }
}

/** One sticker of the catalog: its sprite sheet and frame layout. */
data class StickerDef(
    val id: String,
    val label: String,
    val file: String,
    val frames: Int,
    val cols: Int,
    val size: Int,
    val durationMs: Long,
    /** Cell size (non-square stickers keep their aspect); the bundled ones are size x size. */
    val w: Int = size,
    val h: Int = size,
    /** [file] is an absolute path, not an asset name. */
    val local: Boolean = false,
) {
    val aspect: Float get() = w.toFloat() / h.coerceAtLeast(1)

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("label", label); put("file", file); put("frames", frames); put("cols", cols)
        put("size", size); put("durationMs", durationMs); put("w", w); put("h", h); put("local", local)
    }

    /** Frame shown [localMs] into the sticker's time on screen (loops). */
    fun frameAt(localMs: Long): Int {
        if (frames <= 1 || durationMs <= 0) return 0
        val t = ((localMs % durationMs) + durationMs) % durationMs
        return ((t * frames) / durationMs).toInt().coerceIn(0, frames - 1)
    }
}

/**
 * The sticker catalog and sprite-sheet bitmaps. Thread-safe: used on the
 * UI thread (preview, picker) and the export GL thread. Sheets are kept in
 * a byte-bounded LRU (each full sheet is several MB decoded); the picker
 * uses half-resolution copies.
 */
class StickerStore(private val context: Context) {
    val all: List<StickerDef> by lazy {
        runCatching {
            val json = context.assets.open("stickers/stickers.json").bufferedReader().use { it.readText() }
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                StickerDef(
                    id = o.getString("id"),
                    label = o.optString("label"),
                    file = o.getString("file"),
                    frames = o.getInt("frames"),
                    cols = o.getInt("cols"),
                    size = o.getInt("size"),
                    durationMs = o.getLong("durationMs"),
                )
            }
        }.getOrDefault(emptyList())
    }

    fun byId(id: String): StickerDef? = all.firstOrNull { it.id == id }

    private val cache = object : LruCache<String, Bitmap>(48 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    /** Already decoded (never decodes — for drawing on the UI thread while the picker loads sheets in the background). */
    @Synchronized
    fun cachedSheet(def: StickerDef, sample: Int): Bitmap? = cache.get("${def.file}@$sample")

    /** The sheet at full resolution ([sample] 1) or reduced (2 = half). Null if it can't be decoded. */
    @Synchronized
    fun sheet(def: StickerDef, sample: Int = 1): Bitmap? {
        val key = "${def.file}@$sample"
        cache.get(key)?.let { return it }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = runCatching {
            if (def.local) {
                BitmapFactory.decodeFile(def.file, options)
            } else {
                context.assets.open("stickers/${def.file}").use { BitmapFactory.decodeStream(it, null, options) }
            }
        }.getOrNull() ?: return null
        cache.put(key, bitmap)
        return bitmap
    }

    private val thumbs = HashMap<String, Bitmap>()

    /** The first frame only, decoded on its own (picker thumbnails; call off the main thread). */
    fun thumbnail(def: StickerDef): Bitmap? {
        synchronized(thumbs) { thumbs[def.id]?.let { return it } }
        val bitmap = runCatching {
            val stream = if (def.local) java.io.FileInputStream(def.file) else context.assets.open("stickers/${def.file}")
            stream.use {
                @Suppress("DEPRECATION")
                val decoder = BitmapRegionDecoder.newInstance(it, false) ?: return@use null
                try {
                    decoder.decodeRegion(Rect(0, 0, def.w, def.h), null)
                } finally {
                    decoder.recycle()
                }
            }
        }.getOrNull() ?: return null
        synchronized(thumbs) { thumbs[def.id] = bitmap }
        return bitmap
    }
}

object StickerRenderer {
    private const val POP_MS = 250L
    private const val OUT_MS = 200L

    // A new Paint per draw: this runs on the UI thread and the export GL thread.
    private fun newPaint() = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private fun backOut(t: Float): Float {
        val c1 = 1.70158f
        val c3 = c1 + 1f
        val x = t.coerceIn(0f, 1f) - 1f
        return 1f + c3 * x * x * x + c1 * x * x
    }

    /** Pop-in at the start, quick fade at the end: (scale, alpha). */
    private fun envelope(layer: StickerLayer, tMs: Long): Pair<Float, Float> {
        val local = tMs - layer.startMs
        val scale = if (local < POP_MS) backOut(local.toFloat() / POP_MS).coerceAtLeast(0.01f) else 1f
        val remaining = layer.endMs - tMs
        val alpha = if (remaining < OUT_MS) (remaining.toFloat() / OUT_MS).coerceIn(0f, 1f) else 1f
        return scale to alpha
    }

    /**
     * Half the sticker's width and height, in frame pixels, before its own
     * scale: the LONG side is sizeFrac of the frame height (square bundled
     * stickers; wide or tall ones keep their aspect).
     */
    fun halfSize(layer: StickerLayer, frameH: Float, store: StickerStore): Pair<Float, Float> {
        val long = layer.sizeFrac * frameH / 2f
        val aspect = store.byId(layer.stickerId)?.aspect ?: 1f
        return if (aspect >= 1f) long to long / aspect else long * aspect to long
    }

    fun hitTest(layer: StickerLayer, store: StickerStore, frameW: Float, frameH: Float, px: Float, py: Float): Boolean {
        val rad = -layer.rotationDeg * PI.toFloat() / 180f
        val dx = px - layer.x * frameW
        val dy = py - layer.y * frameH
        val lx = (dx * cos(rad) - dy * sin(rad)) / layer.scale
        val ly = (dx * sin(rad) + dy * cos(rad)) / layer.scale
        val (hw, hh) = halfSize(layer, frameH, store)
        return lx in -hw * 1.1f..hw * 1.1f && ly in -hh * 1.1f..hh * 1.1f
    }

    private fun cellRect(def: StickerDef, sheet: Bitmap, frame: Int): Rect {
        val cw = sheet.width / def.cols
        val ch = (cw * def.h / def.w.coerceAtLeast(1)).coerceAtLeast(1)
        val c = frame % def.cols
        val r = frame / def.cols
        return Rect(c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)
    }

    fun draw(canvas: Canvas, layer: StickerLayer, frameW: Float, frameH: Float, tMs: Long, store: StickerStore, sample: Int = 1) {
        if (tMs < layer.startMs || tMs >= layer.endMs) return
        val def = store.byId(layer.stickerId) ?: return
        val sheet = store.sheet(def, sample) ?: return
        val (pop, alpha) = envelope(layer, tMs)
        if (alpha <= 0.001f) return
        val frame = def.frameAt(tMs - layer.startMs)
        val src = cellRect(def, sheet, frame)
        val (hw, hh) = halfSize(layer, frameH, store)
        canvas.save()
        canvas.translate(layer.x * frameW, layer.y * frameH)
        canvas.rotate(layer.rotationDeg)
        val s = layer.scale * pop
        canvas.scale(if (layer.flipX) -s else s, s)
        val paint = newPaint().apply { this.alpha = (255 * alpha).toInt() }
        canvas.drawBitmap(sheet, src, RectF(-hw, -hh, hw, hh), paint)
        canvas.restore()
    }

    /** Draws frame [frame] of [def] filling [dst] (picker thumbnails). */
    fun drawFrame(canvas: Canvas, def: StickerDef, sheet: Bitmap, frame: Int, dst: RectF) {
        val src = cellRect(def, sheet, frame)
        canvas.drawBitmap(sheet, src, dst, newPaint())
    }
}
