import "dart:async" show unawaited;

import "package:flutter/foundation.dart" show ChangeNotifier, kDebugMode, debugPrint;

import "../../domain/video_project.dart";

/// The single authoritative "what time is it" for one editing session —
/// per the tightened editor spec's own architecture diagram:
///
/// ```
/// VideoProject
///      |
/// EditorController
///      |
/// EditorTransport
///      |
///      +---- Video Player
///      +---- Original Audio
///      +---- Music
///      +---- Timeline
///      +---- Text/Sticker evaluation
///      +---- Animation evaluation
///      +---- Speed evaluation
/// ```
///
/// [VideoProject] (owned by `EditorController`) stays the authoritative
/// *composition* — this class is the authoritative *clock*. No other
/// media component (video player, music player, timeline scroll,
/// overlay visibility, future animation progress) may keep its own
/// independent notion of "now"; every one of them either feeds this
/// clock (video playback position, when not scrubbing) or reads from it
/// (everything else). See `trim_step.dart`'s wiring of this class for
/// the concrete one-directional data flow that prevents the
/// video-position → programmatic-scroll → seek → video-position
/// feedback loop the spec explicitly warns about: only
/// [reportPlaybackPosition] ever writes *from* the player *into* this
/// clock, and only [requestSeek]/[endScrub] ever write *from* this
/// clock back *into* the player — never both directions from the same
/// event.
///
/// ## Project time vs. source video time
///
/// [currentTime] is **project time**: seconds since the trim window's
/// own start (`0` = [VideoProject.trimStart]), the exact same coordinate
/// space [SpeedZone.start]/[VideoOverlay.startSec]/
/// [BackgroundAudio.startSec] already use — not a new, third coordinate
/// system. The actual `VideoPlayerController` operates in **source
/// time** (`0` = the start of the original captured/imported file), so
/// the conversion at the player boundary is always:
///
/// ```
/// sourceTime = trimStart + projectTime
/// ```
///
/// This project-time axis does **not** account for speed-zone time
/// dilation (a 0.5x zone does not make [duration] longer) — it tracks
/// the *source* clip's own timeline, the same way the timeline UI's
/// filmstrip and zone/overlay chips already are positioned against the
/// original, untouched clip length. A speed zone changes how *fast*
/// [currentTime] advances during normal playback (via
/// [activeSpeedAt]-driven `setPlaybackSpeed`), not what [currentTime]
/// *means*.
final class EditorTransport extends ChangeNotifier {
  EditorTransport({
    required Duration duration,
    required Future<void> Function(Duration projectTime) onSeek,
  })  : _duration = duration,
        _onSeek = onSeek;

  Duration _duration;
  Duration get duration => _duration;

  /// Called when the trim window's own duration changes (dragging a trim
  /// handle) — [currentTime] is re-clamped to the new bound.
  void updateDuration(Duration newDuration) {
    _duration = newDuration;
    if (_currentTime > _duration) {
      _currentTime = _duration;
    }
    notifyListeners();
  }

  final Future<void> Function(Duration projectTime) _onSeek;

  Duration _currentTime = Duration.zero;
  Duration get currentTime => _currentTime;

  // videoeditor7.txt section 11: concise, rate-limited debug-only
  // telemetry — never compiled into a release build's hot path (guarded
  // by kDebugMode at every call site, not just here), so it costs
  // nothing once this round's physical-device behavior is confirmed.
  static void _log(String event) {
    if (kDebugMode) {
      debugPrint("[EditorTransport] $event");
    }
  }

  DateTime? _lastPositionLogAt;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// True from the moment a user's finger touches the timeline until
  /// they release it. While true, [reportPlaybackPosition] is ignored —
  /// the user's own requested position is authoritative, not whatever
  /// the player happens to be reporting mid-drag.
  bool _isScrubbing = false;
  bool get isScrubbing => _isScrubbing;

  /// True while a coalesced seek is actually awaiting the player. Also
  /// gates [reportPlaybackPosition] — a player's position callbacks
  /// during its own seek settling are not a new "true" position, they're
  /// the tail end of a seek this transport itself just requested.
  bool _seekInFlight = false;
  bool get isSeeking => _seekInFlight;

  void play() {
    if (_isPlaying) {
      return;
    }
    _isPlaying = true;
    _log("TRANSPORT_PLAY");
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) {
      return;
    }
    _isPlaying = false;
    _log("TRANSPORT_PAUSE");
    notifyListeners();
  }

  /// The player's own position, already converted to project time by
  /// the caller (`sourceTime - trimStart`). Silently ignored while
  /// [isScrubbing] or [isSeeking] — see class doc comment on feedback
  /// loop prevention.
  void reportPlaybackPosition(Duration projectTime) {
    if (_isScrubbing || _seekInFlight) {
      return;
    }
    final Duration clamped = _clamp(projectTime);
    if (clamped == _currentTime) {
      return;
    }
    _currentTime = clamped;
    // Rate-limited per section 11 ("do not log every frame forever") —
    // the native player reports position roughly every 100ms during
    // playback, far too often to log unconditionally.
    final DateTime now = DateTime.now();
    if (_lastPositionLogAt == null || now.difference(_lastPositionLogAt!) >= const Duration(seconds: 1)) {
      _lastPositionLogAt = now;
      _log("PLAYER_POSITION_REPORT t=$_currentTime");
    }
    notifyListeners();
  }

  void beginScrub() {
    _isScrubbing = true;
    _log("USER_SCRUB_BEGIN t=$_currentTime");
    notifyListeners();
  }

  Duration? _pendingSeek;

  /// Requests project time [projectTime]. The visible/logical
  /// [currentTime] (and therefore the timeline, overlay visibility,
  /// music mapping, everything downstream of this transport) updates
  /// **synchronously, immediately** — callers never wait for the actual
  /// decoder seek to move the UI. The expensive seek itself is
  /// coalesced: calling this rapidly only ever results in the player
  /// actually seeking to whichever position was most recent by the time
  /// any earlier seek finishes — an old seek's completion can never
  /// overwrite a newer request, since the drain loop always re-reads
  /// [_pendingSeek] (the latest) rather than trusting what it started
  /// with.
  void requestSeek(Duration projectTime) {
    final Duration clamped = _clamp(projectTime);
    if (clamped != _currentTime) {
      _currentTime = clamped;
      notifyListeners();
    }
    _log("VIDEO_SEEK_REQUEST target=$clamped");
    _pendingSeek = clamped;
    if (_seekInFlight) {
      return;
    }
    unawaited(_drainSeeks());
  }

  Future<void> _drainSeeks() async {
    _seekInFlight = true;
    try {
      while (_pendingSeek != null) {
        final Duration target = _pendingSeek!;
        _pendingSeek = null;
        _log("VIDEO_SEEK_BEGIN target=$target");
        await _onSeek(target);
        _log("VIDEO_SEEK_END target=$target");
        // If requestSeek() was called again while the line above was
        // awaited, _pendingSeek is non-null again and the loop repeats
        // for the newest position instead of stopping here — that's the
        // entire coalescing mechanism.
      }
    } finally {
      _seekInFlight = false;
    }
  }

  /// Ends a scrub gesture and performs one exact final synchronization
  /// at [finalTime] — matches the spec's explicit "on pointer release
  /// perform one exact final synchronization."
  void endScrub(Duration finalTime) {
    _isScrubbing = false;
    _log("USER_SCRUB_END t=$finalTime");
    requestSeek(finalTime);
  }

  Duration _clamp(Duration t) {
    if (t < Duration.zero) {
      return Duration.zero;
    }
    if (t > _duration) {
      return _duration;
    }
    return t;
  }

  // ---- Pure query functions: VideoProject + a project-time instant -> ----
  // ---- derived playback state. Static and side-effect-free on purpose —
  // ---- deterministic, unit-testable without a VideoPlayerController or
  // ---- any Flutter widget at all. ----

  /// The speed factor that should be in effect at project time [time] —
  /// `1.0` outside every zone.
  static double activeSpeedAt(List<SpeedZone> zones, Duration time) {
    for (final SpeedZone zone in zones) {
      if (time >= zone.start && time < zone.end) {
        return zone.factor;
      }
    }
    return 1.0;
  }

  /// Whether [overlay] should be visible at project time [time] — a pure
  /// half-open interval check, `[startSec, endSec)`, matching the
  /// spec's own explicit boundary examples (a 2.0–4.0s layer is visible
  /// at exactly 2.00 and invisible at exactly 4.00).
  static bool isOverlayVisibleAt(VideoOverlay overlay, Duration time) {
    return time >= overlay.startSec && time < overlay.endSec;
  }

  /// How far into [overlay]'s own local timeline [time] is — the basis
  /// for a future entrance animation's progress, always `>= 0` and
  /// always reproducible for a given (overlay, time) pair regardless of
  /// how playback got there (play, seek, scrub, replay) since it's a
  /// pure function of the two, not of wall-clock time or widget mount
  /// order.
  static Duration localLayerTimeAt(VideoOverlay overlay, Duration time) {
    final Duration local = time - overlay.startSec;
    return local.isNegative ? Duration.zero : local;
  }

  /// Where in the music *file itself* playback should be at project time
  /// [time] — `null` when [time] is outside the music's own
  /// `[startSec, startSec + duration)` window on the timeline, meaning
  /// the caller should pause/silence it. This app's [BackgroundAudio]
  /// always plays from its own file's beginning (no "start the file
  /// from N seconds in" offset is supported), so the general
  /// `sourceOffset + (currentTime - startTime)` mapping the spec
  /// describes simplifies to just `time - startSec` here — documented
  /// explicitly rather than silently dropping the general form.
  static Duration? musicLocalTimeAt(BackgroundAudio bg, Duration time, Duration trimmedDuration) {
    final Duration musicDuration = bg.duration ?? (trimmedDuration - bg.startSec);
    final Duration end = bg.startSec + musicDuration;
    if (time < bg.startSec || time >= end) {
      return null;
    }
    return time - bg.startSec;
  }

  /// Default resync threshold for [decideMusicSync] (videoeditor7.txt
  /// section 5: "start with something reasonable such as 100-150ms").
  /// Below this, drift is left alone rather than triggering a seek —
  /// "for small drift: DO NOTHING."
  static const Duration defaultDriftThreshold = Duration(milliseconds: 150);

  /// The music-sync POLICY (videoeditor7.txt section 5), as one pure,
  /// side-effect-free decision function — independently testable without
  /// a real `VideoPlayerController`. The caller (trim_step.dart's
  /// `_onTransportChanged`) is the only place that ever actually calls
  /// `music.seekTo`/`play`/`pause`; this function only says what should
  /// happen, never performs it. Splitting "what" from "how" is what
  /// makes the entry/drift/scrub rules in section 5 unit-testable at
  /// all, since the physical `VideoPlayerController` behavior itself can
  /// only be confirmed on a real device.
  ///
  /// The critical rule this enforces: a music-region **re-entry check**
  /// (`wasInRegion` false → seek once and start) is structurally
  /// distinct from an already-inside-the-region **drift check** (seek
  /// only if actual measured drift exceeds [driftThreshold]) — conflating
  /// the two (e.g. "seek+play whenever the player's own isPlaying flag
  /// happens to read false") is exactly the bug this round fixes: a
  /// transient buffering stall can make `VideoPlayerController.isPlaying`
  /// read false for a tick even though playback never really stopped,
  /// and treating that as "not started yet" reseeks+replays on every
  /// such tick — the free-running/stalling symptom videoeditor7.txt
  /// reported. `wasInRegion` is state the CALLER owns and updates only
  /// once per genuine entry/exit — never derived from the player's own
  /// possibly-flickering `isPlaying` value.
  static MusicSyncDecision decideMusicSync({
    required BackgroundAudio? bg,
    required Duration currentTime,
    required Duration trimmedDuration,
    required bool isPlaying,
    required bool isScrubbing,
    required bool wasInRegion,
    required Duration musicPlayerPosition,
    Duration driftThreshold = defaultDriftThreshold,
  }) {
    // Section: "USER SCRUB — PAUSE music during active scrub... do NOT
    // hammer the audio player with seek calls" for every intermediate
    // pointer movement. No seek target at all while actively scrubbing —
    // the eventual scrub-end tick (isScrubbing already false by then)
    // naturally produces one corrective seek via the drift/re-entry
    // check below, since the caller resets wasInRegion to false the
    // moment a scrub begins (see trim_step.dart).
    if (isScrubbing || bg == null) {
      return const MusicSyncDecision(playback: MusicPlaybackIntent.paused);
    }
    final Duration? local = musicLocalTimeAt(bg, currentTime, trimmedDuration);
    if (local == null) {
      return const MusicSyncDecision(playback: MusicPlaybackIntent.paused);
    }
    final Duration drift = (musicPlayerPosition - local).abs();
    final bool needsSeek = !wasInRegion || drift > driftThreshold;
    return MusicSyncDecision(
      playback: isPlaying ? MusicPlaybackIntent.playing : MusicPlaybackIntent.paused,
      seekTarget: needsSeek ? local : null,
    );
  }
}

/// What [EditorTransport.decideMusicSync] wants the music player's
/// play/pause state to be.
enum MusicPlaybackIntent { paused, playing }

/// The result of [EditorTransport.decideMusicSync] — what the wiring
/// layer should do to the real music player this tick. [seekTarget] is
/// non-null only when a seek is actually warranted (a fresh region
/// entry, a scrub-end correction, or drift beyond the threshold) — most
/// ticks during steady in-sync playback produce a `null` target, meaning
/// "do nothing but ensure play/pause matches [playback]."
final class MusicSyncDecision {
  const MusicSyncDecision({required this.playback, this.seekTarget});

  final MusicPlaybackIntent playback;
  final Duration? seekTarget;

  @override
  bool operator ==(Object other) =>
      other is MusicSyncDecision && other.playback == playback && other.seekTarget == seekTarget;

  @override
  int get hashCode => Object.hash(playback, seekTarget);

  @override
  String toString() => "MusicSyncDecision(playback: $playback, seekTarget: $seekTarget)";
}
