import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/sold_repository_impl.dart";
import "../../domain/sold_repository.dart";

final Provider<SoldRepository> soldRepositoryProvider = Provider<SoldRepository>((ref) {
  return SoldRepositoryImpl(ref.watch(supabaseClientProvider));
});

/// Per-Ad "did the current user SOLD this" state, keyed by Ad id.
/// Optimistic toggle: flips immediately, reverts if the server call fails,
/// so tapping SOLD feels instant (CLAUDE.md section 41).
final class SoldController extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String adId) {
    return ref.read(soldRepositoryProvider).isSoldByCurrentUser(adId);
  }

  Future<void> toggle() async {
    final bool previous = state.valueOrNull ?? false;
    state = AsyncData<bool>(!previous);
    try {
      final bool result = await ref.read(soldRepositoryProvider).toggle(arg);
      state = AsyncData<bool>(result);
    } catch (_) {
      state = AsyncData<bool>(previous);
      rethrow;
    }
  }
}

final AsyncNotifierProviderFamily<SoldController, bool, String> soldControllerProvider =
    AsyncNotifierProvider.family<SoldController, bool, String>(SoldController.new);

/// The SOLD state that the Ad's fetched `sold_count` already reflects — the
/// first value [soldControllerProvider] resolved to for that Ad. Kept HERE,
/// not in the button's State: the feed disposes a card once it's scrolled
/// away, and a new button would take the already-toggled value as its
/// baseline, so the count dropped back after swiping away and back (user
/// report: "SOLD doesn't increase the counter"). Cleared whenever the feed
/// is refetched (the new counts include the viewer's own reactions).
final StateProviderFamily<bool?, String> soldBaselineProvider = StateProvider.family<bool?, String>((ref, adId) => null);

/// Shares (GAG!) this session, per Ad, added to the fetched `share_count`
/// until the next feed refetch — the counter moves right away.
final StateProviderFamily<int, String> shareCountDeltaProvider = StateProvider.family<int, String>((ref, adId) => 0);
