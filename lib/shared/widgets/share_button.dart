import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:share_plus/share_plus.dart";

import "../../core/config/env_config.dart";
import "../../core/supabase/supabase_providers.dart";
import "../../core/theme/app_spacing.dart";
import "count_label.dart";

/// External SHARE (CLAUDE.md section 33). Opens the native share sheet
/// with a universal-link-shaped URL; the link only actually resolves once
/// the deep-link/App-Store-fallback landing page ships (Phase H) — the
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
    return Semantics(
      button: true,
      label: "Share",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => unawaited(_share(ref)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.reply, color: Colors.white, size: 26),
              const SizedBox(height: AppSpacing.xs),
              CountLabel(count: shareCount, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(WidgetRef ref) async {
    final String url = "https://${EnvConfig.appLinkHost}/ad/$adId";
    final String subjectLine = subjectDisplayName != null ? "${subjectDisplayName!.toUpperCase()}™ " : "";
    await SharePlus.instance.share(
      ShareParams(text: "${subjectLine}on AdGag: $url"),
    );

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
