/// A REVIEW in product language (CLAUDE.md section 8), `comments` in the
/// schema.
final class Comment {
  const Comment({
    required this.id,
    required this.adId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.username,
  });

  factory Comment.fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic>? profileEmbed = row["profiles"] as Map<String, dynamic>?;
    return Comment(
      id: row["id"] as String,
      adId: row["ad_id"] as String,
      userId: row["user_id"] as String,
      body: row["body"] as String,
      createdAt: DateTime.parse(row["created_at"] as String),
      username: profileEmbed?["username"] as String?,
    );
  }

  final String id;
  final String adId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String? username;
}
