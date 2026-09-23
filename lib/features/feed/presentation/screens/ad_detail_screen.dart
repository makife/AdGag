import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../providers/feed_providers.dart";
import "../widgets/ad_video_card.dart";

/// `/ad/:id` deep-link target (CLAUDE.md section 33/54) — what a shared Ad
/// link actually opens to. A single-item version of the feed's playback
/// mechanics, not a route into the ranked feed itself (the shared Ad may
/// not even be near the top of the viewer's own feed).
class AdDetailScreen extends ConsumerStatefulWidget {
  const AdDetailScreen({required this.adId, super.key});

  final String adId;

  @override
  ConsumerState<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends ConsumerState<AdDetailScreen> {
  final VideoControllerPool _pool = VideoControllerPool();

  @override
  void dispose() {
    _pool.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adAsync = ref.watch(adByIdProvider(widget.adId));

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      extendBodyBehindAppBar: true,
      body: adAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Text("Couldn't load this Ad.", style: Theme.of(context).textTheme.bodyMedium),
        ),
        data: (ad) {
          if (ad == null) {
            return Center(
              child: Text(
                "This ad isn't available anymore.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            );
          }
          return AdVideoCard(
            ad: ad,
            pool: _pool,
            videoService: ref.read(videoServiceProvider),
            isActive: true,
          );
        },
      ),
    );
  }
}
