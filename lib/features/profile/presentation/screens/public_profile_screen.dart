import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../../core/localization/generated/app_localizations.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/supabase/supabase_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/mini_avatar.dart";
import "../../../feed/domain/ad.dart";
import "../../../moderation/domain/report_target_type.dart";
import "../../../moderation/presentation/block_actions.dart";
import "../../../moderation/presentation/providers/moderation_providers.dart";
import "../../../moderation/presentation/widgets/report_sheet.dart";
import "../../../social/presentation/providers/social_providers.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";
import "../widgets/profile_stat.dart";

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
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text("$error")),
        data: (PublicProfile? profile) {
          if (profile == null) {
            return Center(
                child: Text(AppLocalizations.of(context).profileNotFound),);
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
    final bool blocked = !isOwnProfile &&
        currentUserId != null &&
        (ref.watch(isBlockedProvider(profile.id)).valueOrNull ?? false);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    MiniAvatar(avatarUrl: profile.avatarUrl, username: profile.username, size: 72),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: <Widget>[
                          Flexible(
                            child: ProfileStat(
                              label: AppLocalizations.of(context).statAds,
                              value: blocked ? 0 : (adsAsync.valueOrNull?.length ?? 0),
                            ),
                          ),
                          Flexible(
                            child: ProfileStat(
                              label: AppLocalizations.of(context).statFollowers,
                              value: profile.followersCount,
                              onTap: () => unawaited(context.pushTo(RoutePaths.userFollowsOf(profile.username))),
                            ),
                          ),
                          Flexible(
                            child: ProfileStat(
                              label: AppLocalizations.of(context).statFollowing,
                              value: profile.followingCount,
                              onTap: () => unawaited(
                                context.pushTo(RoutePaths.userFollowsOf(profile.username, following: true)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  profile.displayName ?? profile.username,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text("@${profile.username}",
                    style: Theme.of(context).textTheme.bodyMedium,),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!isOwnProfile && currentUserId != null)
                  Row(
                    children: <Widget>[
                      // Blocking removes follows both ways; following again
                      // only makes sense after unblocking.
                      if (!blocked) ...<Widget>[
                        _FollowButton(userId: profile.id),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      OutlinedButton.icon(
                        icon: Icon(
                            blocked
                                ? Icons.lock_open_outlined
                                : Icons.block_outlined,
                            size: 18,),
                        label: Text(
                          blocked
                              ? AppLocalizations.of(context).blockedUnblock
                              : AppLocalizations.of(context).blockUser,
                        ),
                        onPressed: () => unawaited(
                          blocked
                              ? unblockUserFlow(context, userId: profile.id)
                              : blockUserFlow(context,
                                  userId: profile.id,
                                  username: profile.username,),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flag_outlined),
                        tooltip: AppLocalizations.of(context).reportAd,
                        onPressed: () => unawaited(
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (BuildContext context) => ReportSheet(
                                targetType: ReportTargetType.user,
                                targetId: profile.id,),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (blocked)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                AppLocalizations.of(context).profileBlockedNote,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          )
        else
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
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(AppLocalizations.of(context).emptyProfileAds),
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
                            builder: (_) => SubjectAdsViewerScreen(
                                ads: ads, initialIndex: index,),
                          ),
                        ),
                      ),
                      child: ad.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: ad.thumbnailUrl!, fit: BoxFit.cover,)
                          : Container(color: Colors.black12),
                    );
                  },
                  childCount: ads.length,
                ),
              );
            },
          ),
        SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + AppSpacing.md,),),
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
      onPressed: () => unawaited(
          ref.read(followControllerProvider(userId).notifier).toggle(),),
      child: Text(isFollowing
          ? AppLocalizations.of(context).actionFollowing
          : AppLocalizations.of(context).actionFollow,),
    );
  }
}
