import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/follow_repository_impl.dart";
import "../../domain/follow_repository.dart";

final Provider<FollowRepository> followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProviderFamily<bool, String> isFollowingProvider = FutureProvider.family<bool, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).isFollowing(userId),
);

final FutureProviderFamily<int, String> followerCountProvider = FutureProvider.family<int, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).followerCount(userId),
);

final FutureProviderFamily<int, String> followingCountProvider = FutureProvider.family<int, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).followingCount(userId),
);

/// Optimistic follow/unfollow toggle, keyed by the target user's id.
/// [isFollowingProvider] above is a one-shot read (fine for a profile
/// page); this is for a tappable FOLLOW button that needs to flip
/// instantly and revert on failure (CLAUDE.md section 41).
final class FollowController extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String userId) {
    return ref.read(followRepositoryProvider).isFollowing(userId);
  }

  Future<void> toggle() async {
    final bool previous = state.valueOrNull ?? false;
    state = AsyncData<bool>(!previous);
    try {
      if (previous) {
        await ref.read(followRepositoryProvider).unfollow(arg);
      } else {
        await ref.read(followRepositoryProvider).follow(arg);
      }
    } catch (_) {
      state = AsyncData<bool>(previous);
      rethrow;
    }
  }
}

final AsyncNotifierProviderFamily<FollowController, bool, String> followControllerProvider =
    AsyncNotifierProvider.family<FollowController, bool, String>(FollowController.new);
