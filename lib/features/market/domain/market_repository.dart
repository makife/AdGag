import "../../feed/domain/ad.dart";
import "../../subjects/domain/ad_subject.dart";
import "user_search_result.dart";

/// MARKET / Discovery (CLAUDE.md section 12) — "the market of ideas/Ads",
/// not a commerce marketplace. Covers the subset of section 12's possible
/// sections implemented at MVP: Trending Subjects, Fresh Ads, and search
/// over both subjects and users. Rising Creators / Subjects You May Like
/// are explicitly deferred — extend this interface when they're built,
/// rather than guessing at their shape now.
abstract interface class MarketRepository {
  Future<List<AdSubject>> fetchTrendingSubjects({int limit = 15});

  Future<List<Ad>> fetchFreshAds({int limit = 20});

  Future<List<AdSubject>> searchSubjects(String query, {int limit = 20});

  Future<List<UserSearchResult>> searchUsers(String query, {int limit = 20});
}
