import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../domain/daily_ad_repository.dart";
import "../domain/daily_challenge.dart";

final class DailyAdRepositoryImpl implements DailyAdRepository {
  DailyAdRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<DailyChallenge?> getCurrent() async {
    final dynamic result = await _client.rpc<dynamic>("get_current_daily_challenge");
    // A scalar-returning Postgres function yields either the row as a JSON
    // object, or null (no challenge currently active) — never an error.
    if (result == null) {
      return null;
    }
    final Map<String, dynamic> row = Map<String, dynamic>.from(result as Map);
    if (row["id"] == null) {
      return null;
    }
    return DailyChallenge.fromRow(row);
  }
}
