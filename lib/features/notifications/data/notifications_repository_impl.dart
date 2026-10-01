import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../domain/app_notification.dart";
import "../domain/notification_preferences.dart";
import "../domain/notifications_repository.dart";

final class NotificationsRepositoryImpl implements NotificationsRepository {
  NotificationsRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<List<AppNotification>> fetchRecent({int limit = 50}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("notifications")
        .select("*, profiles!notifications_actor_id_fkey(username)")
        .order("created_at", ascending: false)
        .limit(limit);
    return rows.map(AppNotification.tryFromRow).whereType<AppNotification>().toList(growable: false);
  }

  @override
  Future<void> markRead(String notificationId) async {
    await _client.rpc<dynamic>(
      "mark_notification_read",
      params: <String, dynamic>{"p_notification_id": notificationId},
    );
  }

  @override
  Future<NotificationPreferences> fetchPreferences() async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return const NotificationPreferences();
    }
    final Map<String, dynamic>? row =
        await _client.from("notification_preferences").select().eq("user_id", uid).maybeSingle();
    return NotificationPreferences.fromRow(row);
  }

  @override
  Future<void> savePreferences(NotificationPreferences preferences) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return;
    }
    await _client.from("notification_preferences").upsert(preferences.toRow(uid));
  }
}
