import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../feed/domain/ad.dart";
import "../domain/draft_ad_repository.dart";

final class DraftAdRepositoryImpl implements DraftAdRepository {
  DraftAdRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<Ad> createDraft({required String subjectId, String? caption}) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "create_draft_ad",
        params: <String, dynamic>{"p_subject_id": subjectId, "p_caption": caption},
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
    try {
      await _client.rpc<dynamic>("delete_own_ad", params: <String, dynamic>{"p_ad_id": adId});
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<Ad> getById(String adId) async {
    final Map<String, dynamic> row = await _client.from("ads").select().eq("id", adId).single();
    return Ad.fromRow(row);
  }
}
