import "ad_subject.dart";

/// Abstraction over subject lookup/creation. Canonicalization
/// (normalization + alias resolution) happens server-side
/// (`get_or_create_ad_subject`, see supabase/migrations/0004_ad_subjects.sql)
/// so the client never has to duplicate that logic or race another client
/// creating the "same" subject with slightly different casing.
abstract interface class SubjectRepository {
  /// Resolves [text] to an existing AdSubject or creates a new one. This is
  /// the entry point used by the creation flow's subject picker (Phase D).
  Future<AdSubject> getOrCreateSubject(String text, {String locale = "en"});

  Future<AdSubject?> getSubjectById(String id);
}
