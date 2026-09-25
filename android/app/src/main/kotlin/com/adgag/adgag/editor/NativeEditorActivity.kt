package com.adgag.adgag.editor

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.media3.common.util.UnstableApi
import java.io.File

/**
 * Native, per-platform editor screen — launched from Flutter's
 * `MainActivity` via [Intent], not embedded as a Flutter widget. A
 * separate Activity (not a Flutter `PlatformView`) is the deliberately
 * simpler integration point for a screen this rich: no PlatformView
 * texture/gesture-forwarding complexity, and Compose owns its own
 * lifecycle exactly the way it does in a pure-native app.
 *
 * See EditorViewModel's own doc comment for *why* this screen exists at
 * all (a real, confirmed-on-device architecture limitation in the
 * Flutter+two-VideoPlayerController approach it replaces).
 */
@UnstableApi
class NativeEditorActivity : ComponentActivity() {

    companion object {
        const val EXTRA_VIDEO_PATH = "video_path"
        const val EXTRA_OUTPUT_PATH = "output_path"
        const val EXTRA_OUTPUT_DURATION_MS = "output_duration_ms"
        const val EXTRA_ERROR = "error"
        private const val TAG = "NativeEditorActivity"
    }

    private val viewModel: EditorViewModel by viewModels {
        object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
                val path = intent.getStringExtra(EXTRA_VIDEO_PATH)
                    ?: error("NativeEditorActivity started without $EXTRA_VIDEO_PATH")
                @Suppress("UNCHECKED_CAST")
                return EditorViewModel(applicationContext, path) as T
            }
        }
    }

    private var previousExceptionHandler: Thread.UncaughtExceptionHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Real user report: this screen crashed the whole app on first
        // physical-device test with no way to see why (no ADB access in
        // this dev environment, only the user's own screenshot of the
        // system "app has stopped" dialog). Rather than guess again at
        // what a stack trace would have said, this makes the crash
        // recoverable AND visible: any uncaught exception anywhere in
        // this Activity's lifetime (Compose recomposition, a background
        // coroutine inside EditorViewModel, anything) is caught here,
        // finishes the Activity cleanly with the real exception text
        // instead of killing the process, and MainActivity.onActivityResult
        // surfaces it as a real Flutter-side error message — the same
        // "never silently fail, never require a connected computer to
        // diagnose" discipline this project's Flutter/Dart side has used
        // throughout its own debugging history. Scoped to only this
        // Activity's lifetime (installed in onCreate, restored in
        // onDestroy) so it can't mask an unrelated crash elsewhere in the
        // app after the user leaves this screen.
        previousExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "Uncaught exception in native editor", throwable)
            try {
                runOnUiThread {
                    val result = Intent().apply {
                        putExtra(EXTRA_ERROR, "${throwable::class.java.simpleName}: ${throwable.message}\n${throwable.stackTraceToString()}")
                    }
                    setResult(RESULT_CANCELED, result)
                    finish()
                }
            } catch (recoveryFailure: Exception) {
                // Recovery itself failed (e.g. this Activity is already
                // finishing) — fall back to the platform's own crash
                // handling rather than silently swallowing everything.
                Log.e(TAG, "Crash recovery itself failed", recoveryFailure)
                previousExceptionHandler?.uncaughtException(thread, throwable)
            }
        }

        try {
            setContent {
                EditorScreen(
                    viewModel = viewModel,
                    onCancel = {
                        setResult(RESULT_CANCELED)
                        finish()
                    },
                    onExported = { path, durationMs ->
                        val result = Intent().apply {
                            putExtra(EXTRA_OUTPUT_PATH, path)
                            putExtra(EXTRA_OUTPUT_DURATION_MS, durationMs)
                        }
                        setResult(RESULT_OK, result)
                        finish()
                    },
                    exportOutputPath = outputFilePath(this),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize native editor", e)
            val result = Intent().apply {
                putExtra(EXTRA_ERROR, "${e::class.java.simpleName}: ${e.message}\n${e.stackTraceToString()}")
            }
            setResult(RESULT_CANCELED, result)
            finish()
        }
    }

    override fun onDestroy() {
        Thread.setDefaultUncaughtExceptionHandler(previousExceptionHandler)
        super.onDestroy()
    }

    override fun onBackPressed() {
        setResult(RESULT_CANCELED)
        super.onBackPressed()
    }
}

private fun outputFilePath(context: Context): String {
    val dir = context.cacheDir
    return File(dir, "adgag_native_export_${System.currentTimeMillis()}.mp4").absolutePath
}
