import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/feed_repository_impl.dart";
import "../../domain/ad.dart";
import "../../domain/feed_repository.dart";

final Provider<FeedRepository> feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProviderFamily<Ad?, String> adByIdProvider = FutureProvider.family<Ad?, String>(
  (ref, adId) => ref.watch(feedRepositoryProvider).getById(adId),
);

/// Ads made with AD THIS from one Ad (the "N made their own" list).
final AutoDisposeFutureProviderFamily<List<Ad>, String> adThisChildrenProvider =
    FutureProvider.autoDispose.family<List<Ad>, String>(
  (ref, adId) => ref.watch(feedRepositoryProvider).fetchAdThisChildren(adId),
);
