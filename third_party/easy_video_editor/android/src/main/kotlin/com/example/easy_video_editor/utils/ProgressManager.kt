package com.example.easy_video_editor.utils

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Singleton class to manage progress updates for video operations
 */
class ProgressManager private constructor() {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        @Volatile
        private var instance: ProgressManager? = null

        fun getInstance(): ProgressManager {
            return instance ?: synchronized(this) {
                instance ?: ProgressManager().also { instance = it }
            }
        }
    }

    /**
     * Set the event sink for sending progress updates
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    /**
     * Report progress to Flutter
     * @param progress Progress value between 0.0 and 1.0
     */
    fun reportProgress(progress: Double) {
        // Ensure progress is between 0 and 1
        val normalizedProgress = progress.coerceIn(0.0, 1.0)
        
        // Send progress to Flutter on the main thread
        mainHandler.post {
            eventSink?.success(normalizedProgress)
        }
    }
}
