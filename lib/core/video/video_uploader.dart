import "upload_cancel_token.dart";

/// Uploads a local video file directly to a provider-issued upload URL
/// (CLAUDE.md section 18: the file "should NOT pass through the primary
/// application API server"). Provider-agnostic — works for any pre-signed
/// PUT-style upload URL, so it isn't part of [VideoService] itself.
abstract interface class VideoUploader {
  /// [onProgress] receives values in `[0.0, 1.0]`. Throws on failure after
  /// its internal retry budget is exhausted (section 39: "retry
  /// intelligently" — bounded, not infinite).
  Future<void> upload({
    required String uploadUrl,
    required String filePath,
    required void Function(double progress) onProgress,
    UploadCancelToken? cancelToken,
  });
}
