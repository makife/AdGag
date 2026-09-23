/// Mirrors the `ad_status` Postgres enum
/// (supabase/migrations/0005_ads.sql). CLAUDE.md section 19.
enum AdStatus {
  draft,
  uploading,
  processing,
  ready,
  failed,
  blocked,
  deleted;

  static AdStatus fromDb(String value) => AdStatus.values.firstWhere(
        (AdStatus s) => s.name == value,
        orElse: () => throw ArgumentError("Unknown ad_status: $value"),
      );
}
