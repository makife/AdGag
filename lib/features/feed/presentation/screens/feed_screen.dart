import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../../../../core/widgets/coming_soon_view.dart";
import "../../domain/ad.dart";
import "../providers/feed_controller.dart";
import "../widgets/ad_video_card.dart";

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

  void _onPageChanged(int index, List<Ad> ads) {
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
          const SnackBar(
            content: Text("Think you can do better? Try AD THIS."),
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FeedState> feedAsync = ref.watch(feedControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't load the feed.\n$error",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
        data: (FeedState feedState) {
          if (feedState.ads.isEmpty) {
            return const ComingSoonView(
              title: "No one's sold anything yet.",
              phaseNote: "Be the first to advertise something — creation lands in Phase D.",
            );
          }

          // No RefreshIndicator: its own vertical drag-to-refresh gesture
          // would fight the feed's vertical page-swipe. The initial page
          // already loads fresh on cold start; a dedicated manual-refresh
          // affordance can be added later if needed.
          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: feedState.ads.length,
            onPageChanged: (int index) => _onPageChanged(index, feedState.ads),
            itemBuilder: (BuildContext context, int index) {
              final Ad ad = feedState.ads[index];
              return AdVideoCard(
                ad: ad,
                pool: _pool,
                videoService: ref.read(videoServiceProvider),
                isActive: index == _activeIndex,
              );
            },
          );
        },
      ),
    );
  }
}
