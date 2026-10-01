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
    this.likeCount = 0,
    this.likedByMe = false,
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
      likeCount: (row["like_count"] as num?)?.toInt() ?? 0,
      // RLS shows each user only their own comment_likes rows, so the embed
      // is non-empty exactly when the signed-in user liked this review.
      likedByMe: (row["comment_likes"] as List?)?.isNotEmpty ?? false,
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

  /// Likes on this review (server-maintained).
  final int likeCount;

  /// Whether the signed-in user liked it.
  final bool likedByMe;

  bool get isReply => parentId != null;

  Comment withReplyCount(int count) => _copy(replyCount: count < 0 ? 0 : count);

  /// This review liked (or not) by the signed-in user, count adjusted.
  Comment withLike({required bool liked}) => liked == likedByMe
      ? this
      : _copy(likedByMe: liked, likeCount: (likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31));

  Comment _copy({int? replyCount, int? likeCount, bool? likedByMe}) => Comment(
        id: id,
        adId: adId,
        userId: userId,
        body: body,
        createdAt: createdAt,
        parentId: parentId,
        replyCount: replyCount ?? this.replyCount,
        username: username,
        avatarUrl: avatarUrl,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}
