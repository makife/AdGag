import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/subject_repository_impl.dart";
import "../../domain/subject_repository.dart";

final Provider<SubjectRepository> subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return SubjectRepositoryImpl(ref.watch(supabaseClientProvider));
});
