import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/supabase/supabase_providers.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/create_ad/presentation/providers/draft_ad_providers.dart";
import "../../features/feed/presentation/providers/feed_controller.dart";
import "../../features/moderation/domain/report_target_type.dart";
import "../../features/moderation/presentation/providers/moderation_providers.dart";
import "../../features/moderation/presentation/widgets/report_sheet.dart";
import "../../features/profile/presentation/providers/profile_providers.dart";
import "action_rail_icon.dart";

/// Report / Block entry point (CLAUDE.md section 30/31) shown on each Ad.
/// Hides "Block" entirely for your own Ad — blocking yourself isn't a
/// meaningful action to offer.
class MoreMenuButton extends ConsumerWidget {
  const MoreMenuButton({required this.adId, required this.adOwnerUserId, super.key});

  final String adId;
  final String adOwnerUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? currentUserId = ref.watch(currentUserIdProvider);
    final bool isOwnAd = currentUserId == adOwnerUserId;

    return Semantics(
      button: true,
      label: "More",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => unawaited(_openMenu(context, ref, isOwnAd)),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: ActionRailIcon(icon: Icons.more_horiz),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref, bool isOwnAd) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isOwnAd)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text("Delete"),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_confirmDelete(context, ref));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text("Report"),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (BuildContext context) =>
                          ReportSheet(targetType: ReportTargetType.ad, targetId: adId),
                    ),
                  );
                },
              ),
              if (!isOwnAd)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text("Block"),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    try {
                      await ref.read(moderationRepositoryProvider).blockUser(adOwnerUserId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Blocked.")),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Couldn't block: $e")),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Delete this Ad?"),
        content: const Text("This can't be undone. It will be removed from feeds immediately."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(draftAdRepositoryProvider).deleteAd(adId);
      ref.invalidate(feedControllerProvider);
      ref.invalidate(adsByUserProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't delete: $e")),
        );
      }
    }
  }
}
