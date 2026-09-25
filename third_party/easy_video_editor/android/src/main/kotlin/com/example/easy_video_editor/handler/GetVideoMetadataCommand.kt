package com.example.easy_video_editor.handler

import android.content.Context
import androidx.media3.common.util.UnstableApi
import com.example.easy_video_editor.command.Command
import com.example.easy_video_editor.utils.VideoUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class GetVideoMetadataCommand(private val context: Context) : Command {
    @UnstableApi
    override fun execute(call: MethodCall, result: MethodChannel.Result) {
        val videoPath = call.argument<String>("videoPath")
        
        if (videoPath == null) {
            result.error("INVALID_ARGS", "Missing required argument: videoPath", null)
            return
        }
        
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val metadata = VideoUtils.getVideoMetadata(context, videoPath)
                
                // Convert metadata to map for Flutter
                val metadataMap = mapOf(
                    "duration" to metadata.duration,
                    "width" to metadata.width,
                    "height" to metadata.height,
                    "title" to metadata.title,
                    "author" to metadata.author,
                    "rotation" to metadata.rotation,
                    "fileSize" to metadata.fileSize,
                    "date" to metadata.date,
                )
                
                withContext(Dispatchers.Main) {
                    result.success(metadataMap)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("METADATA_ERROR", e.message ?: "Failed to get video metadata", null)
                }
            }
        }
    }
}
