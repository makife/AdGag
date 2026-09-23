import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/router/route_paths.dart";
import "../../../core/widgets/coming_soon_view.dart";
import "../domain/app_notification.dart";
import "providers/notifications_providers.dart";

/// ACTIVITY tab (CLAUDE.md section 32): new followers, REVIEWS, AD THIS
/// attribution. Daily Ad results / moderation notices are added once
/// Phase F/G's admin tooling actually produces those event types — the
/// `notification_type` enum already has room for them.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(recentNotificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Activity")),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
        data: (List<AppNotification> notifications) {
          if (notifications.isEmpty) {
            return const ComingSoonView(
              title: "Nothing yet",
              phaseNote: "Follows, REVIEWS and AD THIS on your Ads will show up here.",
            );
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (BuildContext context, int index) {
              final AppNotification notification = notifications[index];
              return ListTile(
                tileColor: notification.isUnread
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
                    : null,
                leading: Icon(_iconFor(notification.type)),
                title: Text(_textFor(notification)),
                subtitle: Text(_relativeTime(notification.createdAt)),
                onTap: () {
                  if (notification.isUnread) {
                    unawaited(
                      ref.read(notificationsRepositoryProvider).markRead(notification.id),
                    );
                  }
                  final String? adId = notification.adId;
                  if (adId != null) {
                    context.goTo(RoutePaths.adDetailOf(adId));
                  } else if (notification.actorUsername != null) {
                    context.goTo(RoutePaths.userProfileOf(notification.actorUsername!));
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(NotificationType type) => switch (type) {
        NotificationType.newFollower => Icons.person_add_alt,
        NotificationType.newReview => Icons.chat_bubble_outline,
        NotificationType.adThis => Icons.bolt,
      };

  String _textFor(AppNotification notification) {
    final String actor = notification.actorUsername != null ? "@${notification.actorUsername}" : "Someone";
    return switch (notification.type) {
      NotificationType.newFollower => "$actor started following you.",
      NotificationType.newReview => "$actor reviewed your Ad.",
      NotificationType.adThis => "$actor pressed AD THIS on your Ad.",
    };
  }

  String _relativeTime(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }
}
