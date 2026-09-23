import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/moderation/domain/report_reason.dart";
import "package:adgag/features/moderation/domain/report_target_type.dart";

void main() {
  group("ReportReason.dbValue", () {
    // Mirrors the report_reason Postgres enum exactly (0012_reports_and_blocks.sql).
    // A mismatch here would make every report fail with a Postgres enum
    // cast error, so this is worth pinning down explicitly.
    const Map<ReportReason, String> expected = <ReportReason, String>{
      ReportReason.nudity: "nudity",
      ReportReason.violence: "violence",
      ReportReason.hateHarassment: "hate_harassment",
      ReportReason.bullying: "bullying",
      ReportReason.dangerousActivity: "dangerous_activity",
      ReportReason.spamScam: "spam_scam",
      ReportReason.copyright: "copyright",
      ReportReason.impersonation: "impersonation",
      ReportReason.other: "other",
    };

    for (final entry in expected.entries) {
      test("${entry.key} maps to '${entry.value}'", () {
        expect(entry.key.dbValue, entry.value);
      });
    }

    test("every ReportReason value is covered", () {
      expect(expected.keys.toSet(), ReportReason.values.toSet());
    });
  });

  group("ReportTargetType.dbValue", () {
    test("matches the report_target_type Postgres enum", () {
      expect(ReportTargetType.ad.dbValue, "ad");
      expect(ReportTargetType.user.dbValue, "user");
      expect(ReportTargetType.comment.dbValue, "comment");
    });
  });
}
