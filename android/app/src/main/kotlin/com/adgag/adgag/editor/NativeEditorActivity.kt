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
        /** Relaunch after recording another clip: the previous session's state (EditorSessionState JSON)... */
        const val EXTRA_STATE_JSON = "state_json"
        /** ...plus the newly recorded clip to append (absent if the user cancelled the recording). */
        const val EXTRA_NEW_CLIP_PATH = "new_clip_path"
        /** Result when the user tapped "+": the session to hand back on relaunch, and how much time is left to record. */
        const val EXTRA_ADD_CLIP_STATE = "add_clip_state"
        const val EXTRA_REMAINING_MS = "remaining_ms"
        const val EXTRA_OUTPUT_PATH = "output_path"
        const val EXTRA_OUTPUT_DURATION_MS = "output_duration_ms"
        const val EXTRA_ERROR = "error"
        private const val TAG = "NativeEditorActivity"
    }

    private val viewModel: EditorViewModel by viewModels {
        object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
                val stateJson = intent.getStringExtra(EXTRA_STATE_JSON)
                val state = if (stateJson != null) {
                    EditorSessionState.fromJson(stateJson)
                } else {
                    val path = intent.getStringExtra(EXTRA_VIDEO_PATH)
                        ?: error("NativeEditorActivity started without $EXTRA_VIDEO_PATH or $EXTRA_STATE_JSON")
                    EditorViewModel.initialStateFor(applicationContext, path)
                }
                @Suppress("UNCHECKED_CAST")
                return EditorViewModel(applicationContext, state, intent.getStringExtra(EXTRA_NEW_CLIP_PATH)) as T
            }
        }
    }

    private var previousExceptionHandler: Thread.UncaughtExceptionHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        DebugLog.log(applicationContext, "onCreate: start")
        super.onCreate(savedInstanceState)
        DebugLog.log(applicationContext, "onCreate: super.onCreate done")
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
            DebugLog.log(applicationContext, "onCreate: about to call setContent")
            var composedOnce = false
            setContent {
                // Real bug found via user report ("editor page is very
                // sluggish"): this DebugLog.log call used to sit directly
                // in the composable body, meaning it ran — as a
                // SYNCHRONOUS, BLOCKING FILE WRITE ON THE MAIN THREAD —
                // on every single recomposition (every play/pause, trim
                // drag, rotate, mute tap all trigger one). A local flag
                // instead of e.g. LaunchedEffect(Unit): this needs to run
                // exactly once, at the very first composition, with zero
                // Compose scheduling overhead of its own.
                if (!composedOnce) {
                    composedOnce = true
                    DebugLog.log(applicationContext, "setContent: composing EditorScreen (first time)")
                }
                EditorScreen(
                    viewModel = viewModel,
                    onCancel = {
                        DebugLog.clear(applicationContext) // normal exit, not a crash — see DebugLog.clear's own doc comment
                        setResult(RESULT_CANCELED)
                        finish()
                    },
                    onExported = { path, durationMs ->
                        DebugLog.clear(applicationContext) // normal exit, not a crash
                        val result = Intent().apply {
                            putExtra(EXTRA_OUTPUT_PATH, path)
                            putExtra(EXTRA_OUTPUT_DURATION_MS, durationMs)
                        }
                        setResult(RESULT_OK, result)
                        finish()
                    },
                    onAddClip = {
                        DebugLog.clear(applicationContext) // normal exit, not a crash
                        val result = Intent().apply {
                            putExtra(EXTRA_ADD_CLIP_STATE, viewModel.sessionState().toJson())
                            putExtra(EXTRA_REMAINING_MS, viewModel.remainingMs)
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

    /**
     * Real bug (user report: "the app is in the background but I still
     * hear the video"): nothing paused the editor's ExoPlayer when this
     * Activity left the screen — ExoPlayer has no lifecycle awareness of
     * its own. Pause whenever we're no longer visible (home, app switch,
     * the screen turning off). Not auto-resumed: the user taps play.
     */
    override fun onStop() {
        viewModel.player.pause()
        super.onStop()
    }

    override fun onDestroy() {
        Thread.setDefaultUncaughtExceptionHandler(previousExceptionHandler)
        super.onDestroy()
    }

    override fun onBackPressed() {
        DebugLog.clear(applicationContext) // normal exit (system back), not a crash
        setResult(RESULT_CANCELED)
        super.onBackPressed()
    }
}

private fun outputFilePath(context: Context): String {
    val dir = context.cacheDir
    return File(dir, "adgag_native_export_${System.currentTimeMillis()}.mp4").absolutePath
}
