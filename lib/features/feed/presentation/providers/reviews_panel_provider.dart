import "package:flutter_riverpod/flutter_riverpod.dart";

/// Which Ad's REVIEWS panel is open, or null. The card showing that Ad
/// shrinks its video to the top and shows the panel underneath (instead
/// of a modal sheet covering the video), and the feed stops paging while
/// it's open.
final StateProvider<String?> openReviewsAdIdProvider = StateProvider<String?>((ref) => null);
