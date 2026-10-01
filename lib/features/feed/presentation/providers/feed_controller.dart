import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../comments/presentation/providers/comments_controller.dart";
import "../../domain/ad.dart";
import "../../domain/feed_repository.dart";
import "feed_providers.dart";
import "sold_providers.dart";

final class FeedState {
  const FeedState({required this.ads, required this.nextCursor, required this.isLoadingMore});

  final List<Ad> ads;
  final String? nextCursor;
  final bool isLoadingMore;

  FeedState copyWith({List<Ad>? ads, String? nextCursor, bool clearCursor = false, bool? isLoadingMore}) {
    return FeedState(
      ads: ads ?? this.ads,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// The Home tab's selected feed ("For You" / "Following"). The feed
/// controller watches it, so switching refetches from the first page.
final StateProvider<FeedKind> feedKindProvider = StateProvider<FeedKind>((ref) => FeedKind.forYou);

/// Drives the feed screen: initial page load, "load more" as the user
/// nears the end of the current page, and pull-to-refresh. Page-fetching
/// logic itself lives in [FeedRepository] — this just sequences calls to
/// it and folds results into paginated state (CLAUDE.md section 16).
final class FeedController extends AsyncNotifier<FeedState> {
  @override
  Future<FeedState> build() async {
    final page = await ref.read(feedRepositoryProvider).fetchPage(kind: ref.watch(feedKindProvider));
    return FeedState(ads: page.ads, nextCursor: page.nextCursor, isLoadingMore: false);
  }

  Future<void> loadMore() async {
    final FeedState? current = state.valueOrNull;
    if (current == null || current.isLoadingMore || current.nextCursor == null) {
      return;
    }

    final FeedKind kind = ref.read(feedKindProvider);
    state = AsyncData<FeedState>(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref.read(feedRepositoryProvider).fetchPage(kind: kind, cursor: current.nextCursor);
      if (ref.read(feedKindProvider) != kind) {
        return; // switched feeds meanwhile: this page belongs to the other one
      }
      final FeedState latest = state.value ?? current;
      state = AsyncData<FeedState>(
        FeedState(
          ads: <Ad>[...latest.ads, ...page.ads],
          nextCursor: page.nextCursor,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      // Keep existing ads visible on a failed "load more" — only stop the
      // spinner. The user can retry by scrolling again.
      final FeedState latest = state.value ?? current;
      state = AsyncData<FeedState>(latest.copyWith(isLoadingMore: false));
    }
  }

  /// Pull-to-refresh: fetches the first page again and swaps it in. The
  /// current Ads stay on screen while it loads, and on a failure (the error
  /// is rethrown for the caller to show) — never a full-screen spinner.
  /// Drops every loaded Ad by [userId] at once (after blocking them) — the
  /// server already filters blocked creators out of later pages.
  void hideCreator(String userId) {
    final FeedState? current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData<FeedState>(
      current.copyWith(ads: current.ads.where((ad) => ad.userId != userId).toList(growable: false)),
    );
  }

  Future<void> refresh() async {
    final FeedKind kind = ref.read(feedKindProvider);
    final page = await ref.read(feedRepositoryProvider).fetchPage(kind: kind);
    if (ref.read(feedKindProvider) != kind) {
      return;
    }
    // Fresh counts include the viewer's own SOLDs, shares and reviews: start
    // the local adjustments over. (The review one was missing, so a review
    // you posted was counted twice after a refresh — owner report.)
    ref.invalidate(soldBaselineProvider);
    ref.invalidate(shareCountDeltaProvider);
    ref.invalidate(commentCountDeltaProvider);
    state = AsyncData<FeedState>(FeedState(ads: page.ads, nextCursor: page.nextCursor, isLoadingMore: false));
  }
}

final AsyncNotifierProvider<FeedController, FeedState> feedControllerProvider =
    AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);
