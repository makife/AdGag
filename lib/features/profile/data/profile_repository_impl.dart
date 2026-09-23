import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../feed/domain/ad.dart";
import "../domain/profile_repository.dart";
import "../domain/public_profile.dart";

final class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<PublicProfile?> getByUsername(String username) async {
    final Map<String, dynamic>? row =
        await _client.from("profiles").select().eq("username", username).maybeSingle();
    return row == null ? null : PublicProfile.fromRow(row);
  }

  @override
  Future<List<Ad>> fetchAdsByUser(String userId, {int limit = 30}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("ads")
        .select("*, ad_subjects(display_name), profiles!ads_user_id_fkey(username)")
        .eq("user_id", userId)
        .eq("status", "ready")
        .order("published_at", ascending: false)
        .limit(limit);
    return rows.map(Ad.fromRow).toList(growable: false);
  }
}
