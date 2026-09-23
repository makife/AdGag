/// A minimal profile shape for search results — Market/Discovery (section
/// 12) doesn't need the full auth-scoped `AppUser`, just enough to render
/// a result row and navigate to the profile.
final class UserSearchResult {
  const UserSearchResult({required this.id, required this.username, this.displayName});

  factory UserSearchResult.fromRow(Map<String, dynamic> row) {
    return UserSearchResult(
      id: row["id"] as String,
      username: row["username"] as String,
      displayName: row["display_name"] as String?,
    );
  }

  final String id;
  final String username;
  final String? displayName;
}
