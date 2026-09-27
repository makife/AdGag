import Flutter
import SwiftUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNativeEditorChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // MARK: - Native editor bridge

  /// Registers the same-named channel the Android side uses
  /// (`com.adgag.adgag/native_editor`, see
  /// `lib/core/media/native_editor_bridge.dart`) — the Dart side is
  /// already platform-agnostic; only the two native implementations
  /// differ. `engineBridge.applicationRegistrar.messenger()` is the
  /// current (Flutter 3.38+, UISceneDelegate-based implicit-engine)
  /// way to get a `FlutterBinaryMessenger` from `AppDelegate` — the
  /// FlutterViewController itself is deliberately NOT accessed here
  /// (Flutter's own migration guide warns doing so at this point can
  /// crash); presenting a view controller happens later, in the actual
  /// method-call handler below, by which point the app's window is
  /// definitely already up.
  private func registerNativeEditorChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.adgag.adgag/native_editor", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "openEditor" else {
        // readAndClearNativeEditorDebugLog is Android-only; Dart treats this as "nothing to report".
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      // Same contract as Android (MainActivity): a fresh session from
      // videoPath, or a resumed one from state (+ an optional new clip
      // recorded via the timeline's "+").
      let state: EditorSessionState
      if let json = args["state"] as? String, let decoded = EditorSessionState.fromJSON(json) {
        state = decoded
      } else if let videoPath = args["videoPath"] as? String,
                let durationMs = EditorViewModel.durationMs(path: videoPath) {
        state = EditorSessionState.initial(clipPath: videoPath, sourceDurationMs: durationMs)
      } else {
        result(FlutterError(code: "MISSING_ARG", message: "videoPath or state is required", details: nil))
        return
      }
      self?.presentNativeEditor(state: state, newClipPath: args["newClipPath"] as? String, result: result)
    }
  }

  /// Presents the editor full screen and resolves Flutter's `result` once:
  /// exported → {action: exported, path, durationMs}; "+" →
  /// {action: addClip, state, remainingMs}; cancel → nil.
  private func presentNativeEditor(state: EditorSessionState, newClipPath: String?, result: @escaping FlutterResult) {
    guard
      let windowScene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
      let presenter = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
      result(FlutterError(code: "NO_ROOT_VC", message: "Could not find a presenting view controller", details: nil))
      return
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("adgag_native_export_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
    let viewModel = EditorViewModel(state: state, newClipPath: newClipPath)

    var didFinish = false
    let finish: (Any?) -> Void = { value in
      guard !didFinish else { return }
      didFinish = true
      viewModel.pause()
      presenter.dismiss(animated: true)
      result(value)
    }

    let editorView = EditorView(
      viewModel: viewModel,
      exportOutputURL: outputURL,
      onCancel: { finish(nil) },
      onExported: { path, durationMs in
        finish(["action": "exported", "path": path, "durationMs": durationMs] as [String: Any])
      },
      onAddClip: { stateJSON, remainingMs in
        finish(["action": "addClip", "state": stateJSON, "remainingMs": remainingMs] as [String: Any])
      })
    let hostingController = UIHostingController(rootView: editorView)
    hostingController.modalPresentationStyle = .fullScreen
    presenter.present(hostingController, animated: true)
  }
}
