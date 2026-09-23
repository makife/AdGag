import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/feed_repository_impl.dart";
import "../../domain/feed_repository.dart";

final Provider<FeedRepository> feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepositoryImpl(ref.watch(supabaseClientProvider));
});
