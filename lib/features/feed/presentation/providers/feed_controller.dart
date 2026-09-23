import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/ad.dart";
import "feed_providers.dart";

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

/// Drives the feed screen: initial page load, "load more" as the user
/// nears the end of the current page, and pull-to-refresh. Page-fetching
/// logic itself lives in [FeedRepository] — this just sequences calls to
/// it and folds results into paginated state (CLAUDE.md section 16).
final class FeedController extends AsyncNotifier<FeedState> {
  @override
  Future<FeedState> build() async {
    final page = await ref.read(feedRepositoryProvider).fetchPage();
    return FeedState(ads: page.ads, nextCursor: page.nextCursor, isLoadingMore: false);
  }

  Future<void> loadMore() async {
    final FeedState? current = state.valueOrNull;
    if (current == null || current.isLoadingMore || current.nextCursor == null) {
      return;
    }

    state = AsyncData<FeedState>(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref.read(feedRepositoryProvider).fetchPage(cursor: current.nextCursor);
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

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<FeedController, FeedState> feedControllerProvider =
    AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);
