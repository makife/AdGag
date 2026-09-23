import "ad.dart";

/// One cursor-paginated page of feed results (CLAUDE.md section 16 — cursor
/// pagination, not offset, and metadata only).
final class FeedPage {
  const FeedPage({required this.ads, required this.nextCursor});

  final List<Ad> ads;

  /// Opaque cursor for the next page, or null if this was the last page.
  /// Callers must not parse/construct this value themselves.
  final String? nextCursor;
}
