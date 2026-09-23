import "package:flutter_riverpod/flutter_riverpod.dart";

import "../supabase/supabase_providers.dart";
import "dio_video_uploader.dart";
import "mux_video_service.dart";
import "video_service.dart";
import "video_uploader.dart";

final Provider<VideoService> videoServiceProvider = Provider<VideoService>((ref) {
  return MuxVideoService(ref.watch(supabaseClientProvider));
});

final Provider<VideoUploader> videoUploaderProvider = Provider<VideoUploader>((ref) {
  return DioVideoUploader();
});

/// Shared across every feed video card so muting persists as the user
/// swipes (CLAUDE.md section 17: "Respect mute/audio state") rather than
/// resetting to unmuted on every new Ad.
final StateProvider<bool> isFeedMutedProvider = StateProvider<bool>((ref) => false);
