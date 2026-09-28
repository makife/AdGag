import "dart:io";

import "package:flutter/services.dart";

/// The PHYSICAL orientation of the phone (accelerometer), independent of the
/// UI — the app is locked to portrait, so the UI orientation never changes.
/// The camera screen uses it to record a sideways-held phone as a landscape
/// video and to turn its icons upright.
///
/// Android only (MainActivity's `device_orientation` EventChannel). On iOS
/// the camera plugin already records in the physical orientation, so this
/// returns an empty stream there.
Stream<DeviceOrientation> physicalDeviceOrientation() {
  if (!Platform.isAndroid) {
    return const Stream<DeviceOrientation>.empty();
  }
  return const EventChannel("com.adgag.adgag/device_orientation")
      .receiveBroadcastStream()
      .map(
        (Object? name) => DeviceOrientation.values.firstWhere(
          (DeviceOrientation o) => o.name == name,
          orElse: () => DeviceOrientation.portraitUp,
        ),
      );
}
