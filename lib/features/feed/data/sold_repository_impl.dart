import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../domain/sold_repository.dart";

final class SoldRepositoryImpl implements SoldRepository {
  SoldRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<bool> toggle(String adId) async {
    try {
      final bool nowSold = await _client.rpc<bool>(
        "toggle_sold_reaction",
        params: <String, dynamic>{"p_ad_id": adId},
      );
      return nowSold;
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<bool> isSoldByCurrentUser(String adId) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return false;
    }
    final List<dynamic> rows = await _client
        .from("sold_reactions")
        .select("ad_id")
        .eq("ad_id", adId)
        .eq("user_id", userId)
        .limit(1);
    return rows.isNotEmpty;
  }
}
