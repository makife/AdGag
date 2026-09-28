import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:share_plus/share_plus.dart";

import "../../core/analytics/ad_event_type.dart";
import "../../core/analytics/analytics_providers.dart";
import "../../core/config/env_config.dart";
import "../../core/supabase/supabase_providers.dart";
import "../../core/localization/generated/app_localizations.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/feed/presentation/providers/sold_providers.dart";
import "action_rail_icon.dart";
import "count_label.dart";

/// External share, branded "GAG!" — a fixed brand word, never translated
/// (like SOLD). Shows "GAG!" under the icon until the Ad has shares, then
/// the count (CLAUDE.md section 33). Opens the native share sheet
/// with a universal-link-shaped URL. The in-app side is wired
/// (AdDetailScreen at RoutePaths.adDetail resolves `/ad/:id`); what's
/// still missing is the platform association files (apple-app-site-
/// association / assetlinks.json) that make iOS/Android actually route a
/// tapped link into the app instead of a browser, and a web fallback page
/// for users without the app installed — see README.md > Deep Links. The
/// share action and share_count tracking work today regardless.
class ShareButton extends ConsumerWidget {
  const ShareButton({
    required this.adId,
    required this.subjectDisplayName,
    required this.shareCount,
    super.key,
  });

  final String adId;
  final String? subjectDisplayName;
  final int shareCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int count = shareCount + ref.watch(shareCountDeltaProvider(adId));
    return Semantics(
      button: true,
      label: "GAG!",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => unawaited(_share(context, ref)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ActionRailIcon(icon: Icons.reply),
              const SizedBox(height: AppSpacing.xs),
              if (count > 0)
                CountLabel(count: count, color: Colors.white)
              else
                const Text(
                  "GAG!",
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final String url = "https://${EnvConfig.appLinkHost}/ad/$adId";
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = subjectDisplayName != null
        ? l10n.shareMessage("${subjectDisplayName!.toUpperCase()}™", url)
        : l10n.shareMessageNoSubject(url);
    final ShareResult result = await SharePlus.instance.share(ShareParams(text: text));
    // Opening the share sheet and backing out isn't a share. ("unavailable" —
    // the platform can't tell — still counts, as before.)
    if (result.status == ShareResultStatus.dismissed) {
      return;
    }

    ref.read(analyticsServiceProvider).track(adId, AdEventType.shared);
    ref.read(shareCountDeltaProvider(adId).notifier).state++;

    try {
      await ref
          .read(supabaseClientProvider)
          .rpc<dynamic>("increment_share_count", params: <String, dynamic>{"p_ad_id": adId});
    } catch (_) {
      // Non-critical: the share already happened from the user's
      // perspective — a failed counter bump isn't worth surfacing.
    }
  }
}
