import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../error/app_exception.dart" as app_error;
import "../utils/app_logger.dart";
import "video_service.dart";
import "video_upload_session.dart";

/// Mux implementation of [VideoService]. Swapping providers later (section
/// 60) means writing a new class here and in
/// supabase/functions/create-upload-session + mux-webhook — nothing in
/// feature code (feed, create_ad) changes, since they only ever depend on
/// the [VideoService] interface.
final class MuxVideoService implements VideoService {
  MuxVideoService(this._client);

  final supa.SupabaseClient _client;
  final _log = AppLogger.named("MuxVideoService");

  @override
  Future<VideoUploadSession> createUploadSession(String adId) async {
    _log.info("create-upload-session: requesting for adId=$adId");
    try {
      final supa.FunctionResponse response = await _client.functions.invoke(
        "create-upload-session",
        body: <String, dynamic>{"adId": adId},
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final String? uploadUrl = data["uploadUrl"] as String?;
      if (uploadUrl == null) {
        _log.warning("create-upload-session: 200 response missing uploadUrl", data);
        throw const app_error.UnknownException("UPLOAD_SESSION_RESPONSE_INVALID: missing uploadUrl");
      }
      _log.info("create-upload-session: got uploadUrl (host only, never the signed URL itself): "
          "${Uri.tryParse(uploadUrl)?.host}");
      return VideoUploadSession(uploadUrl: uploadUrl);
    } on supa.FunctionException catch (e) {
      // videoeditor5.txt real-device bug: this used to collapse every
      // failure shape into a single generic "Could not start upload"
      // whenever `e.details` wasn't a Map with a string "error" key —
      // which is exactly what happens for status==0 (request never
      // reached the function at all — network/DNS/relay failure, no
      // structured server response possible) and for any relay-level
      // failure. Every branch here now logs the actual stage-specific
      // diagnostic (status, reasonPhrase, and whatever's in details —
      // none of that is Mux/Supabase secret material, only counts/HTTP
      // metadata/our own function's non-secret error codes) before
      // throwing, and the thrown message itself carries a distinct code
      // instead of the same string every time.
      final Object? errorBody = e.details;
      final String? code = errorBody is Map && errorBody["error"] is String ? errorBody["error"] as String : null;
      final String? detail = errorBody is Map && errorBody["detail"] is String ? errorBody["detail"] as String : null;
      if (e.status == 0) {
        // Request never reached the Edge Function at all — no internet,
        // DNS failure, or the function URL/project ref itself is wrong.
        // This is the one failure mode a server-side fix can never
        // address, since the server was never reached.
        _log.severe(
          "create-upload-session: REQUEST_NEVER_REACHED_FUNCTION (status=0 — network/DNS, not a server error)",
          e,
        );
        throw app_error.UnknownException("UPLOAD_SESSION_UNREACHABLE: no response from server (check network)", e);
      }
      _log.severe(
        "create-upload-session: HTTP ${e.status} ${e.reasonPhrase ?? ''} code=$code detail=${detail ?? errorBody}",
        e,
      );
      final String message = code != null
          ? "UPLOAD_SESSION_FAILED: $code${detail != null ? ' ($detail)' : ''} [HTTP ${e.status}]"
          : "UPLOAD_SESSION_FAILED: non-JSON/relay-level error [HTTP ${e.status}]";
      throw app_error.UnknownException(message, e);
    }
  }

  @override
  String playbackUrl(String playbackId) => "https://stream.mux.com/$playbackId.m3u8";

  @override
  String thumbnailUrl(String playbackId) => "https://image.mux.com/$playbackId/thumbnail.jpg?time=0";
}
