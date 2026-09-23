import "../../feed/domain/ad.dart";

/// Draft-Ad lifecycle before and during video processing (CLAUDE.md
/// section 38/39). Mutations are backed by SECURITY DEFINER RPCs rather
/// than direct table writes — see supabase/migrations/0005_ads.sql — so
/// ownership and the draft-only edit window are enforced server-side, not
/// just by RLS row checks.
abstract interface class DraftAdRepository {
  /// [inspiredByAdId] is the AD THIS lineage link (CLAUDE.md section 9) —
  /// null for an ordinary Ad, set to the origin Ad's id when the user
  /// pressed AD THIS. [dailyChallengeId] is validated server-side against
  /// the currently-active challenge (section 11) — passing a stale or
  /// future challenge id fails the call rather than silently ignoring it.
  Future<Ad> createDraft({
    required String subjectId,
    String? caption,
    String? inspiredByAdId,
    String? dailyChallengeId,
  });
  Future<Ad> updateDraft({required String adId, String? subjectId, String? caption});
  Future<void> deleteAd(String adId);

  /// Re-fetches a single Ad by id. Used to poll for the draft ->
  /// uploading -> processing -> ready transition after a video upload
  /// completes (CLAUDE.md section 19), since the transition itself
  /// happens server-side (mux-webhook), not from any client call.
  Future<Ad> getById(String adId);
}
