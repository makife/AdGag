import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/router/route_paths.dart";
import "../../core/supabase/supabase_providers.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/social/presentation/providers/social_providers.dart";

/// Creator attribution + FOLLOW toggle (CLAUDE.md section 6/15/64). Hides
/// the FOLLOW button entirely when viewing your own Ad or when signed
/// out, rather than showing a button that would just error on tap.
class CreatorHeader extends ConsumerWidget {
  const CreatorHeader({required this.userId, required this.username, super.key});

  final String userId;
  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? currentUserId = ref.watch(currentUserIdProvider);
    final bool isOwnAd = currentUserId == userId;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onTap: username == null
              ? null
              : () => unawaited(context.pushTo(RoutePaths.userProfileOf(username!))),
          // Deliberately plainer than SubjectBadge (no chip background,
          // dimmer white, smaller) — the two used to be the same white
          // bold text stacked tightly, easy to mis-tap one for the other.
          child: Text(
            "@${username ?? 'unknown'}",
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        if (!isOwnAd && currentUserId != null) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          _FollowChip(userId: userId),
        ],
      ],
    );
  }
}

class _FollowChip extends ConsumerWidget {
  const _FollowChip({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> followingAsync = ref.watch(followControllerProvider(userId));
    final bool isFollowing = followingAsync.valueOrNull ?? false;

    return GestureDetector(
      onTap: () async {
        try {
          await ref.read(followControllerProvider(userId).notifier).toggle();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't update follow right now.")),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          isFollowing ? "FOLLOWING" : "FOLLOW",
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
