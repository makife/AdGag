/// The authenticated identity plus its public profile row. Kept distinct
/// from a future richer `Profile` model (avatar, bio, follower counts —
/// Phase B) so the auth feature doesn't depend on social-core fields it
/// doesn't need.
final class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
  });

  factory AppUser.fromProfileRow(Map<String, dynamic> row, {required String email}) {
    return AppUser(
      id: row["id"] as String,
      email: email,
      username: row["username"] as String,
      displayName: row["display_name"] as String? ?? row["username"] as String,
    );
  }

  final String id;
  final String email;
  final String username;
  final String displayName;
}
