import "ad.dart";
import "feed_page.dart";

/// Which feed the Home tab shows (CLAUDE.md section 15: "For You" and
/// "Following").
enum FeedKind {
  /// Everyone's Ads, heuristically ranked (get_feed_page).
  forYou,

  /// Ads by accounts the viewer follows, newest first (get_following_feed_page).
  following,
}

/// Feed access, kept behind an interface so the ranking implementation can
/// be swapped (Postgres heuristic now -> precomputed candidate pools later
/// -> dedicated ranking infra at large scale) without the client changing
/// (CLAUDE.md section 16/59).
///
/// Phase B implements this with straightforward freshness ordering only
/// ("basic feed metadata" per section 52). The heuristic signals listed in
/// section 16 (completion rate, SOLD rate, AD THIS rate, ...) are Phase F
/// work and slot in behind this same method signature.
abstract interface class FeedRepository {
  /// One page of the [kind] feed. The cursor is only valid for the same kind.
  Future<FeedPage> fetchPage({FeedKind kind = FeedKind.forYou, String? cursor, int limit = 10});

  /// Single Ad by id, with the same display embeds as [fetchPage] — used
  /// by the `/ad/:id` deep-link target (section 33/54). Returns null if
  /// the Ad doesn't exist or isn't `ready` (a blocked/deleted/draft Ad
  /// shouldn't be viewable via a shared link either).
  Future<Ad?> getById(String adId);

  /// The AD THIS chain one step down: ready Ads made by pressing AD THIS on
  /// [adId] (their inspired_by_ad_id), newest first.
  Future<List<Ad>> fetchAdThisChildren(String adId, {int limit = 60});
}
