import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/supabase/supabase_providers.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/moderation/domain/report_target_type.dart";
import "../../features/moderation/presentation/providers/moderation_providers.dart";
import "../../features/moderation/presentation/widgets/report_sheet.dart";

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
          child: Icon(Icons.more_horiz, color: Colors.white, size: 26),
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
}
