import "dart:async" show Timer, unawaited;

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:video_player/video_player.dart";

import "../../../../core/analytics/ad_event_type.dart";
import "../../../../core/analytics/analytics_providers.dart";
import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/video/video_controller_pool.dart";
import "../../../../core/video/video_providers.dart";
import "../../../../core/video/video_service.dart";
import "../../../../shared/widgets/count_label.dart";
import "../../../../shared/widgets/creator_header.dart";
import "../../../../shared/widgets/subject_badge.dart";
import "../../../comments/presentation/widgets/reviews_panel.dart";
import "../../domain/ad.dart";
import "../providers/feed_providers.dart";
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
    this.belowCardHeight = 0,
    super.key,
  });

  final Ad ad;
  final VideoControllerPool pool;
  final VideoService videoService;
  final bool isActive;

  /// How much of the screen lies below this card (the bottom-nav bar — the
  /// feed's pages end at its top edge). Lets the reviews panel work out how
  /// far the keyboard reaches into the card.
  final double belowCardHeight;

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
double _bottomClearance(BuildContext context) => _navBarClearance(context) + _scrubberLift + _scrubberHeight;

/// Touch area of the scrubber; the visible line sits at its bottom, a few
/// px above the bar's top border so the two never read as one line.
const double _scrubberHeight = 36;
const double _scrubberLift = 6;

const Duration _panelAnimation = Duration(milliseconds: 260);

class _AdVideoCardState extends ConsumerState<AdVideoCard> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _reviewsEverOpened = false;
  Timer? _twoSecondTimer;
  bool _trackedPlayStarted = false;
  bool _trackedTwoSecondView = false;
  bool _trackedCompleted = false;
  bool _wasNearEnd = false;

  /// Whether this card can actually be seen: its bottom-nav tab is the one
  /// showing (go_router's indexed stack turns tickers off in hidden
  /// branches) and no other page is pushed over it. A card that is
  /// [AdVideoCard.isActive] but not visible must not play — a viewer opened
  /// from MARKET kept playing (with sound) behind other tabs and pages
  /// (device report).
  bool _visible = true;

  bool _appInForeground = true;

  /// The viewer tapped pause on this card. Only then is the big play icon
  /// shown — a card that is merely not playing yet (just swiped to, still
  /// starting) or that was paused by a swipe showed it after every swipe.
  /// Cleared when the card stops being the active one.
  bool _pausedByUser = false;

  /// The player has shown a real frame (it has played past 0). Until then the
  /// thumbnail stays ON TOP of the video: an initialized player can still be
  /// a blank texture for a moment, which flashed black between the thumbnail
  /// and the first frame on every swipe (owner: "blinks when it autoplays").
  bool _hasRenderedFrame = false;

  bool get _shouldPlay => widget.isActive && _visible && _appInForeground;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    if (visible != _visible) {
      _visible = visible;
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool foreground = state == AppLifecycleState.resumed;
    if (foreground != _appInForeground) {
      _appInForeground = foreground;
      _syncPlayback();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _pausedByUser = false;
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
    // A pooled player that already played (a neighbour, coming back) has a frame.
    _hasRenderedFrame = controller.value.isInitialized && controller.value.position > Duration.zero;
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
    if (_shouldPlay && !_pausedByUser) {
      widget.pool.pauseAllExcept(widget.ad.id);
      unawaited(controller.play());
      if (!_trackedPlayStarted) {
        _trackedPlayStarted = true;
        ref.read(analyticsServiceProvider).track(widget.ad.id, AdEventType.playStarted);
      }
      _twoSecondTimer?.cancel();
      _twoSecondTimer = Timer(const Duration(seconds: 2), () {
        final VideoPlayerController? c = _controller;
        if (!_trackedTwoSecondView && _shouldPlay && (c?.value.isPlaying ?? false)) {
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
    if (!_hasRenderedFrame && position > Duration.zero && mounted) {
      setState(() => _hasRenderedFrame = true);
    }
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

  /// The keyboard opening/closing: the reviews panel lays itself out around it.
  @override
  void didChangeMetrics() {
    if (mounted && ref.read(openReviewsAdIdProvider) == widget.ad.id) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        _pausedByUser = true;
        unawaited(controller.pause());
      } else {
        _pausedByUser = false;
        unawaited(controller.play());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool showVideo = controller != null && controller.value.isInitialized;
    final bool isPaused = showVideo && _pausedByUser && !controller.value.isPlaying;

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

    // The Ad fills the whole card, status bar area included, so Ads sit
    // edge to edge while swiping (a black band under each one showed up as
    // a thick gap between them — user report). The card ends at the nav
    // bar, which AppShell sizes so the card is ~9:16 plus the status bar:
    // a 9:16 Ad loses only a sliver at the sides. A clearly different shape
    // (landscape, square) is letterboxed instead — covering it would cut
    // most of it away. The small video above an open reviews panel is the
    // SAME picture scaled down (same crop, card-shaped box): showing it
    // uncropped there made text in the Ad sit at a different distance from
    // the edges than in the full card (user report).
    BoxFit fitFor(Size card) {
      if (!showVideo) {
        return BoxFit.cover;
      }
      final Size v = controller.value.size;
      if (v.width <= 0 || v.height <= 0 || card.width <= 0 || card.height <= 0) {
        return BoxFit.contain;
      }
      final double a = v.width / v.height;
      final double c = card.width / card.height;
      final double cropped = 1 - (a < c ? a / c : c / a);
      return cropped <= 0.2 ? BoxFit.cover : BoxFit.contain;
    }

    Widget videoLayerFor(Size card) {
      final BoxFit fit = fitFor(card);
      final String? thumb = widget.ad.thumbnailUrl;
      final Widget? thumbnail = thumb == null
          ? null
          : CachedNetworkImage(
              imageUrl: thumb,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              // No fade: fading in from black was a blink of its own.
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            );
      if (!showVideo) {
        return thumbnail ?? const Center(child: CircularProgressIndicator());
      }
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          // Same picture as the first frame, until that frame is really on screen.
          if (!_hasRenderedFrame && thumbnail != null) thumbnail,
        ],
      );
    }

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
            final Widget videoLayer = videoLayerFor(Size(constraints.maxWidth, height));
            // The home tab does NOT resize for the keyboard (AppShell /
            // FeedScreen): the card keeps its full height and the reviews
            // panel makes room itself. Resizing the whole pager under an open
            // panel is what made it jump up and vanish (user report). The
            // keyboard is read from the window insets (didChangeMetrics
            // rebuilds this card while its panel is open). It's measured from
            // the SCREEN bottom; the card ends belowCardHeight above that.
            final double keyboard = MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
            final bool keyboardUp = keyboard > 0;
            final double keyboardInCard = (keyboard - widget.belowCardHeight).clamp(0, height);
            // Smaller video while typing, so the reviews stay readable.
            final double openVideoHeight = height * (keyboardUp ? 0.2 : 0.36);
            // Card-shaped (not screen-wide), centred: the full card scaled down.
            final double openVideoWidth = height > 0 ? openVideoHeight * constraints.maxWidth / height : 0;
            final double openVideoSide = ((constraints.maxWidth - openVideoWidth) / 2).clamp(0, constraints.maxWidth);
            // Anything of the card covered by the bottom bar (none in the feed,
            // whose pages end at the bar; kept for other hosts of this card).
            final double navClearance = keyboardUp ? 0 : _navBarClearance(context);
            final double panelTop = statusBar + openVideoHeight;
            final double panelHeight = (height - panelTop - navClearance).clamp(0, height);

            return Stack(
              children: <Widget>[
                AnimatedPositioned(
                  duration: _panelAnimation,
                  curve: Curves.easeOutCubic,
                  // Full card (status bar area included) while watching; the
                  // small video under the status bar with reviews open.
                  top: reviewsOpen ? statusBar : 0,
                  left: reviewsOpen ? openVideoSide : 0,
                  right: reviewsOpen ? openVideoSide : 0,
                  height: reviewsOpen ? openVideoHeight : height,
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
                    bottom: navClearance + _scrubberLift,
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
                    child: ReviewsPanel(adId: widget.ad.id, onClose: closeReviews, keyboardInset: keyboardInCard),
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
              final bool showKnob = dragging || !value.isPlaying;
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
                        // Clearly visible over any frame and against the black
                        // bar below (the first version — white24 track, gradient
                        // fill — was reported as invisible).
                        Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.35))),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: const ColoredBox(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  if (showKnob)
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
        // The AD THIS chain (CLAUDE.md section 9): where this Ad came from,
        // and how many Ads came from it.
        if (ad.inspiredByAdId != null) _InspiredByLine(originAdId: ad.inspiredByAdId!),
        if (ad.adThisCount > 0)
          _ChainLink(
            icon: Icons.bolt,
            text: AppLocalizations.of(context).adThisChainCount(CountLabel.format(ad.adThisCount)),
            onTap: () => unawaited(context.pushTo(RoutePaths.adThisChainOf(ad.id))),
          ),
      ],
    );
  }
}

/// "Inspired by @x" — shown once the origin Ad is known (it may be
/// deleted, then nothing shows). One small cached lookup per origin.
class _InspiredByLine extends ConsumerWidget {
  const _InspiredByLine({required this.originAdId});

  final String originAdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Ad? origin = ref.watch(adByIdProvider(originAdId)).valueOrNull;
    if (origin == null || origin.creatorUsername == null) {
      return const SizedBox.shrink();
    }
    return _ChainLink(
      icon: Icons.subdirectory_arrow_right,
      text: AppLocalizations.of(context).adThisInspiredBy("@${origin.creatorUsername}"),
      onTap: () => unawaited(context.pushTo(RoutePaths.adDetailOf(originAdId))),
    );
  }
}

/// One tappable, shadowed line in the Ad overlay (48dp tall target).
class _ChainLink extends StatelessWidget {
  const _ChainLink({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  static const List<Shadow> _shadow = <Shadow>[Shadow(color: Colors.black87, blurRadius: 6)];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: AppColors.brandMint, shadows: _shadow),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, shadows: _shadow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
