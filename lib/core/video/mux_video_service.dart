import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../error/app_exception.dart" as app_error;
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

  @override
  Future<VideoUploadSession> createUploadSession(String adId) async {
    try {
      final supa.FunctionResponse response = await _client.functions.invoke(
        "create-upload-session",
        body: <String, dynamic>{"adId": adId},
      );
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      final String? uploadUrl = data["uploadUrl"] as String?;
      if (uploadUrl == null) {
        throw const app_error.UnknownException("Upload session response missing uploadUrl");
      }
      return VideoUploadSession(uploadUrl: uploadUrl);
    } on supa.FunctionException catch (e) {
      final Object? errorBody = e.details;
      final String message = errorBody is Map && errorBody["error"] is String
          ? errorBody["error"] as String
          : "Could not start upload";
      throw app_error.UnknownException(message, e);
    }
  }

  @override
  String playbackUrl(String playbackId) => "https://stream.mux.com/$playbackId.m3u8";

  @override
  String thumbnailUrl(String playbackId) => "https://image.mux.com/$playbackId/thumbnail.jpg?time=0";
}
