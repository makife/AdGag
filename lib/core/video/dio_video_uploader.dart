import "dart:io";

import "package:dio/dio.dart" as dio;

import "../error/app_exception.dart" as app_error;
import "../utils/app_logger.dart";
import "upload_cancel_token.dart";
import "video_uploader.dart";

/// PUTs the raw video bytes to a pre-signed provider upload URL (Mux's
/// Direct Upload URLs, like most providers' pre-signed upload URLs, expect
/// the request body to be the file itself — NOT multipart/form-data).
final class DioVideoUploader implements VideoUploader {
  DioVideoUploader([dio.Dio? client]) : _dio = client ?? dio.Dio();

  final dio.Dio _dio;
  final _log = AppLogger.named("VideoUploader");

  static const int _maxAttempts = 3;

  @override
  Future<void> upload({
    required String uploadUrl,
    required String filePath,
    required void Function(double progress) onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    final File file = File(filePath);
    final int length = await file.length();
    Object? lastError;

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        return;
      }
      try {
        await _dio.put<void>(
          uploadUrl,
          data: file.openRead(),
          options: dio.Options(
            headers: <String, dynamic>{
              dio.Headers.contentLengthHeader: length,
              dio.Headers.contentTypeHeader: "video/mp4",
            },
          ),
          cancelToken: cancelToken?.internalDioToken,
          onSendProgress: (int sent, int total) {
            if (total > 0) {
              onProgress(sent / total);
            }
          },
        );
        return; // success
      } on dio.DioException catch (e) {
        if (e.type == dio.DioExceptionType.cancel) {
          return; // Not a failure — the caller cancelled intentionally.
        }
        lastError = e;
        _log.warning("Upload attempt $attempt/$_maxAttempts failed", e);
        if (attempt < _maxAttempts && _isRetryable(e)) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        break;
      }
    }

    throw app_error.NetworkException("Upload failed after $_maxAttempts attempt(s).", lastError);
  }

  bool _isRetryable(dio.DioException e) {
    // Retry transport-level failures (timeouts, connection drops), not
    // 4xx client errors (a stale/expired upload URL retrying won't fix).
    return e.type != dio.DioExceptionType.badResponse ||
        (e.response?.statusCode != null && e.response!.statusCode! >= 500);
  }
}
