import "../../../core/localization/generated/app_localizations.dart";

/// Mirrors the `report_reason` Postgres enum (section 30). [childSafety] is
/// first on purpose: Google Play's Child Safety Standards require in-app
/// reporting of child safety concerns, and those reports get priority.
enum ReportReason {
  childSafety,
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
        ReportReason.childSafety => "child_safety",
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

  /// The reason as shown in the report sheet, in the app's language.
  String label(AppLocalizations l10n) => switch (this) {
        ReportReason.childSafety => l10n.reportReasonChildSafety,
        ReportReason.nudity => l10n.reportReasonNudity,
        ReportReason.violence => l10n.reportReasonViolence,
        ReportReason.hateHarassment => l10n.reportReasonHate,
        ReportReason.bullying => l10n.reportReasonBullying,
        ReportReason.dangerousActivity => l10n.reportReasonDangerous,
        ReportReason.spamScam => l10n.reportReasonSpam,
        ReportReason.copyright => l10n.reportReasonCopyright,
        ReportReason.impersonation => l10n.reportReasonImpersonation,
        ReportReason.other => l10n.reportReasonOther,
      };
}
