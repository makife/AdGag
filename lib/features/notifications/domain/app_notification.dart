/// Mirrors the `notification_type` Postgres enum
/// (supabase/migrations/0014_notifications.sql). CLAUDE.md section 32.
enum NotificationType {
  newFollower,
  newReview,
  adThis,
  reviewReply,
  mention,

  /// The user's Ad reached a SOLD milestone (payload count: 1, 10, 50, 100…).
  soldMilestone,

  /// The user's Ad reached a GAG! (share) milestone (10, 50, 100…).
  gagMilestone;

  /// Null for a type this build doesn't know (added server-side later) —
  /// the list skips it instead of failing as a whole. (It used to throw,
  /// which would have broken the whole list for older builds.)
  static NotificationType? fromDb(String value) => switch (value) {
        "new_follower" => NotificationType.newFollower,
        "new_review" => NotificationType.newReview,
        "ad_this" => NotificationType.adThis,
        "review_reply" => NotificationType.reviewReply,
        "mention" => NotificationType.mention,
        "sold_milestone" => NotificationType.soldMilestone,
        "gag_milestone" => NotificationType.gagMilestone,
        _ => null,
      };
}

final class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.payload,
    this.actorId,
    this.actorUsername,
    this.readAt,
  });

  /// Null when the row's type is unknown to this build.
  static AppNotification? tryFromRow(Map<String, dynamic> row) {
    final NotificationType? type = NotificationType.fromDb(row["type"] as String);
    if (type == null) {
      return null;
    }
    final Map<String, dynamic>? actorEmbed = row["profiles"] as Map<String, dynamic>?;
    return AppNotification(
      id: row["id"] as String,
      type: type,
      createdAt: DateTime.parse(row["created_at"] as String),
      payload: (row["payload"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      actorId: row["actor_id"] as String?,
      actorUsername: actorEmbed?["username"] as String?,
      readAt: row["read_at"] == null ? null : DateTime.parse(row["read_at"] as String),
    );
  }

  final String id;
  final NotificationType type;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String? actorId;
  final String? actorUsername;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  String? get adId => payload["ad_id"] as String?;

  /// The milestone reached (milestone notifications only).
  int? get count => (payload["count"] as num?)?.toInt();
}
