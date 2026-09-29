import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/localization/generated/app_localizations.dart";

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
      appBar: AppBar(title: Text(AppLocalizations.of(context).navActivity)),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
        data: (List<AppNotification> notifications) {
          if (notifications.isEmpty) {
            return ComingSoonView(
              title: AppLocalizations.of(context).activityEmptyTitle,
              phaseNote: AppLocalizations.of(context).activityEmptyBody,
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(recentNotificationsProvider.future),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: notifications.length,
              itemBuilder: (BuildContext context, int index) {
                final AppNotification notification = notifications[index];
                return ListTile(
                  tileColor: notification.isUnread ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : null,
                  leading: Icon(_iconFor(notification.type)),
                  title: Text(_textFor(context, notification)),
                  subtitle: Text(_relativeTime(context, notification.createdAt)),
                  onTap: () {
                    if (notification.isUnread) {
                      unawaited(
                        ref
                            .read(notificationsRepositoryProvider)
                            .markRead(notification.id)
                            .then((_) => ref.invalidate(recentNotificationsProvider)),
                      );
                    }
                    // PUSH, not go: go replaced the whole stack, so the device
                    // back button left the app (user report).
                    final String? adId = notification.adId;
                    if (adId != null) {
                      unawaited(context.pushTo(RoutePaths.adDetailOf(adId)));
                    } else if (notification.actorUsername != null) {
                      unawaited(context.pushTo(RoutePaths.userProfileOf(notification.actorUsername!)));
                    }
                  },
                );
              },
            ),
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

  String _textFor(BuildContext context, AppNotification notification) {
    final String actor = notification.actorUsername != null
        ? "@${notification.actorUsername}"
        : AppLocalizations.of(context).activitySomeone;
    return switch (notification.type) {
      NotificationType.newFollower => AppLocalizations.of(context).activityNewFollower(actor),
      NotificationType.newReview => AppLocalizations.of(context).activityNewReview(actor),
      NotificationType.adThis => AppLocalizations.of(context).activityAdThis(actor),
    };
  }

  String _relativeTime(BuildContext context, DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return AppLocalizations.of(context).timeJustNow;
    if (diff.inHours < 1) return AppLocalizations.of(context).timeMinutesAgo("${diff.inMinutes}");
    if (diff.inDays < 1) return AppLocalizations.of(context).timeHoursAgo("${diff.inHours}");
    return AppLocalizations.of(context).timeDaysAgo("${diff.inDays}");
  }
}
