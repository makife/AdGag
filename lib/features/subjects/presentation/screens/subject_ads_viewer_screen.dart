import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../feed/presentation/widgets/ad_video_card.dart";

/// Fullscreen vertical viewer over a fixed list of Ads — used when tapping
/// into a subject page's grid (CLAUDE.md section 10). Same playback
/// mechanics as [FeedScreen] (bounded pool, one active controller at a
/// time) but over a static list rather than a paginated feed.
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

  @override
  void dispose() {
    _pageController.dispose();
    _pool.disposeAll();
    super.dispose();
  }

  void _onPageChanged(int index) {
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
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.ads.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (BuildContext context, int index) {
          return AdVideoCard(
            ad: widget.ads[index],
            pool: _pool,
            videoService: ref.read(videoServiceProvider),
            isActive: index == _activeIndex,
          );
        },
      ),
    );
  }
}
