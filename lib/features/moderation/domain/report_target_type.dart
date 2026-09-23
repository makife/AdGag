/// Mirrors the `report_target_type` Postgres enum
/// (supabase/migrations/0012_reports_and_blocks.sql).
enum ReportTargetType {
  ad,
  user,
  comment;

  String get dbValue => name;
}
