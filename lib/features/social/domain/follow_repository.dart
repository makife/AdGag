/// Follow/unfollow (CLAUDE.md section 15). Duplicate-follow prevention is a
/// database constraint (`follows` primary key), not client-side logic —
/// this interface just reflects that.
abstract interface class FollowRepository {
  Future<void> follow(String userId);
  Future<void> unfollow(String userId);
  Future<bool> isFollowing(String userId);
  Future<int> followerCount(String userId);
  Future<int> followingCount(String userId);
}
