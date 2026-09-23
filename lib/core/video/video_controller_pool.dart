import "dart:async" show unawaited;

import "package:video_player/video_player.dart";

import "../utils/app_logger.dart";

/// Bounded pool of [VideoPlayerController]s keyed by Ad id (CLAUDE.md
/// section 17/41: "avoid creating an unlimited number of active video
/// controllers").
///
/// Usage from the feed: call [controllerFor] for the currently-visible
/// index and the next one or two indices (preload), then call [evictAllExcept]
/// with that same "keep" set once the visible index changes, so
/// controllers for Ads scrolled far away get disposed promptly instead of
/// accumulating for the life of the feed session.
final class VideoControllerPool {
  VideoControllerPool({this.maxSize = 4});

  /// Current + preloaded neighbors, with a little headroom. Not "dozens of
  /// full videos" (section 17) — just enough that scrolling one step in
  /// either direction never blocks on a fresh network initialization.
  final int maxSize;

  final Map<String, VideoPlayerController> _controllers = <String, VideoPlayerController>{};
  final Map<String, Future<void>> _initFutures = <String, Future<void>>{};
  final _log = AppLogger.named("VideoControllerPool");

  /// Returns an existing controller for [adId]/[playbackUrl] or creates and
  /// starts initializing one. Safe to call repeatedly (e.g. on every
  /// build) — it will not re-create an already-live controller.
  VideoPlayerController controllerFor({required String adId, required String playbackUrl}) {
    final VideoPlayerController? existing = _controllers[adId];
    if (existing != null) {
      return existing;
    }

    final VideoPlayerController controller = VideoPlayerController.networkUrl(Uri.parse(playbackUrl));
    _controllers[adId] = controller;
    _initFutures[adId] = controller.initialize().catchError((Object e, StackTrace st) {
      _log.warning("Failed to initialize controller for ad $adId", e, st);
    });

    // Safety net in case a caller forgets to call evictAllExcept promptly:
    // never hold more than maxSize controllers regardless. _controllers is
    // insertion-ordered, so this evicts the longest-held entries first —
    // callers should still call evictAllExcept for precise control over
    // *which* ids survive (e.g. always keeping the currently-visible one).
    while (_controllers.length > maxSize) {
      _disposeOne(_controllers.keys.first);
    }

    return controller;
  }

  Future<void>? initializationOf(String adId) => _initFutures[adId];

  /// Disposes and removes every controller whose Ad id is not in [keepIds].
  /// Call this after each page-change settles so the pool never exceeds
  /// [maxSize] active controllers for long.
  void evictAllExcept(Set<String> keepIds) {
    final List<String> toRemove =
        _controllers.keys.where((String id) => !keepIds.contains(id)).toList(growable: false);
    for (final String id in toRemove) {
      _disposeOne(id);
    }
  }

  /// Pauses every controller except [adId] — used when the feed page
  /// changes, so only the currently-visible Ad is ever producing audio
  /// (section 17: "Respect mute/audio state" implies exactly one playing
  /// controller at a time).
  void pauseAllExcept(String adId) {
    for (final MapEntry<String, VideoPlayerController> entry in _controllers.entries) {
      if (entry.key != adId && entry.value.value.isPlaying) {
        unawaited(entry.value.pause());
      }
    }
  }

  /// Pauses every controller — call on app background / route change away
  /// from the feed (section 17).
  void pauseAll() {
    for (final VideoPlayerController controller in _controllers.values) {
      if (controller.value.isPlaying) {
        unawaited(controller.pause());
      }
    }
  }

  /// Resumes [adId]'s controller if it's still held and initialized — call
  /// when the screen holding this pool becomes visible again (e.g. the
  /// feed's bottom-nav tab regains focus after [pauseAll] paused it).
  void resume(String adId) {
    final VideoPlayerController? controller = _controllers[adId];
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.play());
    }
  }

  void _disposeOne(String adId) {
    final VideoPlayerController? controller = _controllers.remove(adId);
    _initFutures.remove(adId);
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  void disposeAll() {
    for (final String id in _controllers.keys.toList(growable: false)) {
      _disposeOne(id);
    }
  }
}
