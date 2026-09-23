import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../auth/domain/app_user.dart";
import "../../../auth/presentation/providers/auth_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../subjects/presentation/screens/subject_ads_viewer_screen.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";

/// PROFILE (CLAUDE.md section 13): own Ads grid, SOLD/views stats, account
/// settings, sign-out. The signed-out-vs-signed-in distinction from
/// [PublicProfileScreen] (that one has FOLLOW instead of Settings/sign-out)
/// is intentional, not duplicated logic — different actions apply to your
/// own profile than to someone else's.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppUser?> appUserAsync = ref.watch(currentAppUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Settings",
            onPressed: () => unawaited(context.pushTo(RoutePaths.editProfile)),
          ),
        ],
      ),
      body: appUserAsync.when(
        data: (AppUser? user) {
          if (user == null) {
            return const Center(child: Text("Not signed in."));
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
                      child: adsAsync.maybeWhen(
                        data: (List<Ad> ads) => _StatsRow(ads: ads),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(user.displayName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text("@${user.username}", style: Theme.of(context).textTheme.bodyMedium),
                if (profile?.bio != null && profile!.bio!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio!),
                ],
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: () => unawaited(ref.read(authControllerProvider.notifier).signOut()),
                  child: const Text("Sign out"),
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

/// Ads / SOLD / Views (CLAUDE.md section 13). Summed from the same page of
/// Ads the grid below already fetched — correct for the common case, but
/// not a true account-wide total once a creator has more Ads than
/// [ProfileRepository.fetchAdsByUser]'s limit (30). Good enough for MVP;
/// an accurate total at scale needs a maintained counter on `profiles`
/// (CLAUDE.md section 58), not an extra query here.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.ads});

  final List<Ad> ads;

  @override
  Widget build(BuildContext context) {
    final int soldTotal = ads.fold(0, (int sum, Ad ad) => sum + ad.soldCount);
    final int viewTotal = ads.fold(0, (int sum, Ad ad) => sum + ad.viewCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        _Stat(label: "Ads", value: ads.length),
        _Stat(label: "SOLD", value: soldTotal),
        _Stat(label: "Views", value: viewTotal),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text("$value", style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
