/// TODAY'S AD (CLAUDE.md section 11).
final class DailyChallenge {
  const DailyChallenge({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.prompt,
    required this.startsAt,
    required this.endsAt,
    required this.participantCount,
    this.iconUrl,
  });

  factory DailyChallenge.fromRow(Map<String, dynamic> row) {
    return DailyChallenge(
      id: row["id"] as String,
      subjectId: row["subject_id"] as String,
      title: row["title"] as String,
      prompt: row["prompt"] as String,
      iconUrl: row["icon_url"] as String?,
      startsAt: DateTime.parse(row["starts_at"] as String),
      endsAt: DateTime.parse(row["ends_at"] as String),
      participantCount: (row["participant_count"] as num).toInt(),
    );
  }

  final String id;
  final String subjectId;
  final String title;
  final String prompt;
  final String? iconUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final int participantCount;
}
