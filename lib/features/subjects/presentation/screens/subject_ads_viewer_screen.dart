import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../feed/presentation/providers/reviews_panel_provider.dart";
import "../../../feed/presentation/widgets/feed_page_physics.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../feed/presentation/widgets/ad_video_card.dart";

/// Fullscreen vertical viewer over a fixed list of Ads — opened from
/// MARKET, subject pages, profiles and the AD THIS chain (CLAUDE.md section
/// 10). Same playback mechanics AND layout as [FeedScreen]: bounded pool,
/// neighbours preloaded, the active card switched once a swipe settles,
/// pages ending at the bottom-nav bar. (It used to run under the bar with
/// no preloading: Ads were cropped differently from Home and started late —
/// device report.) Pausing when another tab or page covers it is handled by
/// [AdVideoCard] itself.
class SubjectAdsViewerScreen extends ConsumerStatefulWidget {
  const SubjectAdsViewerScreen({required this.ads, required this.initialIndex, super.key});

  final List<Ad> ads;
  final int initialIndex;

  @override
  ConsumerState<SubjectAdsViewerScreen> createState() => _SubjectAdsViewerScreenState();
}

class _SubjectAdsViewerScreenState extends ConsumerState<SubjectAdsViewerScreen> {
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);
  final VideoControllerPool _pool = VideoControllerPool();
  late int _activeIndex = widget.initialIndex;

  /// The page a swipe has crossed into but not settled on yet.
  int? _pendingIndex;

  @override
  void dispose() {
    _pageController.dispose();
    _pool.disposeAll();
    super.dispose();
  }

  void _activate(int index) {
    if (index == _activeIndex) {
      return;
    }
    setState(() => _activeIndex = index);
    final Set<String> keep = <String>{
      if (index - 1 >= 0) widget.ads[index - 1].id,
      widget.ads[index].id,
      if (index + 1 < widget.ads.length) widget.ads[index + 1].id,
    };
    _pool.evictAllExcept(keep);
  }

  @override
  Widget build(BuildContext context) {
    // Inside a bottom-nav tab this is the bar (the shell extends its body
    // behind it); on a route without the bar it's the system inset.
    final double barInset = MediaQuery.paddingOf(context).bottom;
    final bool reviewsOpen = ref.watch(openReviewsAdIdProvider) != null;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      resizeToAvoidBottomInset: false, // the reviews panel handles the keyboard
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: barInset),
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (ScrollEndNotification notification) {
                    final int? pending = _pendingIndex;
                    if (pending != null && notification.depth == 0) {
                      _pendingIndex = null;
                      _activate(pending);
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    // Neighbours stay laid out, so the next Ad's player is
                    // already loading before the swipe reaches it.
                    allowImplicitScrolling: true,
                    scrollDirection: Axis.vertical,
                    // Same light-swipe paging as the feed; stops while reviews are open.
                    physics: reviewsOpen ? const NeverScrollableScrollPhysics() : const FeedPagePhysics(),
                    itemCount: widget.ads.length,
                    onPageChanged: (int index) {
                      _pendingIndex = index;
                      _pool.playOnly(widget.ads[index].id);
                      ref.read(openReviewsAdIdProvider.notifier).state = null;
                    },
                    itemBuilder: (BuildContext context, int index) {
                      return AdVideoCard(
                        ad: widget.ads[index],
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
          ),
          // No AppBar here — it would look like a different screen from
          // the rest of the app's fullscreen video presentation. This
          // still has to be reachable somehow other than the system back
          // gesture (which isn't discoverable on every device/nav mode).
          if (!reviewsOpen)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
