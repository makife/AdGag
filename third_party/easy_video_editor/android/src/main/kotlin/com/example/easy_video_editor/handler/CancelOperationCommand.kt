package com.example.easy_video_editor.handler

import com.example.easy_video_editor.command.Command
import com.example.easy_video_editor.utils.OperationManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Command for canceling currently running operations
 */
class CancelOperationCommand : Command {
    override fun execute(call: MethodCall, result: MethodChannel.Result) {
        try {
            val wasCanceled = OperationManager.cancelAllOperations()
            result.success(wasCanceled)
        } catch (e: Exception) {
            result.error(
                "CANCEL_ERROR",
                "Error canceling operations: ${e.message}",
                null
            )
        }
    }
}
