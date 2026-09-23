/// Mirrors the `notification_type` Postgres enum
/// (supabase/migrations/0014_notifications.sql). CLAUDE.md section 32.
enum NotificationType {
  newFollower,
  newReview,
  adThis;

  static NotificationType fromDb(String value) => switch (value) {
        "new_follower" => NotificationType.newFollower,
        "new_review" => NotificationType.newReview,
        "ad_this" => NotificationType.adThis,
        _ => throw ArgumentError("Unknown notification_type: $value"),
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

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic>? actorEmbed = row["profiles"] as Map<String, dynamic>?;
    return AppNotification(
      id: row["id"] as String,
      type: NotificationType.fromDb(row["type"] as String),
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
}
