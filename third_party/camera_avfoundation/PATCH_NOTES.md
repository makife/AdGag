# camera_avfoundation 0.9.23+2 — AdGag patch: live AR face effects (iOS)

Vendored from pub.dev (BSD-3, LICENSE kept; `example/` and `test/` omitted,
dev_dependencies removed) and used via `dependency_overrides` in the root
pubspec.yaml. iOS twin of `third_party/camera_android_camerax` "Live AR".

## Changes (all marked `ADGAG PATCH`)

1. `Sources/camera_avfoundation/AdGagAr.swift` (new): the `adgag/ar` method
   channel (`setEffect`, `isPipelineBound` → always true, `previewInfo` →
   nil, `lastError` → nil), Vision face landmarks (`VNDetectFaceLandmarksRequest`,
   on-device), per-face smoothing, and `process(buffer, seconds)` which draws
   the picked effect INTO the BGRA camera frame with Core Graphics.
2. `Sources/camera_avfoundation/ArEffects.swift` (new): the 22 effects, a
   line-for-line port of the Android ArEffects.kt (face units, same shapes,
   colours, timing).
3. `CameraPlugin.swift` `register(with:)`: `AdGagAr.attach(messenger:)`.
4. `DefaultCamera.swift` `captureOutput(_:didOutput:from:)`: calls
   `AdGagAr.process` on each video frame BEFORE it is published to the
   preview texture and appended to the AVAssetWriter — this plugin records
   the same buffers it previews, so preview and recording show the same
   picture, and no camera reopen is ever needed to turn AR on.

With no effect picked `process` returns immediately. Detection runs
synchronously on the capture queue on every other frame (before anything is
drawn into that frame); faces older than 0.5s aren't drawn. Buffers arrive
upright for the device orientation (the plugin sets videoOrientation; the
front camera's is mirrored), so Vision gets `.up`. Only 32BGRA frames
(the plugin's default) are drawn into.

New .swift files are picked up by the podspec's `Sources/camera_avfoundation*/**`
glob and by Package.swift's target path — no project edits.

## Removing it

Delete this folder and the `camera_avfoundation` entry under
`dependency_overrides`; the app's AR button would then do nothing on iOS
(gate it back to Android in camera_record_view.dart `_arSupported`).
