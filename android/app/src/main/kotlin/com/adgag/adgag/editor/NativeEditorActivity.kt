package com.adgag.adgag.editor

import android.content.Context
import android.content.Intent
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
