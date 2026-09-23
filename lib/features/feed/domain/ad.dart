import "ad_status.dart";

/// The content primitive (CLAUDE.md section 3/25/69). This is metadata
/// only — never video bytes (section 16) — matching the `ads` table plus
/// what the feed needs to render an overlay (section 6).
final class Ad {
  const Ad({
    required this.id,
    required this.userId,
    required this.subjectId,
    required this.status,
    required this.viewCount,
    required this.soldCount,
    required this.commentCount,
    required this.shareCount,
    required this.adThisCount,
    required this.createdAt,
    this.caption,
    this.playbackId,
    this.thumbnailUrl,
    this.durationMs,
    this.inspiredByAdId,
    this.dailyChallengeId,
    this.publishedAt,
    this.subjectDisplayName,
    this.creatorUsername,
  });

  factory Ad.fromRow(Map<String, dynamic> row) {
    // ad_subjects/profiles are only present when the query embedded them
    // via PostgREST's relationship syntax (see FeedRepositoryImpl) — both
    // are null for a bare `ads` row, e.g. the create/update draft RPCs.
    final Map<String, dynamic>? subjectEmbed = row["ad_subjects"] as Map<String, dynamic>?;
    final Map<String, dynamic>? profileEmbed = row["profiles"] as Map<String, dynamic>?;

    return Ad(
      id: row["id"] as String,
      userId: row["user_id"] as String,
      subjectId: row["subject_id"] as String,
      caption: row["caption"] as String?,
      playbackId: row["playback_id"] as String?,
      thumbnailUrl: row["thumbnail_url"] as String?,
      durationMs: (row["duration_ms"] as num?)?.toInt(),
      status: AdStatus.fromDb(row["status"] as String),
      inspiredByAdId: row["inspired_by_ad_id"] as String?,
      dailyChallengeId: row["daily_challenge_id"] as String?,
      viewCount: (row["view_count"] as num).toInt(),
      soldCount: (row["sold_count"] as num).toInt(),
      commentCount: (row["comment_count"] as num).toInt(),
      shareCount: (row["share_count"] as num).toInt(),
      adThisCount: (row["ad_this_count"] as num).toInt(),
      createdAt: DateTime.parse(row["created_at"] as String),
      publishedAt:
          row["published_at"] == null ? null : DateTime.parse(row["published_at"] as String),
      subjectDisplayName: subjectEmbed?["display_name"] as String?,
      creatorUsername: profileEmbed?["username"] as String?,
    );
  }

  final String id;
  final String userId;
  final String subjectId;
  final String? caption;
  final String? playbackId;
  final String? thumbnailUrl;
  final int? durationMs;
  final AdStatus status;
  final String? inspiredByAdId;
  final String? dailyChallengeId;
  final int viewCount;
  final int soldCount;
  final int commentCount;
  final int shareCount;
  final int adThisCount;
  final DateTime createdAt;
  final DateTime? publishedAt;

  /// Denormalized display fields from an embedded feed query — see
  /// [Ad.fromRow]. Not part of the `ads` table itself.
  final String? subjectDisplayName;
  final String? creatorUsername;
}
