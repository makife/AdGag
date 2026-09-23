import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../data/market_repository_impl.dart";
import "../../domain/market_repository.dart";

final Provider<MarketRepository> marketRepositoryProvider = Provider<MarketRepository>((ref) {
  return MarketRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProvider<List<AdSubject>> trendingSubjectsProvider = FutureProvider<List<AdSubject>>((ref) {
  return ref.watch(marketRepositoryProvider).fetchTrendingSubjects();
});

final FutureProvider<List<Ad>> freshAdsProvider = FutureProvider<List<Ad>>((ref) {
  return ref.watch(marketRepositoryProvider).fetchFreshAds();
});
