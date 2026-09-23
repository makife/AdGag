import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../../feed/domain/ad.dart";
import "../../../social/presentation/providers/social_providers.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";

/// Another user's PROFILE (CLAUDE.md section 13) — reached from search or
/// a creator's @username tap. The signed-in user's own profile still uses
/// [ProfileScreen] (has sign-out; this one has FOLLOW instead).
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileByUsernameProvider(username));

    return Scaffold(
      appBar: AppBar(),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
        data: (PublicProfile? profile) {
          if (profile == null) {
            return const Center(child: Text("This account doesn't exist."));
          }
          return _ProfileBody(profile: profile);
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final bool isOwnProfile = currentUserId == profile.id;
    final adsAsync = ref.watch(adsByUserProvider(profile.id));

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  profile.displayName ?? profile.username,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text("@${profile.username}", style: Theme.of(context).textTheme.bodyMedium),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!isOwnProfile && currentUserId != null) _FollowButton(userId: profile.id),
              ],
            ),
          ),
        ),
        adsAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace stackTrace) =>
              SliverToBoxAdapter(child: Center(child: Text("$error"))),
          data: (List<Ad> ads) {
            if (ads.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text("Nothing for sale yet."),
                ),
              );
            }
            return SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 9 / 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  final Ad ad = ads[index];
                  return GestureDetector(
                    onTap: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SubjectAdsViewerScreen(ads: ads, initialIndex: index),
                        ),
                      ),
                    ),
                    child: ad.thumbnailUrl != null
                        ? CachedNetworkImage(imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover)
                        : Container(color: Colors.black12),
                  );
                },
                childCount: ads.length,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followingAsync = ref.watch(followControllerProvider(userId));
    final bool isFollowing = followingAsync.valueOrNull ?? false;

    return OutlinedButton(
      onPressed: () => unawaited(ref.read(followControllerProvider(userId).notifier).toggle()),
      child: Text(isFollowing ? "FOLLOWING" : "FOLLOW"),
    );
  }
}
