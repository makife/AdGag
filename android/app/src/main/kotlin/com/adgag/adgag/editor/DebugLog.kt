package com.adgag.adgag.editor

import android.content.Context
import java.io.File

/**
 * Diagnostic tool for a real, unexplained problem: the native editor
 * reportedly closes the whole app with NO visible error at all — not
 * even the crash-recovery dialog `NativeEditorActivity`'s own
 * `Thread.setDefaultUncaughtExceptionHandler` should produce. That
 * combination (zero Kotlin-level exception surfaced, yet the process
 * dies) is the signature of a NATIVE crash (e.g. inside ExoPlayer's/
 * Media3's own C++ decoder layer) — `Thread.UncaughtExceptionHandler`
 * only ever sees JVM `Throwable`s, never a native SIGSEGV, so it cannot
 * catch this class of failure by construction, no matter how it's
 * written.
 *
 * There is no ADB access in this dev environment (no way to read a
 * native crash's tombstone), so this writes a plain, synchronous,
 * timestamped checkpoint log to a file on disk at each stage of the
 * native editor's startup — a synchronous file write (not a Toast,
 * which can be silently dropped if the process dies before it renders)
 * completes before the next line of code runs, so whatever the LAST
 * line in this file is, is the last checkpoint actually reached before
 * the crash. Read back via `readAndClear()`, exposed to Flutter through
 * `MainActivity`'s method channel — a hard native crash kills the whole
 * app process (Activities share one process by default), so this is
 * read back the NEXT time the app starts, not in the same session.
 */
object DebugLog {
    private const val FILE_NAME = "native_editor_debug.log"

    fun log(context: Context, message: String) {
        try {
            val file = File(context.filesDir, FILE_NAME)
            file.appendText("${System.currentTimeMillis()} $message\n")
        } catch (e: Exception) {
            // Never let the diagnostic tool itself be a new crash source.
        }
    }

    fun readAndClear(context: Context): String? {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.exists()) return null
        val content = try {
            file.readText()
        } catch (e: Exception) {
            null
        }
        file.delete()
        return content?.takeIf { it.isNotBlank() }
    }

    /**
     * Real bug found via user report: this log was only ever cleared
     * when the NEXT session checked it (`readAndClear`) — never at the
     * end of a session that finished NORMALLY (export succeeded, or the
     * user cancelled). That meant every ordinary, non-crashing editor
     * session left its checkpoint trail sitting on disk, and the very
     * next time the editor opened, `NativeEditorStep` read that leftover
     * log and reported "the native editor crashed last time" — a false
     * positive, not a real crash. Call this from every normal exit path
     * (export complete, cancel) so only a GENUINE crash ever leaves
     * something for the next session to find.
     */
    fun clear(context: Context) {
        try {
            File(context.filesDir, FILE_NAME).delete()
        } catch (e: Exception) {
            // Best-effort only.
        }
    }
}
