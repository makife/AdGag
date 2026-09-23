/// Mirrors the `report_reason` Postgres enum (section 30).
enum ReportReason {
  nudity,
  violence,
  hateHarassment,
  bullying,
  dangerousActivity,
  spamScam,
  copyright,
  impersonation,
  other;

  /// The exact enum label the database expects (snake_case).
  String get dbValue => switch (this) {
        ReportReason.nudity => "nudity",
        ReportReason.violence => "violence",
        ReportReason.hateHarassment => "hate_harassment",
        ReportReason.bullying => "bullying",
        ReportReason.dangerousActivity => "dangerous_activity",
        ReportReason.spamScam => "spam_scam",
        ReportReason.copyright => "copyright",
        ReportReason.impersonation => "impersonation",
        ReportReason.other => "other",
      };

  /// English label. The matching `reportReason*` keys already exist in
  /// l10n/app_en.arb and app_tr.arb — swap this for an `AppLocalizations`
  /// lookup when the report sheet is wired through localization.
  String get label => switch (this) {
        ReportReason.nudity => "Nudity or sexual content",
        ReportReason.violence => "Violence",
        ReportReason.hateHarassment => "Hate or harassment",
        ReportReason.bullying => "Bullying",
        ReportReason.dangerousActivity => "Dangerous activity",
        ReportReason.spamScam => "Spam or scam",
        ReportReason.copyright => "Copyright",
        ReportReason.impersonation => "Impersonation",
        ReportReason.other => "Other",
      };
}
