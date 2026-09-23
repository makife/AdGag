import "package:dio/dio.dart" as dio;

/// Cancellation handle for an in-flight upload (CLAUDE.md section 39:
/// "support cancellation"). Wraps `dio.CancelToken` so nothing outside
/// lib/core/video/ needs to import dio directly.
final class UploadCancelToken {
  final dio.CancelToken _inner = dio.CancelToken();

  void cancel() => _inner.cancel("Upload cancelled by user");

  bool get isCancelled => _inner.isCancelled;

  dio.CancelToken get internalDioToken => _inner;
}
