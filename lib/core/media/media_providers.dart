import "package:flutter_riverpod/flutter_riverpod.dart";

import "local_video_prober.dart";
import "video_player_local_prober.dart";

/// Used by [CaptureStep] to probe a freshly captured/imported clip's
/// real duration (deciding whether it needs trimming down) — the only
/// remaining consumer of the local-media-probing abstraction now that
/// editing/export itself is entirely native (see `NativeEditorStep`).
final Provider<LocalVideoProber> localVideoProberProvider = Provider<LocalVideoProber>((ref) {
  return VideoPlayerLocalProber();
});
