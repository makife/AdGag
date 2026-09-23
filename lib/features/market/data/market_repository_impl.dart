import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../feed/domain/ad.dart";
import "../../subjects/domain/ad_subject.dart";
import "../domain/market_repository.dart";
import "../domain/user_search_result.dart";

/// NOTE on abuse (CLAUDE.md section 29): these are plain `ilike` reads
/// against already-public tables (RLS already limits what's returned to
/// active subjects / non-deleted profiles), so there's no privilege
/// escalation risk — but nothing here rate-limits repeated search
/// requests yet. Server-mediated rate limiting for search is explicitly
/// Phase G scope (section 52); do not treat its absence here as an
/// oversight when reviewing this file before Phase G lands.
final class MarketRepositoryImpl implements MarketRepository {
  MarketRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<List<AdSubject>> fetchTrendingSubjects({int limit = 15}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("ad_subjects")
        .select()
        .order("ads_count", ascending: false)
        .limit(limit);
    return rows.map(AdSubject.fromRow).toList(growable: false);
  }

  @override
  Future<List<Ad>> fetchFreshAds({int limit = 20}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles(username)")
        .eq("status", "ready")
        .order("published_at", ascending: false)
        .limit(limit);
    return rows.map(Ad.fromRow).toList(growable: false);
  }

  @override
  Future<List<AdSubject>> searchSubjects(String query, {int limit = 20}) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <AdSubject>[];
    }
    final List<Map<String, dynamic>> rows = await _client
        .from("ad_subjects")
        .select()
        .ilike("display_name", "%$trimmed%")
        .order("ads_count", ascending: false)
        .limit(limit);
    return rows.map(AdSubject.fromRow).toList(growable: false);
  }

  @override
  Future<List<UserSearchResult>> searchUsers(String query, {int limit = 20}) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <UserSearchResult>[];
    }
    final List<Map<String, dynamic>> rows = await _client
        .from("profiles")
        .select("id, username, display_name")
        .ilike("username", "%$trimmed%")
        .limit(limit);
    return rows.map(UserSearchResult.fromRow).toList(growable: false);
  }
}
