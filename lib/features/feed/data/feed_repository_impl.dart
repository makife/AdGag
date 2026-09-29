import "dart:convert";

import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../domain/ad.dart";
import "../domain/feed_page.dart";
import "../domain/feed_repository.dart";

/// Phase F implementation: calls the `get_feed_page` RPC (see
/// supabase/migrations/0010_feed_ranking.sql), which owns the actual
/// heuristic ranking (CLAUDE.md section 16/59) — this class only handles
/// the keyset-pagination cursor and mapping rows to [Ad]. Swapping the
/// ranking formula later means changing that SQL function, not this file
/// or anything upstream of [FeedRepository].
final class FeedRepositoryImpl implements FeedRepository {
  FeedRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<FeedPage> fetchPage({FeedKind kind = FeedKind.forYou, String? cursor, int limit = 10}) async {
    final _Cursor? decoded = cursor == null ? null : _Cursor.decode(cursor);

    // Fetch one extra row to know whether a next page exists without a
    // separate COUNT query (same trick as the pre-ranking implementation).
    // Both RPCs return the same row shape and keyset cursor (for Following,
    // rank_score is the publish time) — see 0022_following_feed_replies_mentions.sql.
    final List<Map<String, dynamic>> rows = await _client.rpc<List<dynamic>>(
      switch (kind) {
        FeedKind.forYou => "get_feed_page",
        FeedKind.following => "get_following_feed_page",
      },
      params: <String, dynamic>{
        "p_cursor_score": decoded?.score,
        "p_cursor_id": decoded?.id,
        "p_limit": limit + 1,
      },
    ).then((List<dynamic> value) => value.cast<Map<String, dynamic>>());

    final bool hasMore = rows.length > limit;
    final List<Map<String, dynamic>> pageRows = hasMore ? rows.sublist(0, limit) : rows;
    final Map<String, String?> avatars = await _avatarsFor(pageRows);
    final List<Ad> ads = pageRows
        .map(
          (Map<String, dynamic> row) =>
              Ad.fromRow(<String, dynamic>{...row, "creator_avatar_url": avatars[row["user_id"]]}),
        )
        .toList(growable: false);

    String? nextCursor;
    if (hasMore) {
      final Map<String, dynamic> last = pageRows.last;
      nextCursor = _Cursor(score: (last["rank_score"] as num).toDouble(), id: last["id"] as String).encode();
    }

    return FeedPage(ads: ads, nextCursor: nextCursor);
  }

  /// Creator avatars for a page of feed rows — ONE query for the whole page
  /// (the get_feed_page RPC only returns creator_username). Best-effort:
  /// a failure just means no avatars, never a failed feed page.
  Future<Map<String, String?>> _avatarsFor(List<Map<String, dynamic>> rows) async {
    final List<String> userIds = rows.map((Map<String, dynamic> r) => r["user_id"] as String).toSet().toList();
    if (userIds.isEmpty) {
      return const <String, String?>{};
    }
    try {
      final List<Map<String, dynamic>> profiles =
          await _client.from("profiles").select("id, avatar_url").inFilter("id", userIds);
      return <String, String?>{
        for (final Map<String, dynamic> p in profiles) p["id"] as String: p["avatar_url"] as String?,
      };
    } catch (_) {
      return const <String, String?>{};
    }
  }

  @override
  Future<Ad?> getById(String adId) async {
    final Map<String, dynamic>? row = await _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles!ads_user_id_fkey(username, avatar_url)")
        .eq("id", adId)
        .eq("status", "ready")
        .maybeSingle();
    return row == null ? null : Ad.fromRow(row);
  }

  @override
  Future<List<Ad>> fetchAdThisChildren(String adId, {int limit = 60}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles!ads_user_id_fkey(username, avatar_url)")
        .eq("inspired_by_ad_id", adId)
        .eq("status", "ready")
        .order("published_at", ascending: false)
        .limit(limit);
    return rows.map(Ad.fromRow).toList(growable: false);
  }
}

final class _Cursor {
  const _Cursor({required this.score, required this.id});

  static final RegExp _uuidPattern =
      RegExp(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

  factory _Cursor.decode(String encoded) {
    final Map<String, dynamic> json = jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map<String, dynamic>;
    final double score = (json["s"] as num).toDouble();
    final String id = json["id"] as String;

    // Cursors are opaque to callers but still get passed as literal RPC
    // params — validate shape so a malformed/tampered cursor fails fast.
    if (!_uuidPattern.hasMatch(id)) {
      throw const FormatException("Invalid feed cursor");
    }

    return _Cursor(score: score, id: id);
  }

  final double score;
  final String id;

  String encode() {
    return base64Url.encode(utf8.encode(jsonEncode(<String, dynamic>{"s": score, "id": id})));
  }
}
