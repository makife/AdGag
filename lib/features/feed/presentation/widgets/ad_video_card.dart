import "dart:async" show Timer, unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:video_player/video_player.dart";

import "../../../../core/analytics/ad_event_type.dart";
import "../../../../core/analytics/analytics_providers.dart";
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
/// Also the single place watch-quality analytics events are recorded
/// (section 26) — every card owns its own view/play/completion tracking
/// rather than duplicating that logic in FeedScreen and every other place
/// that shows a card (subject viewer, profile grid viewer).
class AdVideoCard extends ConsumerStatefulWidget {
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
  ConsumerState<AdVideoCard> createState() => _AdVideoCardState();
}

class _AdVideoCardState extends ConsumerState<AdVideoCard> {
  VideoPlayerController? _controller;
  Timer? _twoSecondTimer;
  bool _trackedPlayStarted = false;
  bool _trackedTwoSecondView = false;
  bool _trackedCompleted = false;
  bool _wasNearEnd = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.impression);
    _attach();
  }

  @override
  void didUpdateWidget(covariant AdVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad.id != widget.ad.id) {
      _resetTracking();
      ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.impression);
      _attach();
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncPlayback();
    }
  }

  void _resetTracking() {
    _twoSecondTimer?.cancel();
    _trackedPlayStarted = false;
    _trackedTwoSecondView = false;
    _trackedCompleted = false;
    _wasNearEnd = false;
  }

  void _attach() {
    // Detach from whatever controller this widget was previously
    // listening to — it may still be alive in the shared pool (e.g. a
    // neighboring card), and leaving a stale listener on it would fire
    // this widget's tracking callbacks for the *wrong* ad, or after this
    // State is no longer meaningfully current.
    _controller?.removeListener(_onControllerTick);

    final String? playbackId = widget.ad.playbackId;
    if (playbackId == null) {
      setState(() => _controller = null); // Not ready — thumbnail-only state.
      return;
    }
    final String url = widget.videoService.playbackUrl(playbackId);
    final VideoPlayerController controller =
        widget.pool.controllerFor(adId: widget.ad.id, playbackUrl: url);
    unawaited(controller.setLooping(true));
    controller.addListener(_onControllerTick);
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
      if (!_trackedPlayStarted) {
        _trackedPlayStarted = true;
        ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.playStarted);
      }
      _twoSecondTimer?.cancel();
      _twoSecondTimer = Timer(const Duration(seconds: 2), () {
        final VideoPlayerController? c = _controller;
        if (!_trackedTwoSecondView && widget.isActive && (c?.value.isPlaying ?? false)) {
          _trackedTwoSecondView = true;
          ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.twoSecondView);
        }
      });
    } else {
      unawaited(controller.pause());
      _twoSecondTimer?.cancel();
    }
  }

  /// Since Ads loop (setLooping(true)), "completed" and "rewatched" are
  /// both detected the same way: position snaps back near zero shortly
  /// after having been near the end. The first such wrap is `completed`;
  /// any wrap after that is `rewatched`.
  void _onControllerTick() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final Duration position = controller.value.position;
    final Duration duration = controller.value.duration;
    if (duration == Duration.zero) {
      return;
    }

    final bool isNearEnd = position >= duration - const Duration(milliseconds: 300);
    final bool justWrapped = _wasNearEnd && position < const Duration(milliseconds: 300);

    if (justWrapped) {
      if (!_trackedCompleted) {
        _trackedCompleted = true;
        ref
            .read(analyticsServiceProvider)
            .track(widget.ad.id, AdEventType.completed, watchMs: duration.inMilliseconds);
      } else {
        ref
            .read(analyticsServiceProvider)
            .track(widget.ad.id, AdEventType.rewatched, watchMs: duration.inMilliseconds);
      }
    }
    _wasNearEnd = isNearEnd;
  }

  @override
  void dispose() {
    _twoSecondTimer?.cancel();
    _controller?.removeListener(_onControllerTick);
    super.dispose();
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
