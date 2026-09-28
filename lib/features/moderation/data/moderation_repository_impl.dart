import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../profile/domain/public_profile.dart";
import "../domain/moderation_repository.dart";
import "../domain/report_reason.dart";
import "../domain/report_target_type.dart";

final class ModerationRepositoryImpl implements ModerationRepository {
  ModerationRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    try {
      await _client.rpc<dynamic>(
        "report_content",
        params: <String, dynamic>{
          "p_target_type": targetType.dbValue,
          "p_target_id": targetId,
          "p_reason": reason.dbValue,
          "p_details": details,
        },
      );
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<void> blockUser(String userId) async {
    try {
      await _client.rpc<dynamic>("block_user", params: <String, dynamic>{"p_target_user_id": userId});
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<void> unblockUser(String userId) async {
    try {
      await _client.rpc<dynamic>("unblock_user", params: <String, dynamic>{"p_target_user_id": userId});
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<bool> isBlocked(String userId) async {
    try {
      // RLS blocks_select_own: only the caller's own rows come back.
      final Map<String, dynamic>? row =
          await _client.from("blocks").select("blocked_id").eq("blocked_id", userId).maybeSingle();
      return row != null;
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<List<PublicProfile>> fetchBlockedUsers() async {
    try {
      // `blocks` has two FKs to `profiles` — embed through the blocked side
      // explicitly (an unqualified `profiles(...)` would be ambiguous).
      final List<Map<String, dynamic>> rows = await _client
          .from("blocks")
          .select("created_at, profiles!blocks_blocked_id_fkey(id, username, display_name, bio, avatar_url)")
          .order("created_at", ascending: false);
      return <PublicProfile>[
        for (final Map<String, dynamic> row in rows)
          if (row["profiles"] is Map<String, dynamic>) PublicProfile.fromRow(row["profiles"] as Map<String, dynamic>),
      ];
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }
}
