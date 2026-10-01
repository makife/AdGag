import "app_notification.dart";
import "notification_preferences.dart";

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> fetchRecent({int limit = 50});

  Future<void> markRead(String notificationId);

  /// The signed-in user's push preferences (defaults when never saved).
  Future<NotificationPreferences> fetchPreferences();

  Future<void> savePreferences(NotificationPreferences preferences);
}
