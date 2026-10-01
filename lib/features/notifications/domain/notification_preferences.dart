/// Which notifications are PUSHED to the user's phones
/// (notification_preferences; no row = everything on). The in-app list
/// always shows everything.
final class NotificationPreferences {
  const NotificationPreferences({
    this.newFollowers = true,
    this.reviews = true,
    this.mentions = true,
    this.adThis = true,
  });

  factory NotificationPreferences.fromRow(Map<String, dynamic>? row) => row == null
      ? const NotificationPreferences()
      : NotificationPreferences(
          newFollowers: row["new_followers"] as bool? ?? true,
          reviews: row["reviews"] as bool? ?? true,
          mentions: row["mentions"] as bool? ?? true,
          adThis: row["ad_this"] as bool? ?? true,
        );

  final bool newFollowers;

  /// New reviews on your Ads and replies to your reviews.
  final bool reviews;
  final bool mentions;
  final bool adThis;

  NotificationPreferences copyWith({bool? newFollowers, bool? reviews, bool? mentions, bool? adThis}) =>
      NotificationPreferences(
        newFollowers: newFollowers ?? this.newFollowers,
        reviews: reviews ?? this.reviews,
        mentions: mentions ?? this.mentions,
        adThis: adThis ?? this.adThis,
      );

  Map<String, dynamic> toRow(String userId) => <String, dynamic>{
        "user_id": userId,
        "new_followers": newFollowers,
        "reviews": reviews,
        "mentions": mentions,
        "ad_this": adThis,
        "updated_at": DateTime.now().toUtc().toIso8601String(),
      };
}
