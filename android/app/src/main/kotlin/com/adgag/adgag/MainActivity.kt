package com.adgag.adgag

import android.app.Activity
import android.content.Intent
import com.adgag.adgag.editor.DebugLog
import com.adgag.adgag.editor.NativeEditorActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `FlutterActivity`, not `FlutterFragmentActivity` — deliberately kept as
 * the plain base class every other native integration in this app
 * (camera permissions, the `adgag://login-callback` deep link) already
 * relies on and has been confirmed working on a real device. Launching
 * [NativeEditorActivity] therefore uses the classic
 * `startActivityForResult`/`onActivityResult` pair, not AndroidX's
 * `registerForActivityResult` (which needs a `ComponentActivity` —
 * `FlutterActivity` isn't one; only `FlutterFragmentActivity` is) —
 * still fully supported, just older-style, and not worth risking a base-
 * class swap for on an Activity this much of the app already depends on.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.adgag.adgag/native_editor"
    private val editorRequestCode = 4201

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "openEditor" -> {
                    val videoPath = call.argument<String>("videoPath")
                    if (videoPath == null) {
                        result.error("MISSING_ARG", "videoPath is required", null)
                        return@setMethodCallHandler
                    }
                    if (pendingResult != null) {
                        // A previous call never resolved (shouldn't
                        // normally happen — the editor is a modal, full-
                        // screen flow) — fail it rather than silently
                        // drop it, so a caller awaiting it doesn't hang
                        // forever.
                        pendingResult?.error("SUPERSEDED", "A newer openEditor call started", null)
                    }
                    pendingResult = result
                    val intent = Intent(this, NativeEditorActivity::class.java).apply {
                        putExtra(NativeEditorActivity.EXTRA_VIDEO_PATH, videoPath)
                    }
                    DebugLog.log(applicationContext, "MainActivity: about to startActivityForResult")
                    startActivityForResult(intent, editorRequestCode)
                }
                // Diagnostic for a real, unexplained problem: the native
                // editor reportedly closes the whole app with NO visible
                // error at all — not even the Kotlin-level crash recovery
                // NativeEditorActivity installs. That signature points at
                // a NATIVE (not JVM) crash, invisible to
                // Thread.UncaughtExceptionHandler by construction — see
                // DebugLog's own doc comment. Reads back whatever
                // checkpoint log survived to disk from the last attempt,
                // even a hard-crashed one (a process death kills the
                // whole app, so this is only ever read on the NEXT
                // launch, not within the same crashed session).
                "readAndClearNativeEditorDebugLog" -> {
                    result.success(DebugLog.readAndClear(applicationContext))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != editorRequestCode) {
            return
        }
        val result = pendingResult ?: return
        pendingResult = null
        val errorMessage = data?.getStringExtra(NativeEditorActivity.EXTRA_ERROR)
        if (errorMessage != null) {
            // A real crash/failure inside the native editor, caught and
            // surfaced (see NativeEditorActivity's own uncaught-exception
            // handling) instead of taking the whole app down — reaches
            // Flutter as a genuine PlatformException, not a silent null,
            // so the caller can show the real reason instead of just
            // "nothing happened."
            result.error("NATIVE_EDITOR_CRASHED", errorMessage, null)
        } else if (resultCode == Activity.RESULT_OK && data != null) {
            val outputPath = data.getStringExtra(NativeEditorActivity.EXTRA_OUTPUT_PATH)
            val durationMs = data.getLongExtra(NativeEditorActivity.EXTRA_OUTPUT_DURATION_MS, 0L)
            if (outputPath != null) {
                result.success(mapOf("path" to outputPath, "durationMs" to durationMs))
            } else {
                result.success(null)
            }
        } else {
            // User cancelled (back button / no explicit error) — a plain
            // null result, not an error, matching how the existing
            // Flutter creation flow already treats "user backed out."
            result.success(null)
        }
    }
}
