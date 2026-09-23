import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../data/subject_repository_impl.dart";
import "../../domain/ad_subject.dart";
import "../../domain/subject_ads_sort.dart";
import "../../domain/subject_repository.dart";

final Provider<SubjectRepository> subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return SubjectRepositoryImpl(ref.watch(supabaseClientProvider));
});

final FutureProviderFamily<AdSubject?, String> subjectByIdProvider =
    FutureProvider.family<AdSubject?, String>(
  (ref, subjectId) => ref.watch(subjectRepositoryProvider).getSubjectById(subjectId),
);

/// Keyed by (subjectId, sort) so each tab on the subject page caches
/// independently.
final FutureProviderFamily<List<Ad>, (String, SubjectAdsSort)> subjectAdsProvider =
    FutureProvider.family<List<Ad>, (String, SubjectAdsSort)>((ref, args) {
  final (String subjectId, SubjectAdsSort sort) = args;
  return ref.watch(subjectRepositoryProvider).fetchAdsForSubject(subjectId: subjectId, sort: sort);
});
