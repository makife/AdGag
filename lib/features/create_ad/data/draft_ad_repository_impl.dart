import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../feed/domain/ad.dart";
import "../domain/draft_ad_repository.dart";

final class DraftAdRepositoryImpl implements DraftAdRepository {
  DraftAdRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<Ad> createDraft({
    required String subjectId,
    String? caption,
    String? inspiredByAdId,
    String? dailyChallengeId,
  }) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "create_draft_ad",
        params: <String, dynamic>{
          "p_subject_id": subjectId,
          "p_caption": caption,
          "p_inspired_by_ad_id": inspiredByAdId,
          "p_daily_challenge_id": dailyChallengeId,
        },
      );
      return Ad.fromRow(row);
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<Ad> updateDraft({required String adId, String? subjectId, String? caption}) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "update_draft_ad",
        params: <String, dynamic>{
          "p_ad_id": adId,
          "p_subject_id": subjectId,
          "p_caption": caption,
        },
      );
      return Ad.fromRow(row);
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<void> deleteAd(String adId) async {
    // delete-ad hides the Ad (delete_own_ad, with our JWT) and then deletes
    // its video at Mux — the privacy policy promises the video goes too.
    try {
      await _client.functions.invoke("delete-ad", body: <String, dynamic>{"adId": adId});
    } on supa.FunctionException catch (e) {
      final Object? details = e.details;
      final String? detail = details is Map && details["detail"] is String ? details["detail"] as String : null;
      throw app_error.ValidationException(detail ?? "AD_DELETE_FAILED [HTTP ${e.status}]", e);
    }
  }

  @override
  Future<Ad> getById(String adId) async {
    final Map<String, dynamic> row = await _client.from("ads").select().eq("id", adId).single();
    return Ad.fromRow(row);
  }
}
