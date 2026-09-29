/// The public-facing subset of `profiles` (CLAUDE.md section 13) — no
/// email or other private fields, matching what `profiles_select_public`
/// (0002_profiles_and_auth_trigger.sql) actually exposes.
final class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  factory PublicProfile.fromRow(Map<String, dynamic> row) {
    return PublicProfile(
      id: row["id"] as String,
      username: row["username"] as String,
      displayName: row["display_name"] as String?,
      bio: row["bio"] as String?,
      avatarUrl: row["avatar_url"] as String?,
      // Server-maintained counters (0021_follow_counts_and_asset_cleanup.sql);
      // absent when a query selects only some columns.
      followersCount: (row["followers_count"] as num?)?.toInt() ?? 0,
      followingCount: (row["following_count"] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final int followersCount;
  final int followingCount;
}
