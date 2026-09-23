import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/draft_ad_repository_impl.dart";
import "../../domain/draft_ad_repository.dart";

final Provider<DraftAdRepository> draftAdRepositoryProvider = Provider<DraftAdRepository>((ref) {
  return DraftAdRepositoryImpl(ref.watch(supabaseClientProvider));
});
