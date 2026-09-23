import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../feed/domain/ad.dart";
import "../domain/ad_subject.dart";
import "../domain/subject_ads_sort.dart";
import "../domain/subject_repository.dart";

final class SubjectRepositoryImpl implements SubjectRepository {
  SubjectRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<AdSubject> getOrCreateSubject(String text, {String locale = "en"}) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "get_or_create_ad_subject",
        params: <String, dynamic>{"input_text": text, "input_locale": locale},
      );
      return AdSubject.fromRow(row);
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<AdSubject?> getSubjectById(String id) async {
    final Map<String, dynamic>? row =
        await _client.from("ad_subjects").select().eq("id", id).maybeSingle();
    return row == null ? null : AdSubject.fromRow(row);
  }

  @override
  Future<List<Ad>> fetchAdsForSubject({
    required String subjectId,
    required SubjectAdsSort sort,
    int limit = 30,
  }) async {
    supa.PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles!ads_user_id_fkey(username)")
        .eq("subject_id", subjectId)
        .eq("status", "ready");

    if (sort == SubjectAdsSort.trending) {
      final DateTime sevenDaysAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));
      query = query.gte("published_at", sevenDaysAgo.toIso8601String());
    }

    final supa.PostgrestTransformBuilder<List<Map<String, dynamic>>> sorted = switch (sort) {
      SubjectAdsSort.trending || SubjectAdsSort.top => query.order("sold_count", ascending: false),
      SubjectAdsSort.newest => query.order("published_at", ascending: false),
    };

    final List<Map<String, dynamic>> rows = await sorted.limit(limit);
    return rows.map(Ad.fromRow).toList(growable: false);
  }
}
