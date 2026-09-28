import "../../profile/domain/public_profile.dart";
import "report_reason.dart";
import "report_target_type.dart";

/// Report/block (CLAUDE.md section 30/31). Every write goes through a
/// SECURITY DEFINER RPC — see supabase/migrations/0012_reports_and_blocks.sql
/// — which also rate-limits report abuse (section 29).
abstract interface class ModerationRepository {
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  });

  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);

  /// Whether the signed-in user has blocked [userId].
  Future<bool> isBlocked(String userId);

  /// The signed-in user's own block list, newest first (Settings >
  /// Blocked accounts). RLS `blocks_select_own` only ever returns the
  /// caller's own rows — never who has blocked them.
  Future<List<PublicProfile>> fetchBlockedUsers();
}
