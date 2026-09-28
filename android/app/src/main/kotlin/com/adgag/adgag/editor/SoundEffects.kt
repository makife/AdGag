package com.adgag.adgag.editor

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Sound effects ("Sound FX" tool): applause, ba-dum-tss, cha-ching, air
 * horn, jingles… 39 short CC0 sounds (Freesound items checked one by one,
 * Kenney packs), pre-processed offline by android/tools/build_sfx.py
 * (trimmed, normalized, MP3) into assets/sfx/ + sfx.json + LICENSE.txt.
 * The iOS editor bundles the very same files.
 *
 * A layer is one effect placed at [startMs] (OUTPUT time, like captions)
 * and plays its whole length. PREVIEW: a SoundPool fires the effect when
 * the playhead crosses its start ([SfxPlayer]) — the ExoPlayer preview
 * can't mix another audio source in. EXPORT: extra audio sequences in
 * the Transformer composition, mixed with the clips' sound and the music.
 */
data class SoundLayer(
    val id: String = UUID.randomUUID().toString(),
    val sfxId: String,
    val startMs: Long = 0L,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("sfxId", sfxId); put("startMs", startMs)
    }

    companion object {
        fun listToJson(layers: List<SoundLayer>): JSONArray = JSONArray().apply { layers.forEach { put(it.toJson()) } }

        fun listFromJson(array: JSONArray?): List<SoundLayer> =
            if (array == null) {
                emptyList()
            } else {
                (0 until array.length()).map { i ->
                    val o = array.getJSONObject(i)
                    SoundLayer(
                        id = o.optString("id", UUID.randomUUID().toString()),
                        sfxId = o.optString("sfxId", ""),
                        startMs = o.optLong("startMs", 0L),
                    )
                }
            }
    }
}

/** One effect of the catalog. */
data class SfxDef(
    val id: String,
    val label: String,
    val category: String,
    val file: String,
    val durationMs: Long,
) {
    /** For Media3 (DefaultDataSource reads asset:// URIs). */
    val assetUri: String get() = "asset:///sfx/$file"
}

/** The bundled catalog (assets/sfx/sfx.json), loaded once. */
class SfxStore(private val context: Context) {
    val all: List<SfxDef> by lazy {
        try {
            val json = context.assets.open("sfx/sfx.json").bufferedReader().use { it.readText() }
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                SfxDef(
                    id = o.getString("id"),
                    label = o.getString("label"),
                    category = o.optString("category", "Other"),
                    file = o.getString("file"),
                    durationMs = o.optLong("durationMs", 1_000L),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Categories in catalog order. */
    val categories: List<String> by lazy { all.map { it.category }.distinct() }

    fun byId(id: String): SfxDef? = all.firstOrNull { it.id == id }
}

/**
 * Plays effects for the PREVIEW and the picker. SoundPool, not ExoPlayer:
 * made for short sounds that start instantly, several at once, on top of
 * whatever the editor's player is doing. Samples load lazily; a play()
 * asked before its sample is ready starts as soon as it is.
 */
class SfxPlayer(private val context: Context) {
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(8)
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        )
        .build()
    private val sampleIds = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val playWhenLoaded = mutableSetOf<Int>()
    private val streams = ArrayDeque<Int>()

    init {
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) {
                loaded += sampleId
                if (playWhenLoaded.remove(sampleId)) start(sampleId)
            }
        }
    }

    /** Starts loading [def] so a later play() is instant. */
    fun preload(def: SfxDef) {
        sample(def)
    }

    fun play(def: SfxDef) {
        val id = sample(def) ?: return
        if (id in loaded) start(id) else playWhenLoaded += id
    }

    /** Silences everything that's playing (the preview paused or jumped). */
    fun stopAll() {
        playWhenLoaded.clear()
        while (streams.isNotEmpty()) pool.stop(streams.removeFirst())
    }

    fun release() {
        pool.release()
    }

    private fun sample(def: SfxDef): Int? = sampleIds[def.id] ?: try {
        context.assets.openFd("sfx/${def.file}").use { fd -> pool.load(fd, 1) }.also { sampleIds[def.id] = it }
    } catch (e: Exception) {
        null
    }

    private fun start(sampleId: Int) {
        val stream = pool.play(sampleId, 1f, 1f, 1, 0, 1f)
        if (stream != 0) {
            streams.addLast(stream)
            while (streams.size > 16) streams.removeFirst()
        }
    }
}
