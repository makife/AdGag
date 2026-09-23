import "comment.dart";

/// Cursor-paginated per CLAUDE.md section 8/16 — no offset pagination even
/// for a single Ad's comment list, since a popular Ad can have thousands.
/// The cursor is simply the oldest-so-far comment's `created_at`
/// (timestamp-only, unlike the feed's composite keyset) — comment lists
/// are lower-stakes than the main feed, so the rare edge case of two
/// comments sharing a millisecond isn't worth the extra complexity here.
abstract interface class CommentsRepository {
  Future<List<Comment>> fetchPage({required String adId, DateTime? before, int limit = 20});

  Future<Comment> create({required String adId, required String body});

  Future<void> deleteOwn(String commentId);
}
