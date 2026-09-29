import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../profile/domain/public_profile.dart";
import "../domain/follow_repository.dart";

final class FollowRepositoryImpl implements FollowRepository {
  FollowRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  String get _requireUserId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const app_error.AuthException("Sign in to follow.");
    }
    return id;
  }

  @override
  Future<void> follow(String userId) async {
    try {
      await _client.from("follows").insert(<String, dynamic>{
        "follower_id": _requireUserId,
        "following_id": userId,
      });
    } on supa.PostgrestException catch (e) {
      if (e.code == "23505") {
        return; // Already following — idempotent no-op rather than an error.
      }
      throw app_error.UnknownException(e.message, e);
    }
  }

  @override
  Future<void> unfollow(String userId) async {
    await _client
        .from("follows")
        .delete()
        .eq("follower_id", _requireUserId)
        .eq("following_id", userId);
  }

  @override
  Future<bool> isFollowing(String userId) async {
    final List<dynamic> rows = await _client
        .from("follows")
        .select("follower_id")
        .eq("follower_id", _requireUserId)
        .eq("following_id", userId)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<List<PublicProfile>> fetchFollowers(String userId, {int limit = 100}) =>
      _fetchSide(matchColumn: "following_id", embedFk: "follows_follower_id_fkey", userId: userId, limit: limit);

  @override
  Future<List<PublicProfile>> fetchFollowing(String userId, {int limit = 100}) =>
      _fetchSide(matchColumn: "follower_id", embedFk: "follows_following_id_fkey", userId: userId, limit: limit);

  /// `follows` has two FKs to `profiles`, so the embed must name which one
  /// (the PGRST201 lesson in CLAUDE.md).
  Future<List<PublicProfile>> _fetchSide({
    required String matchColumn,
    required String embedFk,
    required String userId,
    required int limit,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("follows")
        .select("profiles!$embedFk(id, username, display_name, avatar_url, bio)")
        .eq(matchColumn, userId)
        .order("created_at", ascending: false)
        .limit(limit);
    return rows
        .map((Map<String, dynamic> row) => row["profiles"])
        .whereType<Map<String, dynamic>>()
        .map(PublicProfile.fromRow)
        .toList(growable: false);
  }
}
