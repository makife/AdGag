import "ad.dart";
import "feed_page.dart";

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
  Future<FeedPage> fetchPage({String? cursor, int limit = 10});

  /// Single Ad by id, with the same display embeds as [fetchPage] — used
  /// by the `/ad/:id` deep-link target (section 33/54). Returns null if
  /// the Ad doesn't exist or isn't `ready` (a blocked/deleted/draft Ad
  /// shouldn't be viewable via a shared link either).
  Future<Ad?> getById(String adId);
}
