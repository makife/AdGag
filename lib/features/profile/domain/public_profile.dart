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
  });

  factory PublicProfile.fromRow(Map<String, dynamic> row) {
    return PublicProfile(
      id: row["id"] as String,
      username: row["username"] as String,
      displayName: row["display_name"] as String?,
      bio: row["bio"] as String?,
      avatarUrl: row["avatar_url"] as String?,
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
}
