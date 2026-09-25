package com.example.easy_video_editor

import android.content.Context
import com.example.easy_video_editor.handler.CommandHandler
import com.example.easy_video_editor.utils.ProgressManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** EasyVideoEditorPlugin */
class EasyVideoEditorPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: Context
  private lateinit var commandHandler: CommandHandler
  private var eventSink: EventChannel.EventSink? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    // Set up method channel
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "easy_video_editor")
    context = flutterPluginBinding.applicationContext
    commandHandler = CommandHandler(context)
    channel.setMethodCallHandler(this)
    
    // Set up event channel for progress updates
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "easy_video_editor/progress")
    eventChannel.setStreamHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    commandHandler.handleCommand(call, result)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }
  
  // EventChannel.StreamHandler implementation
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    ProgressManager.getInstance().setEventSink(events)
  }
  
  override fun onCancel(arguments: Any?) {
    eventSink = null
    ProgressManager.getInstance().setEventSink(null)
  }
}
