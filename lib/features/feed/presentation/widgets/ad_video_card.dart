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
import "../../../../core/video/video_providers.dart";
import "../../../../core/video/video_service.dart";
import "../../../../shared/widgets/creator_header.dart";
import "../../../../shared/widgets/subject_badge.dart";
import "../../../comments/presentation/widgets/reviews_panel.dart";
import "../../domain/ad.dart";
import "../providers/reviews_panel_provider.dart";
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

/// Height of the bottom-nav bar (plus the system inset under it) that sits
/// over the bottom of this card. `Scaffold(extendBody: true)` in AppShell
/// ALREADY puts exactly that into the body's MediaQuery padding.bottom —
/// the old code added AppShell's bar height on top of it, counting the bar
/// twice: the reviews panel stopped a whole bar-height above the bar
/// (user-reported black gap) and the action rail sat too high.
double _navBarClearance(BuildContext context) => MediaQuery.paddingOf(context).bottom;

/// Bottom-anchored overlays (rail, creator text) sit just above the bar and
/// the scrubber.
double _bottomClearance(BuildContext context) => _navBarClearance(context) + _scrubberHeight + AppSpacing.xs;

const double _scrubberHeight = 28;

const Duration _panelAnimation = Duration(milliseconds: 260);

class _AdVideoCardState extends ConsumerState<AdVideoCard> {
  VideoPlayerController? _controller;
  bool _reviewsEverOpened = false;
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
    final VideoPlayerController controller = widget.pool.controllerFor(adId: widget.ad.id, playbackUrl: url);
    unawaited(controller.setLooping(true));
    unawaited(controller.setVolume(ref.read(isFeedMutedProvider) ? 0 : 1));
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
        ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.completed, watchMs: duration.inMilliseconds);
      } else {
        ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.rewatched, watchMs: duration.inMilliseconds);
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

  void _togglePlayPause() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      if (controller.value.isPlaying) {
        unawaited(controller.pause());
      } else {
        unawaited(controller.play());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool showVideo = controller != null && controller.value.isInitialized;
    final bool isPaused = showVideo && !controller.value.isPlaying;

    ref.listen(isFeedMutedProvider, (bool? previous, bool next) {
      final VideoPlayerController? c = _controller;
      if (c != null) {
        unawaited(c.setVolume(next ? 0 : 1));
      }
    });
    final bool isMuted = ref.watch(isFeedMutedProvider);

    final bool reviewsOpen = ref.watch(openReviewsAdIdProvider) == widget.ad.id;
    if (reviewsOpen) {
      _reviewsEverOpened = true; // keep the panel mounted so it can slide back out
    }
    void closeReviews() => ref.read(openReviewsAdIdProvider.notifier).state = null;
    final double statusBar = MediaQuery.paddingOf(context).top;

    // contain, not cover: a 9:16 Ad on a taller (~9:20) phone would be
    // cropped ~12% off each side, cutting off anything near the edges
    // (the editor's border effects were reported as "overflowing the
    // screen"). Anchored to the TOP (just under the status bar): centring
    // left a big black band above the video.
    final Widget videoLayer = showVideo
        ? FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          )
        : widget.ad.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: widget.ad.thumbnailUrl!,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                errorWidget: (context, url, error) => const SizedBox.shrink(),
              )
            : const Center(child: CircularProgressIndicator());

    return PopScope(
      // System back closes the reviews panel first.
      canPop: !reviewsOpen,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && reviewsOpen) {
          closeReviews();
        }
      },
      child: ColoredBox(
        color: AppColors.darkBackground,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double height = constraints.maxHeight;
            final double openVideoHeight = height * 0.36;
            // The bottom-nav bar sits over the bottom of this card (extendBody)
            // — except while the keyboard is up, when it's behind the keyboard.
            // The keyboard is read from the raw window insets: the Scaffolds
            // above remove it from MediaQuery once they've resized for it.
            final bool keyboardUp = MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
            final double navClearance = keyboardUp ? 0 : _navBarClearance(context);
            final double panelTop = statusBar + openVideoHeight;
            final double panelHeight = (height - panelTop - navClearance).clamp(0, height);

            return Stack(
              children: <Widget>[
                AnimatedPositioned(
                  duration: _panelAnimation,
                  curve: Curves.easeOutCubic,
                  top: statusBar,
                  left: 0,
                  right: 0,
                  height: reviewsOpen ? openVideoHeight : height - statusBar,
                  child: GestureDetector(
                    // With the panel open, tapping the (small) video closes it.
                    onTap: reviewsOpen ? closeReviews : _togglePlayPause,
                    child: videoLayer,
                  ),
                ),
                // Seekable progress bar, pinned right above the nav bar (which
                // fills the space under a 9:16 video, so this is the video's
                // bottom edge). Thin while watching; drag or tap to scrub.
                if (showVideo && !reviewsOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: navClearance,
                    height: _scrubberHeight,
                    child: _Scrubber(controller: controller),
                  ),
                if (isPaused && !reviewsOpen)
                  const IgnorePointer(
                    child: Center(
                      child: Icon(Icons.play_arrow, size: 72, color: Colors.white70),
                    ),
                  ),
                if (!reviewsOpen) ...<Widget>[
                  Positioned(
                    top: AppSpacing.md,
                    right: AppSpacing.md,
                    child: SafeArea(
                      child: _MuteButton(
                        isMuted: isMuted,
                        onTap: () => ref.read(isFeedMutedProvider.notifier).state = !isMuted,
                      ),
                    ),
                  ),
                  Positioned(
                    right: AppSpacing.md,
                    bottom: _bottomClearance(context),
                    child: FeedActionRail(ad: widget.ad),
                  ),
                  Positioned(
                    left: AppSpacing.lg,
                    right: 88, // keep clear of the action rail
                    bottom: _bottomClearance(context),
                    child: _Overlay(ad: widget.ad),
                  ),
                ],
                if (_reviewsEverOpened)
                  AnimatedPositioned(
                    duration: _panelAnimation,
                    curve: Curves.easeOutCubic,
                    top: reviewsOpen ? panelTop : height,
                    left: 0,
                    right: 0,
                    height: panelHeight,
                    child: ReviewsPanel(adId: widget.ad.id, onClose: closeReviews),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Thin progress line that turns into a scrubber: tap or drag horizontally
/// to seek (a horizontal drag doesn't compete with the feed's vertical
/// paging). Rebuilds only itself on position ticks.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// Fraction being dragged to (null when not dragging).
  double? _dragFraction;

  void _seekToFraction(double fraction) {
    final Duration total = widget.controller.value.duration;
    if (total > Duration.zero) {
      unawaited(widget.controller.seekTo(total * fraction.clamp(0.0, 1.0)));
    }
  }

  String _clock(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, "0")}";

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        double fractionAt(double dx) => (dx / width).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) => _seekToFraction(fractionAt(d.localPosition.dx)),
          onHorizontalDragStart: (DragStartDetails d) => setState(() => _dragFraction = fractionAt(d.localPosition.dx)),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              setState(() => _dragFraction = fractionAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) {
            final double? f = _dragFraction;
            setState(() => _dragFraction = null);
            if (f != null) {
              _seekToFraction(f);
            }
          },
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: widget.controller,
            builder: (BuildContext context, VideoPlayerValue value, Widget? child) {
              final int total = value.duration.inMilliseconds;
              final double played = total <= 0 ? 0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
              final bool dragging = _dragFraction != null;
              final double fraction = _dragFraction ?? played;
              final double barHeight = dragging ? 6 : 3;
              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (dragging)
                    Positioned(
                      bottom: barHeight + 6,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Text(
                          "${_clock(value.duration * fraction)} / ${_clock(value.duration)}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: barHeight,
                    child: Stack(
                      children: <Widget>[
                        const Positioned.fill(child: ColoredBox(color: Colors.white24)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.brandGradient)),
                        ),
                      ],
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      left: (width * fraction - 7).clamp(0.0, width - 14),
                      bottom: barHeight / 2 - 7,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.isMuted, required this.onTap});

  final bool isMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
        child: Icon(
          isMuted ? Icons.volume_off : Icons.volume_up,
          color: Colors.white,
          size: 20,
        ),
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
        if (ad.subjectDisplayName != null) SubjectBadge(subjectId: ad.subjectId, displayName: ad.subjectDisplayName!),
        const SizedBox(height: AppSpacing.sm),
        CreatorHeader(userId: ad.userId, username: ad.creatorUsername, avatarUrl: ad.creatorAvatarUrl),
        if (ad.caption != null && ad.caption!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(ad.caption!, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}
