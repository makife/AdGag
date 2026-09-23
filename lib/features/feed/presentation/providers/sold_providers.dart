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
