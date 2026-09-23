import "package:flutter_test/flutter_test.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "package:adgag/core/video/mux_video_service.dart";

void main() {
  // playbackUrl/thumbnailUrl are pure string builders — no network call —
  // so a client pointed at a fake project is enough to construct the
  // service under test.
  final MuxVideoService service =
      MuxVideoService(SupabaseClient("https://example.supabase.co", "anon-key"));

  group("MuxVideoService.playbackUrl", () {
    test("builds an HLS manifest URL from a playback id", () {
      expect(
        service.playbackUrl("abc123"),
        "https://stream.mux.com/abc123.m3u8",
      );
    });
  });

  group("MuxVideoService.thumbnailUrl", () {
    test("builds a thumbnail image URL from a playback id", () {
      expect(
        service.thumbnailUrl("abc123"),
        "https://image.mux.com/abc123/thumbnail.jpg?time=0",
      );
    });
  });
}
