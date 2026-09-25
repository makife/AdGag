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
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let videoPath = args["videoPath"] as? String
      else {
        result(FlutterError(code: "MISSING_ARG", message: "videoPath is required", details: nil))
        return
      }
      self?.presentNativeEditor(videoPath: videoPath, result: result)
    }
  }

  /// Presents the native editor screen (`EditorView`/`EditorViewModel`,
  /// see those files' own doc comments) modally over whatever's
  /// currently key-window-visible, and resolves Flutter's pending
  /// `result` when the user either exports (path/duration) or cancels
  /// (`nil` — not an error, matching how the rest of the creation flow
  /// already treats "user backed out").
  private func presentNativeEditor(videoPath: String, result: @escaping FlutterResult) {
    guard
      let windowScene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
      let presenter = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
      result(FlutterError(code: "NO_ROOT_VC", message: "Could not find a presenting view controller", details: nil))
      return
    }

    let sourceURL = URL(fileURLWithPath: videoPath)
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("adgag_native_export_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
    let viewModel = EditorViewModel(sourceURL: sourceURL)

    var didFinish = false
    let finish: (String?, Double?) -> Void = { path, durationSeconds in
      guard !didFinish else { return }
      didFinish = true
      presenter.dismiss(animated: true)
      if let path, let durationSeconds {
        result(["path": path, "durationMs": Int(durationSeconds * 1000)])
      } else {
        result(nil)
      }
    }

    let editorView = EditorView(
      viewModel: viewModel,
      exportOutputURL: outputURL,
      onCancel: { finish(nil, nil) },
      onExported: { path, durationSeconds in finish(path, durationSeconds) }
    )
    let hostingController = UIHostingController(rootView: editorView)
    hostingController.modalPresentationStyle = .fullScreen
    presenter.present(hostingController, animated: true)
  }
}
