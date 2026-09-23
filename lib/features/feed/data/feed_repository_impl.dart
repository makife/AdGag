import "dart:convert";

import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../domain/ad.dart";
import "../domain/feed_page.dart";
import "../domain/feed_repository.dart";

/// Phase B implementation: correct cursor pagination over `status = 'ready'`
/// Ads ordered by freshness, with no heuristic ranking yet (see
/// [FeedRepository] doc comment). Keyset pagination on
/// `(published_at, id)` rather than OFFSET, so page N+1 stays O(limit) even
/// on a large table (CLAUDE.md section 16/57).
final class FeedRepositoryImpl implements FeedRepository {
  FeedRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<FeedPage> fetchPage({String? cursor, int limit = 10}) async {
    // Embed subject display name + creator username so the feed overlay
    // (section 6) doesn't need a second round trip per card — this is the
    // "basic feed metadata" the query returns, never video bytes.
    supa.PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles(username)")
        .eq("status", "ready");

    final _Cursor? decoded = cursor == null ? null : _Cursor.decode(cursor);
    if (decoded != null) {
      query = query.or(
        "published_at.lt.${decoded.publishedAtIso},"
        "and(published_at.eq.${decoded.publishedAtIso},id.lt.${decoded.id})",
      );
    }

    // Fetch one extra row to know whether a next page exists without a
    // separate COUNT query.
    final List<Map<String, dynamic>> rows = await query
        .order("published_at", ascending: false)
        .order("id", ascending: false)
        .limit(limit + 1);

    final bool hasMore = rows.length > limit;
    final List<Map<String, dynamic>> pageRows = hasMore ? rows.sublist(0, limit) : rows;
    final List<Ad> ads = pageRows.map(Ad.fromRow).toList(growable: false);

    String? nextCursor;
    if (hasMore && ads.isNotEmpty) {
      final Ad last = ads.last;
      nextCursor = _Cursor(publishedAtIso: last.publishedAt!.toIso8601String(), id: last.id).encode();
    }

    return FeedPage(ads: ads, nextCursor: nextCursor);
  }
}

final class _Cursor {
  const _Cursor({required this.publishedAtIso, required this.id});

  static final RegExp _uuidPattern =
      RegExp(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

  factory _Cursor.decode(String encoded) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map<String, dynamic>;
    final String publishedAtIso = json["p"] as String;
    final String id = json["id"] as String;

    // Cursors are opaque to callers but still get here as plain strings
    // interpolated into a PostgREST `.or()` filter — validate shape so a
    // malformed/tampered cursor fails fast with a clear error instead of
    // producing an unexpected filter string.
    DateTime.parse(publishedAtIso);
    if (!_uuidPattern.hasMatch(id)) {
      throw const FormatException("Invalid feed cursor");
    }

    return _Cursor(publishedAtIso: publishedAtIso, id: id);
  }

  final String publishedAtIso;
  final String id;

  String encode() {
    return base64Url.encode(utf8.encode(jsonEncode(<String, String>{"p": publishedAtIso, "id": id})));
  }
}
