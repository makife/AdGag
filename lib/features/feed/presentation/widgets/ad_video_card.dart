import "dart:async" show unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_service.dart";
import "../../../../shared/widgets/creator_header.dart";
import "../../../../shared/widgets/subject_badge.dart";
import "../../domain/ad.dart";
import "feed_action_rail.dart";

/// One fullscreen feed item (CLAUDE.md section 6): subject badge, creator
/// + FOLLOW, caption, and the SOLD/REVIEWS/AD THIS/SHARE action rail.
class AdVideoCard extends StatefulWidget {
  const AdVideoCard({
    required this.ad,
    required this.pool,
    required this.videoService,
    required this.isActive,
    super.key,
  });

  final Ad ad;
  final VideoControllerPool pool;
  final VideoService videoService;
  final bool isActive;

  @override
  State<AdVideoCard> createState() => _AdVideoCardState();
}

class _AdVideoCardState extends State<AdVideoCard> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant AdVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad.id != widget.ad.id) {
      _attach();
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncPlayback();
    }
  }

  void _attach() {
    final String? playbackId = widget.ad.playbackId;
    if (playbackId == null) {
      return; // Not ready — thumbnail-only state, nothing to attach.
    }
    final String url = widget.videoService.playbackUrl(playbackId);
    final VideoPlayerController controller =
        widget.pool.controllerFor(adId: widget.ad.id, playbackUrl: url);
    unawaited(controller.setLooping(true));
    setState(() => _controller = controller);
    widget.pool.initializationOf(widget.ad.id)?.then((_) {
      if (mounted) {
        setState(() {}); // trigger rebuild once initialized to show the frame
        _syncPlayback();
      }
    });
  }

  void _syncPlayback() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.isActive) {
      widget.pool.pauseAllExcept(widget.ad.id);
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool showVideo = controller != null && controller.value.isInitialized;

    return ColoredBox(
      color: AppColors.darkBackground,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (showVideo)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else if (widget.ad.thumbnailUrl != null)
            CachedNetworkImage(
              imageUrl: widget.ad.thumbnailUrl!,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            )
          else
            const Center(child: CircularProgressIndicator()),

          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.xxxl,
            child: FeedActionRail(ad: widget.ad),
          ),

          Positioned(
            left: AppSpacing.lg,
            right: 88, // keep clear of the action rail
            bottom: AppSpacing.xxxl,
            child: _Overlay(ad: widget.ad),
          ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.ad});

  final Ad ad;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (ad.subjectDisplayName != null)
          SubjectBadge(subjectId: ad.subjectId, displayName: ad.subjectDisplayName!),
        const SizedBox(height: AppSpacing.xs),
        CreatorHeader(userId: ad.userId, username: ad.creatorUsername),
        if (ad.caption != null && ad.caption!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(ad.caption!, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}
