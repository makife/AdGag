import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../auth/domain/app_user.dart";
import "../../../auth/presentation/providers/auth_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../../../../shared/widgets/count_label.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";
import "../widgets/profile_stat.dart";

/// PROFILE (CLAUDE.md section 13): own Ads grid, SOLD/views stats, Edit
/// profile, and the menu icon into Settings (where sign-out lives). The
/// distinction from [PublicProfileScreen] (that one has FOLLOW instead)
/// is intentional, not duplicated logic — different actions apply to your
/// own profile than to someone else's.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppUser?> appUserAsync = ref.watch(currentAppUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).navProfile),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: AppLocalizations.of(context).profileMenuTooltip,
            onPressed: () => unawaited(context.pushTo(RoutePaths.settings)),
          ),
        ],
      ),
      body: appUserAsync.when(
        data: (AppUser? user) {
          if (user == null) {
            return Center(child: Text(AppLocalizations.of(context).profileNotSignedIn));
          }
          return _ProfileBody(user: user);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PublicProfile? profile = ref.watch(profileByUsernameProvider(user.username)).valueOrNull;
    final AsyncValue<List<Ad>> adsAsync = ref.watch(adsByUserProvider(user.id));

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          profile?.avatarUrl != null ? CachedNetworkImageProvider(profile!.avatarUrl!) : null,
                      child: profile?.avatarUrl == null ? const Icon(Icons.person, size: 32) : null,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: _StatsRow(
                        username: user.username,
                        ads: adsAsync.valueOrNull,
                        profile: profile,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(user.displayName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text("@${user.username}", style: Theme.of(context).textTheme.bodyMedium),
                if (adsAsync.valueOrNull case final List<Ad> ads when ads.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _EngagementLine(ads: ads),
                ],
                if (profile?.bio != null && profile!.bio!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio!),
                ],
                const SizedBox(height: AppSpacing.lg),
                // Sign out lives at the bottom of Settings (menu icon, top
                // right) — like Instagram, not on the profile itself.
                FilledButton.tonal(
                  onPressed: () => unawaited(context.pushTo(RoutePaths.editProfile)),
                  child: Text(AppLocalizations.of(context).profileEditProfile),
                ),
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
          error: (Object error, StackTrace stackTrace) => SliverToBoxAdapter(child: Center(child: Text("$error"))),
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
        // The shell's Scaffold uses extendBody, so the nav bar sits over
        // the end of this list; unlike ListView, CustomScrollView doesn't
        // add that inset by itself — without it the last row stayed
        // half-hidden under the bar.
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + AppSpacing.md)),
      ],
    );
  }
}

/// Ads / Followers / Following (CLAUDE.md section 13) next to the avatar;
/// the follow counts open their lists. Follow counts are the profile's
/// server-maintained counters. The Ads count is the fetched page's length —
/// exact up to [ProfileRepository.fetchAdsByUser]'s limit (30).
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.username, required this.ads, required this.profile});

  final String username;
  final List<Ad>? ads;
  final PublicProfile? profile;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        Flexible(child: ProfileStat(label: l10n.statAds, value: ads?.length ?? 0)),
        Flexible(
          child: ProfileStat(
            label: l10n.statFollowers,
            value: profile?.followersCount ?? 0,
            onTap: () => unawaited(context.pushTo(RoutePaths.userFollowsOf(username))),
          ),
        ),
        Flexible(
          child: ProfileStat(
            label: l10n.statFollowing,
            value: profile?.followingCount ?? 0,
            onTap: () => unawaited(context.pushTo(RoutePaths.userFollowsOf(username, following: true))),
          ),
        ),
      ],
    );
  }
}

/// "12.8K SOLD · 40K views", summed from the same page of Ads the grid
/// fetched — not an account-wide total past 30 Ads (a maintained counter on
/// `profiles` is the fix at scale, CLAUDE.md section 58).
class _EngagementLine extends StatelessWidget {
  const _EngagementLine({required this.ads});

  final List<Ad> ads;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int soldTotal = ads.fold(0, (int sum, Ad ad) => sum + ad.soldCount);
    final int viewTotal = ads.fold(0, (int sum, Ad ad) => sum + ad.viewCount);
    return Text(
      "${CountLabel.format(soldTotal)} ${l10n.actionSold} · ${CountLabel.format(viewTotal)} ${l10n.statViews}",
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
