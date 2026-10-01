import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/notifications_repository_impl.dart";
import "../../domain/app_notification.dart";
import "../../domain/notification_preferences.dart";
import "../../domain/notifications_repository.dart";

final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return NotificationsRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProvider<List<AppNotification>> recentNotificationsProvider =
    FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).fetchRecent();
});

final AutoDisposeFutureProvider<NotificationPreferences> notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) {
  return ref.watch(notificationsRepositoryProvider).fetchPreferences();
});
