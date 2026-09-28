import "video_upload_session.dart";

/// Client-side surface of the video provider abstraction (CLAUDE.md
/// section 18). The full `VideoService` responsibility list in section 18
/// — createUploadSession/getPlaybackInfo/deleteAsset/verifyWebhook/
/// getThumbnail — spans both this client interface and the server-side
/// Edge Functions in supabase/functions/ (create-upload-session,
/// mux-webhook). `verifyWebhook` in particular is server-only by
/// necessity: it needs the provider's signing secret, which must never
/// reach the client.
///
/// [playbackUrl]/[thumbnailUrl] are pure functions, not network calls —
/// Mux (and most providers) derive both deterministically from the
/// `playback_id` already present in Ad metadata, so no extra round trip is
/// needed just to start playback.
abstract interface class VideoService {
  Future<VideoUploadSession> createUploadSession(String adId);

  String playbackUrl(String playbackId);

  String thumbnailUrl(String playbackId);

  /// A short, silent, looping animated image of the clip's first seconds —
  /// for small previews (Market) that should move without spending a
  /// hardware video decoder (the native editor needs every one of them).
  String animatedPreviewUrl(String playbackId);
}
