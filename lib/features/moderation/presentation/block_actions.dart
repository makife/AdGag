import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/localization/generated/app_localizations.dart";
import "../../feed/presentation/providers/feed_controller.dart";
import "providers/moderation_providers.dart";

/// Block with a confirmation, then make it visible right away: the user's
/// Ads leave the feed immediately and a snackbar offers Undo. (Before, the
/// block went through but nothing on screen changed, so the button seemed
/// to do nothing and every tap just said "Blocked." again.)
///
/// Returns true if the user was blocked.
Future<bool> blockUserFlow(
  BuildContext context, {
  required String userId,
  required String? username,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String name = username ?? l10n.unknownUser;
  // The card/menu that started this may be gone by the time Undo is
  // tapped, so everything after the dialog goes through the app-wide
  // container and messenger, not this context.
  final ProviderContainer container = ProviderScope.containerOf(context, listen: false);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(l10n.blockConfirmTitle(name)),
      content: Text(l10n.blockConfirmNote),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.genericCancel)),
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.blockUser)),
      ],
    ),
  );
  if (confirmed != true) {
    return false;
  }

  try {
    await container.read(moderationRepositoryProvider).blockUser(userId);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.blockFailed("$e"))));
    return false;
  }
  container.read(feedControllerProvider.notifier).hideCreator(userId);
  _invalidate(container, userId);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.blockDoneNamed(name)),
        action: SnackBarAction(
          label: l10n.blockUndo,
          onPressed: () => unawaited(_unblock(container, messenger, l10n, userId)),
        ),
      ),
    );
  return true;
}

/// Unblock (profile's "Unblock" button). No confirmation: it's the
/// harmless direction, and the button itself says what it does.
Future<void> unblockUserFlow(BuildContext context, {required String userId}) {
  return _unblock(
    ProviderScope.containerOf(context, listen: false),
    ScaffoldMessenger.of(context),
    AppLocalizations.of(context),
    userId,
  );
}

Future<void> _unblock(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String userId,
) async {
  try {
    await container.read(moderationRepositoryProvider).unblockUser(userId);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("$e")));
    return;
  }
  _invalidate(container, userId);
  // Their Ads come back with the next page load; refresh quietly.
  unawaited(container.read(feedControllerProvider.notifier).refresh().catchError((Object _) {}));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.unblockDone)));
}

void _invalidate(ProviderContainer container, String userId) {
  container
    ..invalidate(isBlockedProvider(userId))
    ..invalidate(blockedUsersProvider);
}
