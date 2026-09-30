# camera_android_camerax 0.6.30 — AdGag patch

Vendored copy of the published `camera_android_camerax` 0.6.30 (BSD-3-Clause,
LICENSE preserved), wired in through `dependency_overrides` in the root
`pubspec.yaml`. Only `example/` and `test/` were left out.

## The bug it fixes

Every recording started with ~1.8s of frozen video on a real device. Upstream
`AndroidCameraCameraX.initializeCamera` binds `Preview + ImageCapture +
ImageAnalysis`; `startVideoCapturing` then unbinds ImageAnalysis (and
ImageCapture on LEGACY devices) and binds `VideoCapture` — each bind/unbind
reconfigures the camera capture session, right as the recording begins.
`stopVideoRecording` unbinds VideoCapture again, so it happened on every take.

## The patch (both in `lib/src/android_camera_camerax.dart`, marked `ADGAG PATCH`)

1. `initializeCamera` binds `Preview + VideoCapture` instead of
   `Preview + ImageCapture + ImageAnalysis`. `startVideoCapturing`'s own
   unbind/bind calls then become no-ops (they already check `isBound`).
2. `stopVideoRecording` no longer unbinds `VideoCapture`.

AdGag never calls `takePicture()` or `startImageStream()`; if it ever does,
those still bind their use case lazily (possibly reconfiguring the session
then, which is acceptable for a photo).

## Removing it

Delete this folder and the `camera_android_camerax` entry under
`dependency_overrides` once upstream binds VideoCapture ahead of time (or
exposes a way to). Re-check the recording-start freeze on a device after.

## Live AR (added 2026-09-30, ADGAG PATCH)

Live face effects drawn on the camera frames themselves, so the preview and
the recording show the same thing:

- `AdGagAr.kt`: when the app picked an effect ("adgag/ar" channel,
  `setEffect`) before the camera binds, `ProcessCameraProviderProxyApi.bindToLifecycle`
  binds a `UseCaseGroup` of Preview + VideoCapture + an `ImageAnalysis`
  (ML Kit face detection through `MlKitAnalyzer`, `COORDINATE_SYSTEM_SENSOR`)
  + a CameraX `OverlayEffect` (targets PREVIEW | VIDEO_CAPTURE, queue depth 0).
  The draw listener sets `frame.sensorToBufferTransform` on the overlay canvas
  and draws each face's effect in face units (`FaceGeom.localToSensor`).
  `unbindAll` resets the AR state.
- `ArEffects.kt`: the artwork, procedural and left-right symmetric (the front
  camera's preview is mirrored, its recording isn't).
- `PreviewProxyApi.createSurfaceProvider` records the preview SurfaceRequest's
  TransformationInfo. With an effect CameraX hands the preview a GL-processed
  buffer (`hasCameraTransform == false`), which the plugin's own rotation
  logic would turn sideways — the app shows that texture itself, turned and
  mirrored exactly as `previewInfo` says (camera_record_view.dart `_preview`).
- Plugin `onAttachedToEngine` registers the channel.
- build.gradle: `camera-effects`, `camera-mlkit-vision` (same CameraX version)
  and `com.google.mlkit:face-detection` (bundled model).

Removing: delete AdGagAr.kt / ArEffects.kt, the three marked hooks and the
three dependencies; the app hides the AR button when the channel is missing.
