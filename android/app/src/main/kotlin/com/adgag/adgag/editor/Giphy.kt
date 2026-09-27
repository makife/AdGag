package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * GIPHY search for the Stickers panel. The API key comes from the app's
 * env config (GIPHY_API_KEY, passed in by Flutter when the editor opens) —
 * never from source. GIPHY keys are client keys (their own SDKs ship them
 * in apps); an empty key just shows "not configured" in the panel.
 *
 * A picked GIF is turned into the SAME kind of sprite sheet as the bundled
 * stickers (frames every 50ms, WebP, + a def JSON) under filesDir/giphy/,
 * so preview, export and the "+"-relaunch all treat it like any sticker —
 * and the export can draw any frame at any time. Frames come from
 * android.graphics.Movie: deprecated, but the one platform GIF decoder that
 * can SEEK (ImageDecoder/AnimatedImageDrawable only play on their own clock).
 */
object GiphyConfig {
    @Volatile var apiKey: String = ""
}

enum class GiphyKind(val label: String, val path: String) { STICKERS("Stickers", "stickers"), GIFS("GIFs", "gifs") }

data class GiphyItem(
    val id: String,
    val title: String,
    /** Small animated preview for the grid. */
    val previewUrl: String,
    /** The GIF actually imported (200px wide). */
    val gifUrl: String,
    val width: Int,
    val height: Int,
)

object Giphy {
    private const val TAG = "Giphy"
    private const val STEP_MS = 50L
    private const val MAX_FRAMES = 80
    private const val COLS = 6

    /** Trending when [query] is blank. Rated pg-13 at most (CLAUDE.md section 31). */
    suspend fun search(kind: GiphyKind, query: String): List<GiphyItem> = withContext(Dispatchers.IO) {
        val key = GiphyConfig.apiKey
        if (key.isBlank()) return@withContext emptyList()
        val q = query.trim()
        val url = if (q.isEmpty()) {
            "https://api.giphy.com/v1/${kind.path}/trending?api_key=$key&limit=36&rating=pg-13"
        } else {
            "https://api.giphy.com/v1/${kind.path}/search?api_key=$key&limit=36&rating=pg-13&q=" +
                URLEncoder.encode(q, "UTF-8")
        }
        val body = download(url).toString(Charsets.UTF_8)
        val data = JSONObject(body).getJSONArray("data")
        (0 until data.length()).mapNotNull { i ->
            val o = data.getJSONObject(i)
            val images = o.optJSONObject("images") ?: return@mapNotNull null
            val preview = images.optJSONObject("fixed_width_small") ?: images.optJSONObject("fixed_width")
            val full = images.optJSONObject("fixed_width") ?: return@mapNotNull null
            GiphyItem(
                id = o.getString("id"),
                title = o.optString("title"),
                previewUrl = preview?.optString("url").orEmpty().ifEmpty { full.optString("url") },
                gifUrl = full.optString("url"),
                width = full.optString("width").toIntOrNull() ?: 200,
                height = full.optString("height").toIntOrNull() ?: 200,
            )
        }
    }

    private val bytesCache = object : android.util.LruCache<String, ByteArray>(12 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }

    suspend fun bytes(url: String): ByteArray = withContext(Dispatchers.IO) {
        bytesCache.get(url) ?: download(url).also { bytesCache.put(url, it) }
    }

    private fun download(url: String): ByteArray {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 10_000
        conn.readTimeout = 15_000
        try {
            if (conn.responseCode !in 200..299) error("GIPHY HTTP ${conn.responseCode}")
            return conn.inputStream.use { it.readBytes() }
        } finally {
            conn.disconnect()
        }
    }

    fun dir(context: Context): File = File(context.filesDir, "giphy").apply { mkdirs() }

    /** Downloads [item] and packs it into a local sprite sheet; returns its sticker definition. */
    @Suppress("DEPRECATION")
    suspend fun import(context: Context, item: GiphyItem): StickerDef = withContext(Dispatchers.Default) {
        val id = "giphy_${item.id}"
        val dir = dir(context)
        StickerStore.readLocalDef(dir, id)?.let { return@withContext it }
        val bytes = bytes(item.gifUrl)
        val movie = Movie.decodeByteArray(bytes, 0, bytes.size) ?: error("Couldn't decode that GIF")
        val w = max(1, movie.width())
        val h = max(1, movie.height())
        // Cells at most 200px on the long side (the fixed_width rendition already is).
        val scale = min(1f, 200f / max(w, h))
        val cw = max(1, (w * scale).roundToInt())
        val ch = max(1, (h * scale).roundToInt())
        val duration = movie.duration().toLong()
        val frames = if (duration <= 0) 1 else (duration / STEP_MS).toInt().coerceIn(1, MAX_FRAMES)
        val rows = (frames + COLS - 1) / COLS
        val sheet = Bitmap.createBitmap(cw * COLS, ch * rows, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        val frameBitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val frameCanvas = Canvas(frameBitmap)
        for (f in 0 until frames) {
            frameBitmap.eraseColor(Color.TRANSPARENT)
            movie.setTime(if (duration <= 0) 0 else (f * duration / frames).toInt())
            movie.draw(frameCanvas, 0f, 0f)
            canvas.save()
            canvas.translate(((f % COLS) * cw).toFloat(), ((f / COLS) * ch).toFloat())
            canvas.scale(cw.toFloat() / w, ch.toFloat() / h)
            canvas.drawBitmap(frameBitmap, 0f, 0f, null)
            canvas.restore()
        }
        frameBitmap.recycle()
        val file = File(dir, "$id.webp")
        FileOutputStream(file).use {
            @Suppress("DEPRECATION")
            sheet.compress(Bitmap.CompressFormat.WEBP, 80, it)
        }
        sheet.recycle()
        val def = StickerDef(
            id = id,
            label = item.title.ifBlank { "GIPHY" },
            file = file.absolutePath,
            frames = frames,
            cols = COLS,
            size = max(cw, ch),
            durationMs = if (duration <= 0) 1_000L else duration,
            w = cw,
            h = ch,
            local = true,
        )
        StickerStore.writeLocalDef(dir, def)
        Log.i(TAG, "imported ${item.id}: $frames frames ${cw}x$ch")
        def
    }
}
