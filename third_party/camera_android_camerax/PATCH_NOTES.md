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
