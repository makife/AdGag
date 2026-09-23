import "../../feed/domain/ad.dart";
import "public_profile.dart";

abstract interface class ProfileRepository {
  Future<PublicProfile?> getByUsername(String username);

  /// This user's published Ads, newest first. No cursor pagination yet —
  /// same accepted-simplification note as SubjectRepository.fetchAdsForSubject.
  Future<List<Ad>> fetchAdsByUser(String userId, {int limit = 30});
}
