package com.adgag.adgag.editor

import android.content.Context
import org.json.JSONObject

/**
 * The native editor's UI language. The Flutter app passes the language it is
 * actually showing (its own Settings choice, else the device language) with
 * every openEditor call, so the editor always matches the rest of the app.
 *
 * Strings are looked up by their ENGLISH text — `tr("Cancel")`,
 * `tr("Clip {0} · trim", n)` — in `assets/l10n/editor.json`, generated from
 * `tool/l10n/editor_strings.py` (the source of truth, shared with iOS). A
 * missing translation just shows the English text.
 */
object EditorL10n {
    @Volatile private var table: Map<String, String> = emptyMap()

    @Volatile var language: String = "en"
        private set

    fun load(context: Context, lang: String?) {
        val code = lang?.takeIf { it.isNotBlank() } ?: "en"
        language = code
        if (code == "en") {
            table = emptyMap()
            return
        }
        table = runCatching {
            val all = JSONObject(context.assets.open("l10n/editor.json").bufferedReader().use { it.readText() })
            val o = all.optJSONObject(code) ?: return@runCatching emptyMap<String, String>()
            o.keys().asSequence().associateWith { o.getString(it) }
        }.getOrDefault(emptyMap())
    }

    fun t(en: String, args: Array<out Any?>): String {
        var s = table[en] ?: en
        args.forEachIndexed { i, a -> s = s.replace("{$i}", a.toString()) }
        return s
    }
}

/** The editor's translation of [en] (English text as the key); `{0}`, `{1}`… are replaced by [args]. */
fun tr(en: String, vararg args: Any?): String = EditorL10n.t(en, args)
