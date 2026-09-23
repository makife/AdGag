import "dart:io";

import "../../feed/domain/ad.dart";
import "public_profile.dart";

abstract interface class ProfileRepository {
  Future<PublicProfile?> getByUsername(String username);

  /// This user's published Ads, newest first. No cursor pagination yet —
  /// same accepted-simplification note as SubjectRepository.fetchAdsForSubject.
  Future<List<Ad>> fetchAdsByUser(String userId, {int limit = 30});

  /// Updates the signed-in user's own display name/bio (CLAUDE.md section
  /// 13/24). Column-level grants on `profiles` (0002_profiles_and_auth_trigger.sql)
  /// already restrict this to `display_name`/`avatar_url`/`bio` server-side —
  /// this call can never touch `username`, `id`, or `account_status` even if
  /// it tried to. A null field leaves that column unchanged.
  Future<void> updateProfile({String? displayName, String? bio, String? avatarUrl});

  /// Uploads [file] to the `avatars` Storage bucket
  /// (0018_avatar_storage.sql) at `{userId}/avatar.<ext>` (upsert — replaces
  /// any existing avatar), updates `profiles.avatar_url` to the new public
  /// URL, and returns that URL.
  Future<String> uploadAvatar(File file);
}
