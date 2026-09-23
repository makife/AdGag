import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/comments_repository_impl.dart";
import "../../domain/comments_repository.dart";

final Provider<CommentsRepository> commentsRepositoryProvider = Provider<CommentsRepository>((ref) {
  return CommentsRepositoryImpl(ref.watch(supabaseClientProvider));
});
