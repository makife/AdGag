import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/follow_repository_impl.dart";
import "../../domain/follow_repository.dart";

final Provider<FollowRepository> followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProvider<bool> isFollowingProvider = FutureProvider.family<bool, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).isFollowing(userId),
);

final FutureProvider<int> followerCountProvider = FutureProvider.family<int, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).followerCount(userId),
);

final FutureProvider<int> followingCountProvider = FutureProvider.family<int, String>(
  (ref, userId) => ref.watch(followRepositoryProvider).followingCount(userId),
);
