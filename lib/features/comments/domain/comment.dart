/// A REVIEW in product language (CLAUDE.md section 8), `comments` in the
/// schema. Replies are one level deep: a reply's [parentId] is always a
/// top-level review (0022_following_feed_replies_mentions.sql).
final class Comment {
  const Comment({
    required this.id,
    required this.adId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.replyCount = 0,
    this.username,
    this.avatarUrl,
  });

  factory Comment.fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic>? profileEmbed = row["profiles"] as Map<String, dynamic>?;
    return Comment(
      id: row["id"] as String,
      adId: row["ad_id"] as String,
      userId: row["user_id"] as String,
      body: row["body"] as String,
      createdAt: DateTime.parse(row["created_at"] as String),
      parentId: row["parent_id"] as String?,
      replyCount: (row["reply_count"] as num?)?.toInt() ?? 0,
      username: profileEmbed?["username"] as String?,
      avatarUrl: profileEmbed?["avatar_url"] as String?,
    );
  }

  final String id;
  final String adId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// The top-level review this one answers; null for a top-level review.
  final String? parentId;

  /// Replies under this review (server-maintained; top-level reviews only).
  final int replyCount;
  final String? username;
  final String? avatarUrl;

  bool get isReply => parentId != null;

  Comment withReplyCount(int count) => Comment(
        id: id,
        adId: adId,
        userId: userId,
        body: body,
        createdAt: createdAt,
        parentId: parentId,
        replyCount: count < 0 ? 0 : count,
        username: username,
        avatarUrl: avatarUrl,
      );
}
