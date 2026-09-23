import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
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
  Future<int> followerCount(String userId) async {
    final response = await _client
        .from("follows")
        .select()
        .eq("following_id", userId)
        .count(supa.CountOption.exact);
    return response.count;
  }

  @override
  Future<int> followingCount(String userId) async {
    final response = await _client
        .from("follows")
        .select()
        .eq("follower_id", userId)
        .count(supa.CountOption.exact);
    return response.count;
  }
}
