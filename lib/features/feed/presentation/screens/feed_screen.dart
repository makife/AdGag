import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../../core/localization/generated/app_localizations.dart";

import "../../../../core/router/app_shell.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../../../../core/widgets/coming_soon_view.dart";
import "../../domain/ad.dart";
import "../providers/feed_controller.dart";
import "../providers/reviews_panel_provider.dart";
import "../widgets/ad_video_card.dart";
import "../widgets/feed_page_physics.dart";

/// HOME / FEED (CLAUDE.md section 6). Fullscreen vertical Ad feed with
/// bounded-pool preloading (section 17) and the SOLD/REVIEWS/AD THIS/
/// SHARE action rail (section 64) via [AdVideoCard].
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final VideoControllerPool _pool = VideoControllerPool();
  int _activeIndex = 0;

  /// The page the swipe has crossed into but hasn't settled on yet.
  int? _pendingIndex;

  // Section 63: "After several swipes, subtly surface: 'Think you can do
  // better?' AD THIS." Session-only (not persisted) — a returning user who
  // already knows the mechanic seeing it once more per app launch is a
  // reasonable trade-off against the complexity of persisting "seen" state.
  bool _hasShownAdThisHint = false;
  static const int _adThisHintAfterSwipes = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Section 17: pause playback immediately when the app backgrounds.
    if (state != AppLifecycleState.resumed) {
      _pool.pauseAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _pool.disposeAll();
    super.dispose();
  }

  /// Called once a swipe has SETTLED (ScrollEndNotification), not when the
  /// page crosses the halfway mark mid-animation: switching the active
  /// card (rebuild, play/pause, pool eviction, next-page loading) during
  /// the swipe animation made it hitch — the reported "hard to swipe".
  void _activate(int index, List<Ad> ads) {
    if (index == _activeIndex) {
      return;
    }
    setState(() => _activeIndex = index);

    // Keep the active card plus one neighbor on each side warm; drop the
    // rest (section 17: "Do NOT preload dozens of full videos").
    final Set<String> keep = <String>{
      if (index - 1 >= 0) ads[index - 1].id,
      ads[index].id,
      if (index + 1 < ads.length) ads[index + 1].id,
    };
    _pool.evictAllExcept(keep);

    if (index >= ads.length - 2) {
      unawaited(ref.read(feedControllerProvider.notifier).loadMore());
    }

    if (!_hasShownAdThisHint && index >= _adThisHintAfterSwipes) {
      _hasShownAdThisHint = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).feedAdThisHint),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    }
  }

  /// Pull-to-refresh (only reachable from the first card — the pull is an
  /// overscroll past the top of the pager). The new first page replaces the
  /// list; players for Ads no longer in it are dropped.
  Future<void> _refresh() async {
    try {
      await ref.read(feedControllerProvider.notifier).refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).feedRefreshFailed)));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final List<Ad> ads = ref.read(feedControllerProvider).valueOrNull?.ads ?? const <Ad>[];
    _pendingIndex = null;
    setState(() => _activeIndex = 0);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    _pool.evictAllExcept(<String>{for (final Ad ad in ads.take(2)) ad.id});
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FeedState> feedAsync = ref.watch(feedControllerProvider);

    // IndexedStack (StatefulShellRoute.indexedStack) keeps this screen
    // mounted, not paused, when another bottom-nav tab is showing — without
    // this listener the active video keeps playing behind e.g. the AD
    // (creation) tab, and never resumes on returning to Home.
    ref.listen(activeShellBranchIndexProvider, (int? previous, int next) {
      if (next == 0) {
        final List<Ad>? ads = ref.read(feedControllerProvider).valueOrNull?.ads;
        if (ads != null && _activeIndex < ads.length) {
          _pool.resume(ads[_activeIndex].id);
        }
      } else {
        _pool.pauseAll();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      resizeToAvoidBottomInset: false, // see AdVideoCard: the reviews panel handles the keyboard
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "${AppLocalizations.of(context).feedLoadFailed}\n$error",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
        data: (FeedState feedState) {
          final double topInset = MediaQuery.paddingOf(context).top;
          if (feedState.ads.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              edgeOffset: topInset,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: ComingSoonView(
                      title: AppLocalizations.of(context).feedEmptyTitle,
                      phaseNote: AppLocalizations.of(context).feedEmptyBody,
                    ),
                  ),
                ),
              ),
            );
          }

          // The pager ends at the bottom-nav bar's top edge (the Scaffold
          // extends the body behind the bar): pages as tall as the space above
          // the bar, so one Ad's bottom touches the next one's top. When pages
          // reached under the bar, the strip hidden behind it scrolled into view
          // between two Ads as a thick black gap (user report).
          final double barInset = MediaQuery.paddingOf(context).bottom;

          // Pull down on the first card to refresh. The indicator only
          // reacts to an overscroll past the pager's top, so it never
          // competes with an ordinary page swipe; it's disabled while a
          // reviews panel is open (the pager is locked then anyway).
          return Padding(
            padding: EdgeInsets.only(bottom: barInset),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: RefreshIndicator(
                onRefresh: _refresh,
                edgeOffset: topInset,
                notificationPredicate: (ScrollNotification notification) =>
                    notification.depth == 0 && ref.read(openReviewsAdIdProvider) == null,
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (ScrollEndNotification notification) {
                    final int? pending = _pendingIndex;
                    if (pending != null && notification.depth == 0) {
                      _pendingIndex = null;
                      _activate(pending, feedState.ads);
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    // Keep the neighbours laid out, so revealing the next card
                    // mid-swipe doesn't build it on the spot.
                    allowImplicitScrolling: true,
                    scrollDirection: Axis.vertical,
                    // Paging stops while a card's reviews panel is open.
                    physics: ref.watch(openReviewsAdIdProvider) != null
                        ? const NeverScrollableScrollPhysics()
                        : const FeedPagePhysics(),
                    itemCount: feedState.ads.length,
                    onPageChanged: (int index) {
                      _pendingIndex = index;
                      ref.read(openReviewsAdIdProvider.notifier).state = null;
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final Ad ad = feedState.ads[index];
                      return AdVideoCard(
                        ad: ad,
                        pool: _pool,
                        videoService: ref.read(videoServiceProvider),
                        isActive: index == _activeIndex,
                        belowCardHeight: barInset,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
