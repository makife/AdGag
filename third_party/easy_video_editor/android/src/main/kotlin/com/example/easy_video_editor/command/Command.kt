package com.example.easy_video_editor.command

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

interface Command {
    fun execute(call: MethodCall, result: MethodChannel.Result)
}
