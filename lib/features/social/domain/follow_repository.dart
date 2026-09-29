import "../../profile/domain/public_profile.dart";

/// Follow/unfollow (CLAUDE.md section 15). Duplicate-follow prevention is a
/// database constraint (`follows` primary key), not client-side logic —
/// this interface just reflects that. Follower/following COUNTS live on the
/// profile row (server-maintained, PublicProfile.followersCount), not here.
abstract interface class FollowRepository {
  Future<void> follow(String userId);
  Future<void> unfollow(String userId);
  Future<bool> isFollowing(String userId);

  /// People following [userId], newest first.
  Future<List<PublicProfile>> fetchFollowers(String userId, {int limit = 100});

  /// People [userId] follows, newest first.
  Future<List<PublicProfile>> fetchFollowing(String userId, {int limit = 100});
}
