import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../data/profile_repository_impl.dart";
import "../../domain/profile_repository.dart";
import "../../domain/public_profile.dart";

final Provider<ProfileRepository> profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProviderFamily<PublicProfile?, String> profileByUsernameProvider =
    FutureProvider.family<PublicProfile?, String>(
  (ref, username) => ref.watch(profileRepositoryProvider).getByUsername(username),
);

final FutureProviderFamily<List<Ad>, String> adsByUserProvider = FutureProvider.family<List<Ad>, String>(
  (ref, userId) => ref.watch(profileRepositoryProvider).fetchAdsByUser(userId),
);
