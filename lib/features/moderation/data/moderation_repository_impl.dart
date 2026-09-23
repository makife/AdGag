import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
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
}
