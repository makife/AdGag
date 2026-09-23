import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../domain/ad_subject.dart";
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
}
