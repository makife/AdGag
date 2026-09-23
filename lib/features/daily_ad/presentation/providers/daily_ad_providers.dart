import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/daily_ad_repository_impl.dart";
import "../../domain/daily_ad_repository.dart";
import "../../domain/daily_challenge.dart";

final Provider<DailyAdRepository> dailyAdRepositoryProvider = Provider<DailyAdRepository>((ref) {
  return DailyAdRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProvider<DailyChallenge?> currentDailyChallengeProvider = FutureProvider<DailyChallenge?>(
  (ref) => ref.watch(dailyAdRepositoryProvider).getCurrent(),
);
