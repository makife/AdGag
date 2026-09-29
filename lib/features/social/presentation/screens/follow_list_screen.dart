import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/supabase/supabase_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/count_label.dart";
import "../../../../shared/widgets/mini_avatar.dart";
import "../../../profile/domain/public_profile.dart";
import "../../../profile/presentation/providers/profile_providers.dart";
import "../providers/social_providers.dart";

/// Followers / Following of one user (CLAUDE.md section 15), reached by
/// tapping the counts on a profile. Two tabs, like Instagram.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({required this.username, this.showFollowing = false, super.key});

  final String username;
  final bool showFollowing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PublicProfile? profile = ref.watch(profileByUsernameProvider(username)).valueOrNull;

    return DefaultTabController(
      length: 2,
      initialIndex: showFollowing ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text("@$username"),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: "${CountLabel.format(profile?.followersCount ?? 0)} ${l10n.statFollowers}"),
              Tab(text: "${CountLabel.format(profile?.followingCount ?? 0)} ${l10n.statFollowing}"),
            ],
          ),
        ),
        body: profile == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: <Widget>[
                  _PeopleList(provider: followersProvider(profile.id), emptyText: l10n.followersEmpty),
                  _PeopleList(provider: followingProvider(profile.id), emptyText: l10n.followingEmpty),
                ],
              ),
      ),
    );
  }
}

class _PeopleList extends ConsumerWidget {
  const _PeopleList({required this.provider, required this.emptyText});

  final AutoDisposeFutureProvider<List<PublicProfile>> provider;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? currentUserId = ref.watch(currentUserIdProvider);
    return ref.watch(provider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(provider),
              child: Text(AppLocalizations.of(context).genericRetry),
            ),
          ),
          data: (List<PublicProfile> people) {
            if (people.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(emptyText, textAlign: TextAlign.center),
                ),
              );
            }
            return ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.md),
              itemCount: people.length,
              itemBuilder: (BuildContext context, int index) {
                final PublicProfile person = people[index];
                return ListTile(
                  leading: MiniAvatar(avatarUrl: person.avatarUrl, username: person.username, size: 44),
                  title: Text(person.displayName ?? person.username),
                  subtitle: Text("@${person.username}"),
                  // Yourself: the PROFILE tab (a shell branch), not a pushed page.
                  onTap: () => person.id == currentUserId
                      ? context.goTo(RoutePaths.profile)
                      : unawaited(context.pushTo(RoutePaths.userProfileOf(person.username))),
                );
              },
            );
          },
        );
  }
}
