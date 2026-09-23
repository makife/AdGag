import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/moderation_repository_impl.dart";
import "../../domain/moderation_repository.dart";

final Provider<ModerationRepository> moderationRepositoryProvider = Provider<ModerationRepository>((ref) {
  return ModerationRepositoryImpl(ref.watch(supabaseClientProvider));
});
