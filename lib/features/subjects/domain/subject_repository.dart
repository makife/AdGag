import "../../feed/domain/ad.dart";
import "ad_subject.dart";
import "subject_ads_sort.dart";

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

  /// Ads for the AdSubject page's Trending/Top/New tabs (section 10).
  /// Unlike [FeedRepository], this is a single bounded page (no cursor
  /// pagination yet) — acceptable for a secondary surface today; revisit
  /// if a subject regularly needs more than [limit] results browsable.
  Future<List<Ad>> fetchAdsForSubject({
    required String subjectId,
    required SubjectAdsSort sort,
    int limit = 30,
  });
}
