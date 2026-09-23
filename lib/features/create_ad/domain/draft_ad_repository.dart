import "../../feed/domain/ad.dart";

/// Draft-Ad lifecycle before video is attached (CLAUDE.md section 38/39).
/// Backed by SECURITY DEFINER RPCs rather than direct table writes — see
/// supabase/migrations/0005_ads.sql — so ownership and the draft-only edit
/// window are enforced server-side, not just by RLS row checks.
///
/// Video attach/upload (Phase C) and publish (draft -> ready, gated on
/// successful processing) are added to this interface once the
/// [VideoService] abstraction lands; they are deliberately not stubbed
/// here to avoid an interface that promises behavior this phase doesn't
/// implement.
abstract interface class DraftAdRepository {
  Future<Ad> createDraft({required String subjectId, String? caption});
  Future<Ad> updateDraft({required String adId, String? subjectId, String? caption});
  Future<void> deleteAd(String adId);
}
