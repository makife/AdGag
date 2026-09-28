import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/mini_avatar.dart";
import "../../../moderation/presentation/providers/moderation_providers.dart";
import "../../../profile/domain/public_profile.dart";

/// Settings > Blocked: who the user has blocked, with Unblock
/// (CLAUDE.md section 30). Blocking itself happens from the "…" menu on
/// an Ad or a profile.
class BlockedAccountsScreen extends ConsumerWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<PublicProfile>> blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsBlocked)),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.blockedLoadError),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: () => ref.invalidate(blockedUsersProvider), child: Text(l10n.genericRetry)),
            ],
          ),
        ),
        data: (List<PublicProfile> blocked) {
          if (blocked.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.block, size: 48),
                    const SizedBox(height: AppSpacing.md),
                    Text(l10n.blockedEmpty, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(l10n.blockedEmptyNote, textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: blocked.length,
            itemBuilder: (BuildContext context, int index) {
              final PublicProfile user = blocked[index];
              return ListTile(
                leading: MiniAvatar(avatarUrl: user.avatarUrl, username: user.username, size: 44),
                title: Text(user.username),
                subtitle: user.displayName == null ? null : Text(user.displayName!),
                onTap: () => unawaited(context.pushTo(RoutePaths.userProfileOf(user.username))),
                trailing: OutlinedButton(
                  onPressed: () => unawaited(_unblock(context, ref, user)),
                  child: Text(l10n.blockedUnblock),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref, PublicProfile user) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.blockedUnblockConfirmTitle(user.username)),
        content: Text(l10n.blockedUnblockConfirmNote),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.genericCancel)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.blockedUnblock)),
        ],
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }
    try {
      await ref.read(moderationRepositoryProvider).unblockUser(user.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
      }
    }
    ref.invalidate(blockedUsersProvider);
  }
}
