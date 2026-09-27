package com.adgag.adgag.editor

import android.content.Context
import android.graphics.Typeface
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Text layers ("Text" tool): any number of styled, animated captions over
 * the whole Ad, each shown from [TextLayer.startMs] to [TextLayer.endMs]
 * in OUTPUT time. Drawn by [TextRenderer] — the same code for the live
 * preview (Compose canvas) and the export (a full-frame Media3
 * BitmapOverlay at composition level), so what's previewed is exported.
 *
 * Geometry is resolution-independent: position is the text block's centre
 * as a fraction of the frame, size a fraction of the frame HEIGHT.
 */
data class TextLayer(
    val id: String = UUID.randomUUID().toString(),
    val text: String = "Your text",
    val fontId: String = TextFonts.DEFAULT_ID,
    val sizeFrac: Float = 0.06f,
    val color: Int = 0xFFFFFFFF.toInt(),
    /** Second colour: outline / shadow / glow / box / 3D depth, depending on [style]. */
    val accentColor: Int = 0xFFFF3D9E.toInt(),
    val opacity: Float = 1f,
    val style: TextStyleEffect = TextStyleEffect.OUTLINE,
    val animation: TextAnimation = TextAnimation.POP,
    val align: TextAlignment = TextAlignment.CENTER,
    /** Extra space between letters, fraction of the font size. */
    val letterSpacing: Float = 0f,
    val x: Float = 0.5f,
    val y: Float = 0.45f,
    val rotationDeg: Float = 0f,
    val scale: Float = 1f,
    val startMs: Long = 0L,
    val endMs: Long = 3_000L,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("text", text); put("fontId", fontId); put("sizeFrac", sizeFrac.toDouble())
        put("color", color); put("accentColor", accentColor); put("opacity", opacity.toDouble())
        put("style", style.name); put("animation", animation.name); put("align", align.name)
        put("letterSpacing", letterSpacing.toDouble()); put("x", x.toDouble()); put("y", y.toDouble())
        put("rotationDeg", rotationDeg.toDouble()); put("scale", scale.toDouble())
        put("startMs", startMs); put("endMs", endMs)
    }

    companion object {
        fun fromJson(o: JSONObject): TextLayer = TextLayer(
            id = o.optString("id", UUID.randomUUID().toString()),
            text = o.optString("text", ""),
            fontId = o.optString("fontId", TextFonts.DEFAULT_ID),
            sizeFrac = o.optDouble("sizeFrac", 0.06).toFloat(),
            color = o.optInt("color", 0xFFFFFFFF.toInt()),
            accentColor = o.optInt("accentColor", 0xFFFF3D9E.toInt()),
            opacity = o.optDouble("opacity", 1.0).toFloat(),
            style = runCatching { TextStyleEffect.valueOf(o.optString("style")) }.getOrDefault(TextStyleEffect.NONE),
            animation = runCatching { TextAnimation.valueOf(o.optString("animation")) }.getOrDefault(TextAnimation.NONE),
            align = runCatching { TextAlignment.valueOf(o.optString("align")) }.getOrDefault(TextAlignment.CENTER),
            letterSpacing = o.optDouble("letterSpacing", 0.0).toFloat(),
            x = o.optDouble("x", 0.5).toFloat(),
            y = o.optDouble("y", 0.45).toFloat(),
            rotationDeg = o.optDouble("rotationDeg", 0.0).toFloat(),
            scale = o.optDouble("scale", 1.0).toFloat(),
            startMs = o.optLong("startMs", 0L),
            endMs = o.optLong("endMs", 3_000L),
        )

        fun listToJson(layers: List<TextLayer>): JSONArray = JSONArray().apply { layers.forEach { put(it.toJson()) } }

        fun listFromJson(array: JSONArray?): List<TextLayer> =
            if (array == null) emptyList() else (0 until array.length()).map { fromJson(array.getJSONObject(it)) }
    }
}

enum class TextAlignment { LEFT, CENTER, RIGHT }

/** The static look of the letters. [TextRenderer] implements each one. */
enum class TextStyleEffect(val label: String) {
    NONE("Plain"),
    OUTLINE("Outline"),
    SHADOW("Shadow"),
    GLOW("Glow"),
    NEON("Neon"),
    BOX("Box"),
    PILL("Pill"),
    HIGHLIGHT("Marker"),
    HOLLOW("Hollow"),
    EXTRUDE("3D"),
    REFLECTION("Mirror"),
    COMIC("Comic"),
    RETRO("Retro"),
    GLITCH("Glitch"),
    GOLD("Gold"),
    SUNSET("Sunset"),
    OCEAN("Ocean"),
    RAINBOW_FILL("Rainbow"),
}

/** Motion: entrances (play once at the start) and loops (for the whole time on screen). */
enum class TextAnimation(val label: String) {
    NONE("None"),
    FADE("Fade"),
    POP("Pop"),
    BOUNCE("Bounce"),
    ZOOM("Zoom"),
    SPIN("Spin"),
    SLIDE_UP("Slide up"),
    SLIDE_DOWN("Slide down"),
    SLIDE_LEFT("Slide left"),
    SLIDE_RIGHT("Slide right"),
    TYPEWRITER("Typewriter"),
    RISE("Rise"),
    DROP("Drop in"),
    WAVE("Wave"),
    JUMP("Jump"),
    SHAKE("Shake"),
    PULSE("Pulse"),
    SWING("Swing"),
    FLICKER("Flicker"),
    RAINBOW("Rainbow"),
}

/**
 * The bundled fonts (android/app/src/main/assets/fonts — Google Fonts, OFL
 * / Apache, licences in assets/fonts/licenses; every one checked to have
 * the Turkish letters ğ ş ı İ ç ö ü). Variable fonts are offered at more
 * than one weight via [TextFont.weight] (Paint.fontVariationSettings,
 * API 26+; older devices just get the default weight).
 */
data class TextFont(val id: String, val label: String, val file: String, val weight: Int? = null)

object TextFonts {
    const val DEFAULT_ID = "montserrat_black"

    val all: List<TextFont> = listOf(
        TextFont("montserrat_black", "Montserrat", "Montserrat-Variable.ttf", 900),
        TextFont("montserrat", "Montserrat Light", "Montserrat-Variable.ttf", 400),
        TextFont("anton", "Anton", "Anton-Regular.ttf"),
        TextFont("bebas", "Bebas Neue", "BebasNeue-Regular.ttf"),
        TextFont("oswald", "Oswald", "Oswald-Variable.ttf", 700),
        TextFont("poppins", "Poppins", "Poppins-Bold.ttf"),
        TextFont("archivo", "Archivo Black", "ArchivoBlack-Regular.ttf"),
        TextFont("russo", "Russo One", "RussoOne-Regular.ttf"),
        TextFont("bangers", "Bangers", "Bangers-Regular.ttf"),
        TextFont("luckiest", "Luckiest Guy", "LuckiestGuy-Regular.ttf"),
        TextFont("bungee", "Bungee", "Bungee-Regular.ttf"),
        TextFont("rubikmono", "Rubik Mono", "RubikMonoOne-Regular.ttf"),
        TextFont("blackops", "Black Ops", "BlackOpsOne-Regular.ttf"),
        TextFont("righteous", "Righteous", "Righteous-Regular.ttf"),
        TextFont("audiowide", "Audiowide", "Audiowide-Regular.ttf"),
        TextFont("pressstart", "Pixel", "PressStart2P-Regular.ttf"),
        TextFont("monoton", "Monoton", "Monoton-Regular.ttf"),
        TextFont("shrikhand", "Shrikhand", "Shrikhand-Regular.ttf"),
        TextFont("abril", "Abril Fatface", "AbrilFatface-Regular.ttf"),
        TextFont("playfair", "Playfair", "PlayfairDisplay-Variable.ttf", 800),
        TextFont("specialelite", "Typewriter", "SpecialElite-Regular.ttf"),
        TextFont("lobster", "Lobster", "Lobster-Regular.ttf"),
        TextFont("pacifico", "Pacifico", "Pacifico-Regular.ttf"),
        TextFont("kaushan", "Kaushan", "KaushanScript-Regular.ttf"),
        TextFont("dancing", "Dancing", "DancingScript-Variable.ttf", 700),
        TextFont("greatvibes", "Great Vibes", "GreatVibes-Regular.ttf"),
        TextFont("caveat", "Caveat", "Caveat-Variable.ttf", 700),
    )

    fun byId(id: String): TextFont = all.firstOrNull { it.id == id } ?: all.first()
}

/** Loads (once) and caches the typefaces. Thread-safe; used on the UI thread and the export GL thread. */
class TypefaceCache(private val context: Context) {
    private val cache = HashMap<String, Typeface>()

    @Synchronized
    fun get(font: TextFont): Typeface = cache.getOrPut(font.file) {
        runCatching { Typeface.createFromAsset(context.assets, "fonts/${font.file}") }.getOrDefault(Typeface.DEFAULT_BOLD)
    }
}

/** Colour swatches for the text colour and the accent colour. */
val TextPalette: List<Int> = listOf(
    0xFFFFFFFF, 0xFF000000, 0xFFFF3D9E, 0xFFFF1744, 0xFFFF9100, 0xFFFFD600, 0xFFC6FF00, 0xFF00E676,
    0xFF1DE9B6, 0xFF00E5FF, 0xFF2979FF, 0xFF651FFF, 0xFFD500F9, 0xFFFF80AB, 0xFF8D6E63, 0xFF9E9E9E,
).map { it.toInt() }
