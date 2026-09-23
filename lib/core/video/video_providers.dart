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
