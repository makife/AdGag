import "app_notification.dart";

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> fetchRecent({int limit = 50});

  Future<void> markRead(String notificationId);
}
