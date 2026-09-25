import "dart:async" show StreamSubscription, Timer, unawaited;
import "dart:io";
import "dart:math" show max, pi;

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:image_picker/image_picker.dart";
import "package:uuid/uuid.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/router/app_shell.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/media/video_editor_service.dart";
import "../../../../core/media/video_export_service.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/utils/app_logger.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../../domain/video_project.dart";
import "../providers/create_ad_flow_controller.dart";
import "../providers/editor_controller.dart";
import "editor_transport.dart";
import "timeline_geometry.dart";

/// The creation flow's one editing step (CLAUDE.md section 4/38): trim,
/// rotate, flip, mute, a color filter, background music, slow-motion
/// zones, and timed text/sticker overlays, all on a single screen with a
/// timeline. Not split into a separate "basic" vs. "advanced" screen — a
/// slow-motion zone is just another tool next to rotate, not a different
/// product.
///
/// Two render paths, picked automatically at "Continue", not exposed to
/// the user as a choice: a plain trim/rotate/flip/mute edit (no zones, no
/// overlays) goes through the fast `easy_video_editor` pipeline
/// ([VideoEditorService]); the moment a speed zone or overlay is added,
/// everything (including trim/rotate/flip/mute) renders in one pass
/// through the FFmpeg pipeline ([VideoExportService]) instead, so the
/// user never sees "export" as a separate concept from "continue" — it's
/// just what continuing costs when the edit needs it.
class TrimStep extends ConsumerStatefulWidget {
  const TrimStep({super.key});

  @override
  ConsumerState<TrimStep> createState() => _TrimStepState();
}

class _TrimStepState extends ConsumerState<TrimStep> {
  static const Uuid _uuid = Uuid();

  VideoPlayerController? _controller;

  // The ONE authoritative clock for this editing session (videoeditor6.txt
  // section 1) — every media component (video player, music, timeline,
  // overlay visibility) either feeds it (via _reportPlayerPosition) or
  // reads from it (via _onTransportChanged and the transport-driven
  // widgets below), never both directions for the same event. See
  // editor_transport.dart's own class doc for the full architecture.
  EditorTransport? _transport;

  // videoeditor9.txt: a TEMPORARY, debug-only hard-isolation A/B test.
  // When true, none of the fields/methods above are constructed or
  // touched at all — not even the widgets/callbacks that would read
  // them — and this screen instead renders a second, completely
  // independent VideoPlayerController with the EXACT SAME minimal
  // architecture as caption_publish_step.dart: file -> initialize ->
  // setLooping -> play -> bare AspectRatio(VideoPlayer). No
  // EditorTransport is constructed, so no player-position listener, no
  // transport listener, no timeline, no music/speed/overlay
  // coordination of any kind can run — not gated off, simply never
  // built. See _enterRawPreviewMode/_exitRawPreviewMode/_buildRawPreview.
  bool _rawPreviewMode = false;
  VideoPlayerController? _rawController;

  // The trim window's *end* the first time this screen loads a clip —
  // needed by both EditorController.init() and Reset (which restores
  // this exact untouched window, not an empty/zero one).
  Duration _initialTrimEnd = Duration.zero;

  bool _processing = false;
  double _progress = 0;
  StreamSubscription<double>? _progressSub;
  String? _error;

  // Live-preview-only state (never exported — the real render always goes
  // through VideoFilterGraphBuilder/FfmpegVideoExportService). A second
  // VideoPlayerController plays the picked music file in sync with the
  // main preview rather than adding a dedicated audio-player dependency —
  // video_player's native ExoPlayer/AVPlayer backing plays audio-only
  // files fine, and this project's history this session (file_picker,
  // share_plus, ffmpeg_kit) is full of new-native-dependency Kotlin/AGP
  // conflicts worth avoiding when an already-vetted package can do it.
  VideoPlayerController? _musicController;
  // Initialized to the native player's own real defaults (volume=1.0,
  // playbackSpeed=1.0 — see VideoPlayerValue's own defaults), not null,
  // so a freshly-loaded zero-edit clip never issues an "establish
  // baseline" setVolume(1)/setPlaybackSpeed(1.0) call on its first tick
  // — there is genuinely nothing to change yet (videoeditor8.txt
  // section 10: "VIDEO speed changes = 0 / VIDEO mute changes = 0"
  // during zero-edit playback).
  double _lastAppliedPreviewSpeed = 1.0;
  bool _lastAppliedMute = false;

  // The user-reported "play/pause çıkışında 100-200ms geriden başlıyor,
  // bu sürekli tekrarlanıyor olabilir mi" bug: `_onTransportChanged`'s
  // video play/pause branch used to compare against
  // `controller.value.isPlaying`, the SAME kind of value that can
  // transiently flicker to `false` during a native buffering micro-
  // stall (exactly the mechanism already fixed for music below). A
  // stall the player would have recovered from on its own instead got
  // read as "stopped, needs a fresh play() command" — and every such
  // command pays the same real native play()-restart latency the user
  // was seeing, turning a brief, self-resolving stall into a repeating
  // stutter. This tracks the play/pause state WE ourselves last told
  // the controller to be in, never what it happens to report back, so
  // a transient stall is left alone to resolve on its own.
  bool _lastAppliedIsPlaying = false;

  // Same fix, applied to the music controller (its "no seek needed,
  // just make sure it's playing" branch had the identical flicker
  // vulnerability against `music.value.isPlaying`). Nullable — reset to
  // null on a music-source change so the very next tick re-establishes
  // it rather than trusting a stale value from a different file.
  bool? _lastAppliedMusicPlaying;

  // videoeditor7.txt section 5/6: whether the music player is currently
  // considered "inside" its region by the last tick this widget itself
  // processed — owned here, never derived from `music.value.isPlaying`
  // (which can transiently read false during a native buffering stall,
  // the exact conflation that caused repeated seek+play cycles/"free
  // running" before this round). Reset to false on any scrub begin, a
  // music-source change, or leaving the editor, so the next relevant
  // tick is always treated as a fresh entry needing exactly one seek.
  bool _musicInRegion = false;

  // Latest-wins coalescing for music seeks — the EXACT same pattern
  // EditorTransport._drainSeeks already uses for the video controller
  // (only one seek ever in flight; a newer request while one is
  // pending just updates the pending target, the loop drains to the
  // latest instead of firing concurrent seeks). Replaced an earlier
  // per-dispatch generation-token approach after a real bug: bumping a
  // generation counter on EVERY seek dispatch meant a rapid sequence of
  // drift-correction seeks kept invalidating each other before any
  // single one could ever reach its own play() call afterward — music
  // got seeked repeatedly but never actually played, confirmed live via
  // the on-screen debug overlay (mSeek=42, mPlay=0, errors=0, during a
  // session where music never once produced audible playback). See
  // _requestMusicSeek/_drainMusicSeeks.
  Duration? _pendingMusicSeek;
  bool _musicSeekInFlight = false;
  bool _pendingMusicPlayAfter = false;
  // See _requestMusicSeek's own doc comment: distinguishes an ordinary
  // per-tick drift correction (seek only, no forced play() — the player
  // is presumed already playing) from a confirmed-stall recovery (seek
  // AND force a fresh play(), since the player has genuinely stopped).
  bool _pendingMusicForcePlay = false;

  final _log = AppLogger.named("TrimStepPlayback");

  // videoeditor8.txt section 10: debug-only counters, summarized every
  // 10s while a clip is loaded (see _startDebugInstrumentation). During
  // zero-edit playback, seek/play/pause/speed/mute should all read 0
  // after the initial play — these exist to make that a directly
  // observable fact during physical-device testing, not a claim.
  int _dbgSeekCount = 0;
  int _dbgPlayCount = 0;
  int _dbgPauseCount = 0;
  int _dbgSpeedChangeCount = 0;
  int _dbgMuteChangeCount = 0;
  int _dbgTimelineUpdateCount = 0;
  int _dbgEditorRebuildCount = 0;
  // Added this round: a still-unresolved "music never resumes after a
  // scrub / timeline appears to stop" report needs to see whether
  // music commands are even being attempted, and whether
  // _onTransportChanged is throwing (see its own try/catch).
  int _dbgMusicSeekCount = 0;
  int _dbgMusicPlayCount = 0;
  int _dbgMusicPauseCount = 0;
  int _dbgErrorCount = 0;
  String? _dbgLastError;
  Timer? _dbgReportTimer;

  // A rolling history (not just the current instant) of every music
  // play/pause transition, each with the exact positions at that
  // moment — added because catching the precise instant music cuts out
  // in a single manually-timed screenshot is genuinely hard (a real,
  // fair complaint). Whatever caused the last cutout is now always
  // visible on screen afterward, no perfect timing required.
  final List<String> _dbgMusicEvents = <String>[];

  void _logMusicEvent(String event) {
    if (!kDebugMode) {
      return;
    }
    final Duration? t = _transport?.currentTime;
    final Duration? mPos = _musicController?.value.position;
    _dbgMusicEvents.add("$event t=${t?.inMilliseconds} mPos=${mPos?.inMilliseconds}");
    if (_dbgMusicEvents.length > 6) {
      _dbgMusicEvents.removeAt(0);
    }
  }

  void _startDebugInstrumentation() {
    if (!kDebugMode) {
      return;
    }
    _dbgReportTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _log.info(
        "10s window: seekTo=$_dbgSeekCount play=$_dbgPlayCount pause=$_dbgPauseCount "
        "speedChanges=$_dbgSpeedChangeCount muteChanges=$_dbgMuteChangeCount "
        "timelineUpdates=$_dbgTimelineUpdateCount editorRebuilds=$_dbgEditorRebuildCount "
        "musicSeek=$_dbgMusicSeekCount musicPlay=$_dbgMusicPlayCount musicPause=$_dbgMusicPauseCount "
        "errors=$_dbgErrorCount",
      );
      _dbgSeekCount = 0;
      _dbgPlayCount = 0;
      _dbgPauseCount = 0;
      _dbgSpeedChangeCount = 0;
      _dbgMuteChangeCount = 0;
      _dbgTimelineUpdateCount = 0;
      _dbgEditorRebuildCount = 0;
      _dbgMusicSeekCount = 0;
      _dbgMusicPlayCount = 0;
      _dbgMusicPauseCount = 0;
      // _dbgErrorCount/_dbgLastError deliberately NOT reset — an error
      // should stay visible on screen until the next one replaces it,
      // not silently disappear after 10s.
    });
  }

  Timer? _playbackWatchdog;
  Duration? _watchdogLastVideoPos;
  Duration? _watchdogLastMusicPos;

  // Escalation counter: a confirmed user report says music going silent
  // is PERMANENT (never recovers on its own, video keeps going fine) —
  // meaning the cheap seekTo()+play() resync below isn't enough on its
  // own; the decoder itself has likely entered a genuinely broken state
  // a fresh seek/play command can't revive. After a few consecutive
  // 800ms cycles of confirmed non-advancement (not just one), escalate
  // to fully disposing and recreating the music controller from the
  // same file — see _rebuildMusicController.
  int _musicWatchdogFailStreak = 0;
  bool _musicRebuildInProgress = false;

  /// Recovers from a GENUINE (sustained) playback freeze — but, per two
  /// FURTHER user screenshots after the first version of this watchdog
  /// shipped, `VideoPlayerController.value.isPlaying` itself turned out
  /// to be an unreliable signal on the reporting device: it read `false`
  /// for many consecutive seconds while `vPos` kept advancing completely
  /// normally in lockstep with `mPos` — i.e. the flag was simply wrong,
  /// not the video actually frozen. Trusting that flag (this watchdog's
  /// first version) meant firing needless retry `play()` calls against
  /// an already-healthy player, which could itself have been
  /// contributing interference rather than helping.
  ///
  /// Freeze detection is now POSITION-based instead: compare the
  /// controller's own position against what it was on the PREVIOUS
  /// watchdog tick (800ms ago) — if it genuinely has not moved at all
  /// while this screen wants it playing, that's real, direct evidence
  /// of a stall, independent of whatever the `isPlaying` flag claims.
  ///
  /// Why this can't live inside `_onTransportChanged`: that method only
  /// runs in reaction to `_transport` notifying, which itself only
  /// happens when `_reportPlayerPosition` sees the *video's* position
  /// actually change. If the video controller genuinely stops
  /// advancing, position reports stop entirely, so `_onTransportChanged`
  /// would never run again to notice or retry. This watchdog is
  /// intentionally independent of `_transport`'s own notification
  /// stream (same reasoning as `_DebugOverlay`'s own timer) and runs on
  /// a deliberately slow cadence (800ms, not every ~100ms tick) so it
  /// corrects a SUSTAINED stall without reintroducing the original
  /// play()-restart-latency stutter a single transient flicker would
  /// cause if retried immediately.
  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _watchdogLastVideoPos = null;
    _watchdogLastMusicPos = null;
    _musicWatchdogFailStreak = 0;
    _playbackWatchdog = Timer.periodic(const Duration(milliseconds: 800), (_) {
      final EditorTransport? transport = _transport;
      final VideoPlayerController? controller = _controller;
      if (transport == null || controller == null || !controller.value.isInitialized) {
        return;
      }

      final Duration videoPos = controller.value.position;
      final bool videoFrozen =
          transport.isPlaying && _watchdogLastVideoPos != null && videoPos == _watchdogLastVideoPos;
      _watchdogLastVideoPos = videoPos;
      if (videoFrozen) {
        if (kDebugMode) {
          _log.warning(
            "VIDEO_WATCHDOG: position hasn't advanced in 800ms while transport wants playing — retrying play()",
          );
        }
        unawaited(controller.play());
      }

      final VideoPlayerController? music = _musicController;
      final VideoProject? project = ref.read(editorControllerProvider);
      final BackgroundAudio? bg = project?.bgAudio;
      if (music == null || !music.value.isInitialized || project == null || bg == null) {
        _watchdogLastMusicPos = null;
        return;
      }
      // Recompute the decision fresh (not just "call play() blindly") so
      // a recovery after a sustained stall lands on the mathematically
      // correct position, not wherever it happened to be stuck.
      final MusicSyncDecision decision = EditorTransport.decideMusicSync(
        bg: bg,
        currentTime: transport.currentTime,
        trimmedDuration: project.trimmedDuration,
        isPlaying: transport.isPlaying,
        isScrubbing: transport.isScrubbing,
        wasInRegion: _musicInRegion,
        musicPlayerPosition: music.value.position,
      );
      final Duration musicPos = music.value.position;
      final bool musicFrozen = decision.playback == MusicPlaybackIntent.playing &&
          _watchdogLastMusicPos != null &&
          musicPos == _watchdogLastMusicPos;
      _watchdogLastMusicPos = musicPos;
      if (musicFrozen) {
        _musicWatchdogFailStreak++;
        if (_musicWatchdogFailStreak >= 3) {
          // Three consecutive 800ms cycles (~2.4s) of confirmed zero
          // movement despite repeated seekTo()+play() resync attempts —
          // per the user's own confirmation this freeze is PERMANENT,
          // not something a cheap resync recovers from. Escalate to a
          // full controller rebuild instead of trying the same thing a
          // fourth time.
          _musicWatchdogFailStreak = 0;
          unawaited(_rebuildMusicController(bg));
        } else {
          if (kDebugMode) {
            _log.warning(
              "MUSIC_WATCHDOG: position hasn't advanced in 800ms while it should be playing — resyncing "
              "(attempt $_musicWatchdogFailStreak/3 before rebuild)",
            );
            _logMusicEvent("WATCHDOG_FROZEN_$_musicWatchdogFailStreak");
          }
          _requestMusicSeek(
            EditorTransport.musicLocalTimeAt(bg, transport.currentTime, project.trimmedDuration) ?? Duration.zero,
            playAfter: true,
            // Confirmed stall (position frozen across an 800ms watchdog
            // tick, not just ordinary drift) — bypass the cache so a
            // genuinely stopped player actually gets a fresh play().
            forcePlay: true,
          );
        }
      } else {
        _musicWatchdogFailStreak = 0;
      }
    });
  }

  /// Last-resort recovery when repeated seekTo()+play() resync attempts
  /// don't revive a genuinely stuck music decoder: dispose it entirely
  /// and build a fresh `VideoPlayerController` from the same file,
  /// matching how it was first attached in `_setBgAudio`. Guarded
  /// against overlapping calls (`_musicRebuildInProgress`) since the
  /// watchdog could otherwise fire again mid-rebuild.
  Future<void> _rebuildMusicController(BackgroundAudio bg) async {
    if (_musicRebuildInProgress || !mounted) {
      return;
    }
    _musicRebuildInProgress = true;
    if (kDebugMode) {
      _log.warning("MUSIC_WATCHDOG: sustained freeze survived resync attempts — rebuilding controller from scratch");
      _logMusicEvent("REBUILD");
    }
    final VideoPlayerController? old = _musicController;
    _musicController = null;
    _pendingMusicSeek = null;
    _watchdogLastMusicPos = null;
    try {
      await old?.pause();
    } catch (_) {
      // Best-effort teardown of a controller already in a broken state.
    }
    try {
      await old?.dispose();
    } catch (_) {
      // Same as above.
    }
    try {
      final VideoPlayerController fresh = VideoPlayerController.file(File(bg.filePath));
      await fresh.initialize();
      await fresh.setVolume(bg.volume);
      if (mounted) {
        setState(() => _musicController = fresh);
        _lastAppliedMusicPlaying = null;
        _musicInRegion = false;
        _onTransportChanged();
      } else {
        await fresh.dispose();
      }
    } catch (e) {
      if (kDebugMode) {
        _log.severe("MUSIC_WATCHDOG: rebuild itself failed", e);
        _logMusicEvent("REBUILD_FAILED");
      }
    } finally {
      _musicRebuildInProgress = false;
    }
  }

  /// Tears down EVERY normal-mode playback resource (not gated/early-
  /// returned — actually disposed and un-listened) and constructs a
  /// second `VideoPlayerController` whose only operations, anywhere in
  /// this codebase, are `initialize()`, `setLooping(true)`, `play()`,
  /// and disposal — the identical set `caption_publish_step.dart` uses.
  /// No `EditorTransport` is created, so [_reportPlayerPosition] and
  /// [_onTransportChanged] are never registered as listeners on it
  /// (they still exist as methods, but nothing ever calls
  /// `addListener` linking them to this controller); [_Timeline] is not
  /// built at all while this mode is active, so it cannot call
  /// `jumpTo` regardless of what this controller does.
  Future<void> _enterRawPreviewMode() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    _dbgReportTimer?.cancel();
    _playbackWatchdog?.cancel();
    _controller?.removeListener(_reportPlayerPosition);
    _controller?.dispose().ignore();
    _controller = null;
    _transport?.removeListener(_onTransportChanged);
    _transport?.dispose();
    _transport = null;
    _pendingMusicSeek = null; // the drain loop (if any) exits on its own via the controller-identity check
    _musicController?.dispose().ignore();
    _musicController = null;

    final VideoPlayerController raw = VideoPlayerController.file(File(draft.filePath));
    _rawController = raw;
    setState(() => _rawPreviewMode = true);

    await raw.initialize();
    if (!mounted || !_rawPreviewMode || _rawController != raw) {
      return;
    }
    setState(() {});
    // Exactly caption_publish_step.dart's own sequence — nothing else.
    unawaited(raw.setLooping(true));
    unawaited(raw.play());
    if (kDebugMode) {
      _log.info(
        "RAW_PREVIEW_MODE entered: controller initialized and playing. "
        "EditorTransport=NOT CONSTRUCTED, _reportPlayerPosition listener=NOT REGISTERED, "
        "_onTransportChanged listener=NOT REGISTERED, _Timeline=NOT BUILT. "
        "Therefore, by construction (not runtime sampling — ChangeNotifier's own "
        "listener count isn't part of Flutter's public API): "
        "EditorTransport reports=0, timeline playback updates=0, jumpTo calls=0, "
        "video seekTo calls=0 (only initialize+play were called), speed calls=0, "
        "music sync calls=0. The only listener(s) on this controller are whatever "
        "the VideoPlayer widget itself attaches internally — identical to "
        "caption_publish_step.dart, which this screen's own code never touches.",
      );
    }
  }

  /// Disposes the raw controller and rebuilds the normal editor pipeline
  /// from scratch (composition state in [VideoProject]/Riverpod is
  /// untouched — only this screen's own player/transport/timeline
  /// widget state is rebuilt).
  void _exitRawPreviewMode() {
    _rawController?.dispose().ignore();
    _rawController = null;
    setState(() => _rawPreviewMode = false);
    _startInitialization();
  }

  /// videoeditor10.txt's standalone-route experiment: uses
  /// `pushReplacement`, not `push`, specifically so `CreateAdScreen`
  /// (and therefore this `TrimStep`, its `EditorTransport`, and its
  /// thumbnail-service reference) is actually disposed before
  /// `TemporaryRawPlayerRoute` is built — a `push` would only cover this
  /// screen, leaving it alive underneath, which would not test the
  /// lifecycle-isolation question at all.
  void _openStandaloneRawPlayerRoute() {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    unawaited(GoRouter.of(context).pushReplacement(RoutePaths.debugRawPlayer, extra: draft.filePath));
  }

  Widget _buildRawPreview() {
    final VideoPlayerController? raw = _rawController;
    final bool rawReady = raw != null && raw.value.isInitialized;
    return Scaffold(
      appBar: AppBar(
        title: const Text("RAW PREVIEW MODE (debug)"),
        actions: <Widget>[
          TextButton(onPressed: _exitRawPreviewMode, child: const Text("Exit raw mode")),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: rawReady
              ? AspectRatio(aspectRatio: raw.value.aspectRatio, child: VideoPlayer(raw))
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }

  // Real decoded frames for the timeline's Clip lane (not a placeholder
  // bar — see the video-editor spec this round implements). Generated
  // once against the *original* captured file, independent of trim/edits,
  // since the filmstrip represents the whole source clip the same way
  // the base track already does. Empty until generation finishes, and
  // stays empty (falling back to the plain lane background) if it fails
  // — a missing filmstrip should never block editing.
  List<String> _thumbnailPaths = <String>[];

  bool _showFilterStrip = false;

  // BUG 3 fix: controller.initialize() previously had no timeout and no
  // error handling at all — if it hung (real-device report: "recorded
  // ~10 seconds, editor remained on a loading spinner indefinitely, had
  // to close it") or threw, `ready` just stayed false forever with no
  // way out except leaving the screen. Every async stage here now has
  // an explicit outcome: success, a bounded timeout, or a caught error
  // — never silence.
  String? _initError;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    // Retrying after a failed/timed-out init (via the "Try again"
    // button) must not leak the controller (or transport/its listener)
    // from the attempt that just failed.
    _controller?.removeListener(_reportPlayerPosition);
    _controller?.dispose().ignore();
    _transport?.removeListener(_onTransportChanged);
    _transport?.dispose();
    _dbgReportTimer?.cancel();
    _playbackWatchdog?.cancel();
    _lastAppliedMute = false;
    _lastAppliedPreviewSpeed = 1.0;
    _lastAppliedIsPlaying = false;
    setState(() {
      _initError = null;
      _controller = null;
      _transport = null;
    });
    final VideoPlayerController controller = VideoPlayerController.file(File(draft.filePath));
    _controller = controller;
    unawaited(_initializeController(controller, draft));
  }

  Future<void> _initializeController(VideoPlayerController controller, LocalVideoDraft draft) async {
    try {
      // 12s is generous for a <=10s-source clip on a mid-range phone —
      // long enough that a legitimately slow device isn't cut off
      // mid-init, short enough that "indefinitely" never happens again.
      await controller.initialize().timeout(const Duration(seconds: 12));
    } catch (e) {
      if (mounted) {
        setState(() => _initError = "Couldn't open this video: $e");
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final Duration total = controller.value.duration;
    _initialTrimEnd = total > VideoConstraints.max ? VideoConstraints.max : total;
    // VideoProject becomes the single source of truth from this point
    // on — the preview below reads it directly, not a parallel copy of
    // these fields kept in widget state.
    ref.read(editorControllerProvider.notifier).init(
          VideoProject(videoPath: draft.filePath, trimStart: Duration.zero, trimEnd: _initialTrimEnd),
        );

    // EditorTransport.currentTime is project time (0 = trimStart) — the
    // player itself operates in source time, so onSeek converts at this
    // one boundary (sourceTime = trimStart + projectTime), reading
    // trimStart fresh on every call since a trim-edge drag can change it
    // between requests.
    final EditorTransport transport = EditorTransport(
      duration: _initialTrimEnd,
      onSeek: (Duration projectTime) async {
        final Duration trimStart = ref.read(editorControllerProvider)?.trimStart ?? Duration.zero;
        if (kDebugMode) _dbgSeekCount++;
        await controller.seekTo(trimStart + projectTime);
      },
    );
    _transport = transport;
    transport.addListener(_onTransportChanged);
    _startDebugInstrumentation();
    _startPlaybackWatchdog();

    setState(() {});
    unawaited(controller.setLooping(true));
    // Player position -> transport only (never the reverse from this
    // listener) — see _reportPlayerPosition's own doc comment.
    controller.addListener(_reportPlayerPosition);
    // Routed through the transport, not controller.play() directly, so
    // isPlaying has exactly one owner from the very first frame.
    transport.play();
    // videoeditor11.txt's isolation test is resolved: thumbnail
    // generation was never the cause (the actual bug — an ungated
    // ScrollEndNotification double-seeking on every timeline
    // auto-follow jump — is fixed). Restored.
    unawaited(_generateThumbnails(draft));
  }

  Future<void> _generateThumbnails(LocalVideoDraft draft) async {
    final List<String> paths = await ref.read(videoThumbnailServiceProvider).generateThumbnails(
          videoPath: draft.filePath,
          duration: draft.duration,
          count: 10,
        );
    if (mounted && paths.isNotEmpty) {
      setState(() => _thumbnailPaths = paths);
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _dbgReportTimer?.cancel();
    _playbackWatchdog?.cancel();
    _rawController?.dispose().ignore();
    _controller?.removeListener(_reportPlayerPosition);
    _controller?.dispose().ignore();
    _transport?.removeListener(_onTransportChanged);
    _transport?.dispose();
    _pendingMusicSeek = null;
    _musicController?.dispose().ignore();
    // Stops an in-flight thumbnail generation and deletes whatever it
    // had already written — leaving the editor before generation
    // finishes shouldn't leak temp JPEGs for the rest of the session.
    unawaited(ref.read(videoThumbnailServiceProvider).cancel());
    // Whatever happens next (successful Continue, Retake, or the shell
    // itself navigating away after confirmation) means there's nothing
    // left on *this* screen to warn about losing.
    ref.read(hasUnsavedCreateEditsProvider.notifier).state = false;
    super.dispose();
  }

  /// The ONLY place the player's own position ever writes into the
  /// transport (videoeditor6.txt section 5). Pure report, never a seek —
  /// [EditorTransport.reportPlaybackPosition] itself silently ignores
  /// this while the transport is scrubbing or has a seek in flight, so
  /// this listener never needs to know which state the transport is in;
  /// it just always reports, and the transport decides whether that's
  /// trustworthy right now. This one-directional flow (player -> report
  /// -> transport, and separately transport -> requestSeek -> player,
  /// never both for the same event) is what prevents the
  /// position-drives-scroll-drives-seek-drives-position loop the spec
  /// explicitly warns about.
  void _reportPlayerPosition() {
    final VideoPlayerController? controller = _controller;
    final EditorTransport? transport = _transport;
    final VideoProject? project = ref.read(editorControllerProvider);
    if (controller == null || transport == null || project == null || !controller.value.isInitialized) {
      return;
    }
    final Duration projectTime = controller.value.position - project.trimStart;
    transport.reportPlaybackPosition(projectTime.isNegative ? Duration.zero : projectTime);
  }

  /// The other direction: everything the transport's clock implies gets
  /// applied back onto the real media components here — play/pause
  /// state, mute (BUG 11's fix, now re-asserted from one single
  /// mechanism instead of scattered toggle handlers, per spec section 7
  /// "undo/redo/reset must correctly update preview volume"), the active
  /// speed zone (BUG 7-adjacent: preview must reflect speed the same way
  /// export does), and background music position (spec section 6's exact
  /// mapping, via [EditorTransport.musicLocalTimeAt]). Registered as a
  /// listener on `_transport` itself, so it runs on every clock change
  /// (play, pause, a reported position, a requested seek) — never driven
  /// by a separate/unrelated timer.
  ///
  /// `setPlaybackSpeed`'s pitch-shift (vs. export's pitch-correct FFmpeg
  /// `atempo`) remains a known preview-only approximation, same as this
  /// screen's existing `ColorFilter.matrix`-vs-FFmpeg-`eq`/`hue` preview
  /// approximation for color filters.
  void _onTransportChanged() {
    final EditorTransport? transport = _transport;
    final VideoPlayerController? controller = _controller;
    final VideoProject? project = ref.read(editorControllerProvider);
    if (transport == null || controller == null || !controller.value.isInitialized || project == null) {
      return;
    }
    // Diagnostic wrap, per a persisting user report ("timeline duruyor"/
    // music never resuming after a scrub) that survived the duration-
    // clamp fix: an uncaught exception anywhere below would silently
    // abort THIS notifyListeners() round for every listener registered
    // AFTER this one on the same ChangeNotifier — including
    // _Timeline's own _onTransportPositionChanged (its auto-follow),
    // which would look exactly like "the timeline stops" while the
    // native video/music players keep running underneath, unaffected
    // (Dart-side exception, not a platform one). Caught, logged, and
    // surfaced on the on-screen debug overlay instead of guessed at —
    // the same evidence-first approach that found the real seek-loop
    // bug earlier in this diagnosis chain.
    try {

    // Gated on transport.isPlaying CHANGING from what we last told the
    // controller — not on comparing against controller.value.isPlaying
    // (see _lastAppliedIsPlaying's own doc comment). A transient native
    // buffering stall that makes the player briefly report isPlaying as
    // false does NOT get a fresh play() command here; the player
    // recovers on its own once buffered, since playWhenReady is already
    // true from the first (and only, per this gate) play() call.
    if (transport.isPlaying != _lastAppliedIsPlaying) {
      _lastAppliedIsPlaying = transport.isPlaying;
      if (transport.isPlaying) {
        if (kDebugMode) {
          _log.fine("VIDEO_PLAY");
          _dbgPlayCount++;
        }
        unawaited(controller.play());
      } else {
        if (kDebugMode) {
          _log.fine("VIDEO_PAUSE");
          _dbgPauseCount++;
        }
        unawaited(controller.pause());
      }
    }

    if (_lastAppliedMute != project.removeAudio) {
      _lastAppliedMute = project.removeAudio;
      if (kDebugMode) _dbgMuteChangeCount++;
      unawaited(controller.setVolume(project.removeAudio ? 0 : 1));
    }

    // videoeditor8.txt section 9: the explicit zero-edit fast path. When
    // the composition has no speed zones and no background music,
    // nothing below this line has any work to do — overlays are
    // evaluated independently by their own listeners (see the preview
    // Stack), not through this method at all, and rotation/flip/filter
    // are one-shot widget-tree concerns, not per-tick ones. Skipping
    // this keeps a plain, unedited clip's per-tick cost close to
    // caption_publish_step.dart's (essentially none), rather than merely
    // "safe but still doing the checks every tick."
    if (!project.needsPlaybackCoordination) {
      return;
    }

    final double desiredSpeed = EditorTransport.activeSpeedAt(project.speedZones, transport.currentTime);
    if (_lastAppliedPreviewSpeed != desiredSpeed) {
      _lastAppliedPreviewSpeed = desiredSpeed;
      if (kDebugMode) _dbgSpeedChangeCount++;
      unawaited(controller.setPlaybackSpeed(desiredSpeed));
    }

    final VideoPlayerController? music = _musicController;
    final BackgroundAudio? bg = project.bgAudio;
    if (music == null || !music.value.isInitialized) {
      return;
    }
    if (bg == null) {
      _musicInRegion = false;
      if (music.value.isPlaying) {
        if (kDebugMode) {
          _log.fine("MUSIC_PAUSE reason=NO_MUSIC");
          _dbgMusicPauseCount++;
          _logMusicEvent("PAUSE/NO_MUSIC");
        }
        unawaited(music.pause());
      }
      return;
    }

    // The ONE decision point (videoeditor7.txt section 5/8: "Transport
    // should not be a second media player" — this widget is the only
    // place that ever calls seekTo/play/pause on the music controller;
    // EditorTransport and decideMusicSync only ever say what SHOULD
    // happen). See decideMusicSync's own doc comment for why
    // `_musicInRegion` — not `music.value.isPlaying` — is what tracks
    // "have we already entered this region."
    final bool wasInRegion = _musicInRegion;
    final MusicSyncDecision decision = EditorTransport.decideMusicSync(
      bg: bg,
      currentTime: transport.currentTime,
      trimmedDuration: project.trimmedDuration,
      isPlaying: transport.isPlaying,
      isScrubbing: transport.isScrubbing,
      wasInRegion: wasInRegion,
      musicPlayerPosition: music.value.position,
    );
    // While actively scrubbing, "in region" is always reported as false
    // going forward, so the tick right after scrub-end is treated as a
    // fresh entry (forcing exactly one corrective seek) — matches
    // section 5's "on scrub end: seek music ONCE to the final correct
    // position."
    _musicInRegion = !transport.isScrubbing &&
        EditorTransport.musicLocalTimeAt(bg, transport.currentTime, project.trimmedDuration) != null;

    // Section 7 debug invariant: originally forced a pause whenever
    // `music.value.isPlaying` read true while the decision said it
    // shouldn't be. DOWNGRADED to log-only (never acts) after a real
    // user report of music unexpectedly going silent mid-playback,
    // combined with direct evidence (two screenshots, see the playback
    // watchdog's own history) that `VideoPlayerController.value.isPlaying`
    // is an UNRELIABLE flag on the reporting device — it read `false`
    // for many consecutive seconds while a controller was demonstrably,
    // continuously playing. This invariant trusted that exact same
    // flag as grounds to force a real `.pause()` call; if it's
    // similarly unreliable in the "stuck true" direction (or simply
    // wrong at the moment it's read), this would have been actively
    // CAUSING the reported cutout, not just failing to prevent one.
    // `_onTransportChanged`'s own regular seekTarget/no-seek branches
    // already pause music correctly when genuinely needed, gated on
    // `_lastAppliedMusicPlaying` (this screen's own reliable intent
    // cache), so this defensive extra pause was never load-bearing.
    if (kDebugMode && music.value.isPlaying && decision.playback == MusicPlaybackIntent.paused) {
      _log.warning(
        "INVARIANT OBSERVATION (not acted on): music.value.isPlaying=true but decision says paused "
        "(t=${transport.currentTime}, isPlaying=${transport.isPlaying}, "
        "isScrubbing=${transport.isScrubbing})",
      );
      _logMusicEvent("INVARIANT_OBSERVED_NOT_ACTED");
    }

    if (decision.seekTarget != null) {
      if (kDebugMode) {
        _log.fine("MUSIC_SEEK_REQUEST target=${decision.seekTarget} reason=${wasInRegion ? 'DRIFT' : 'ENTER_REGION'}");
      }
      _requestMusicSeek(decision.seekTarget!, playAfter: decision.playback == MusicPlaybackIntent.playing);
    } else {
      if (decision.playback == MusicPlaybackIntent.playing) {
        if (_lastAppliedMusicPlaying != true) {
          _lastAppliedMusicPlaying = true;
          if (kDebugMode) {
            _log.fine("MUSIC_PLAY reason=RESUME");
            _dbgMusicPlayCount++;
            _logMusicEvent("PLAY/RESUME");
          }
          unawaited(music.play());
        }
      } else if (_lastAppliedMusicPlaying != false) {
        _lastAppliedMusicPlaying = false;
        if (kDebugMode) {
          final String reason = transport.isScrubbing ? 'SCRUB' : 'OUT_OF_REGION';
          _log.fine("MUSIC_PAUSE reason=$reason");
          _dbgMusicPauseCount++;
          _logMusicEvent("PAUSE/$reason");
        }
        unawaited(music.pause());
      }
    }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        _dbgErrorCount++;
        _dbgLastError = "$e";
        _log.severe("_onTransportChanged threw — this tick's remaining listeners were skipped", e, stackTrace);
      }
    }
  }

  /// Requests that the music controller end up seeked to [target] and
  /// playing/paused per [playAfter] — coalesced exactly like
  /// [EditorTransport]'s own video-seek drain loop (see
  /// `_pendingMusicSeek`'s own doc comment for the bug this replaced).
  /// Calling this rapidly (every tick while drift keeps getting
  /// re-evaluated) only ever results in ONE seek being in flight at a
  /// time; newer calls just update the pending target/intent, and the
  /// loop naturally converges to the latest one instead of firing
  /// concurrent, self-invalidating seeks.
  ///
  /// [forcePlay] distinguishes two genuinely different situations that
  /// both end up calling this method with `playAfter: true`, found via
  /// a real user report after this distinction was missing: an ordinary
  /// per-tick DRIFT correction during otherwise-healthy playback (two
  /// independently-clocked `VideoPlayerController`s naturally drift
  /// apart by more than the 150ms threshold every second or so — this
  /// is normal, not a failure) only needs a `seekTo()`; forcing a fresh
  /// `play()` on every one of these (which is what happens dozens of
  /// times per second of healthy playback, confirmed via the on-screen
  /// debug overlay's `PLAY/POST_SEEK` log firing every ~150-200ms) was
  /// itself audibly disruptive — "kesik kesik çalıyor" (choppy,
  /// stop-start playback), a regression introduced by an earlier fix
  /// that removed the play()-call gate entirely to solve a DIFFERENT
  /// problem (a genuine stall never resuming). A CONFIRMED STALL
  /// (position frozen across multiple 800ms watchdog ticks) is the
  /// opposite case — the player has actually stopped, so only that path
  /// should pass `forcePlay: true` to bypass the cache and guarantee a
  /// real play() call actually reaches it.
  void _requestMusicSeek(Duration target, {required bool playAfter, bool forcePlay = false}) {
    _pendingMusicSeek = target;
    _pendingMusicPlayAfter = playAfter;
    _pendingMusicForcePlay = forcePlay;
    if (_musicSeekInFlight) {
      return;
    }
    unawaited(_drainMusicSeeks());
  }

  Future<void> _drainMusicSeeks() async {
    _musicSeekInFlight = true;
    try {
      while (_pendingMusicSeek != null) {
        final VideoPlayerController? music = _musicController;
        if (music == null) {
          _pendingMusicSeek = null;
          return;
        }
        final Duration target = _pendingMusicSeek!;
        final bool playAfter = _pendingMusicPlayAfter;
        final bool forcePlay = _pendingMusicForcePlay;
        _pendingMusicSeek = null;
        if (kDebugMode) {
          _log.fine("MUSIC_SEEK_BEGIN target=$target");
          _dbgMusicSeekCount++;
        }
        await music.seekTo(target);
        if (_musicController != music) {
          // The controller was torn down/replaced (source change)
          // while this seek was in flight — nothing left to apply it to.
          return;
        }
        if (_pendingMusicSeek != null) {
          // A newer target arrived while this seek was in flight — go
          // straight to it instead of applying this now-superseded
          // one's play/pause outcome. This is the exact mechanism that
          // used to be handled (incorrectly) by a generation-token
          // check that invalidated EVERY dispatch, not just genuinely
          // stale ones — see this class's own doc comment on the bug.
          continue;
        }
        // See _requestMusicSeek's own doc comment for the two-path
        // history behind this exact condition. Short version: ordinary
        // per-tick drift correction (forcePlay: false) must NOT force a
        // fresh play() every time — two independently-clocked
        // VideoPlayerControllers drift apart by >150ms naturally, many
        // times a second, during entirely healthy playback, and forcing
        // play() on every one of those was itself audibly disruptive
        // (confirmed via user report + the debug overlay's PLAY/POST_SEEK
        // firing every ~150-200ms). Only a CONFIRMED STALL (forcePlay:
        // true, only ever set by the playback watchdog after 3
        // consecutive 800ms ticks of zero position movement) bypasses
        // the cache to guarantee a real play() reaches a genuinely
        // stopped player.
        if (playAfter) {
          if (forcePlay || _lastAppliedMusicPlaying != true) {
            _lastAppliedMusicPlaying = true;
            if (kDebugMode) {
              _log.fine("MUSIC_PLAY reason=POST_SEEK forced=$forcePlay");
              _dbgMusicPlayCount++;
              _logMusicEvent("PLAY/POST_SEEK${forcePlay ? '/FORCED' : ''}");
            }
            await music.play();
          }
        } else if (_lastAppliedMusicPlaying != false) {
          _lastAppliedMusicPlaying = false;
          if (kDebugMode) {
            _dbgMusicPauseCount++;
            _logMusicEvent("PAUSE/POST_SEEK");
          }
          await music.pause();
        }
      }
    } finally {
      _musicSeekInFlight = false;
    }
  }

  /// Creates/replaces/tears down `_musicController` to match [audio], and
  /// writes [audio] into [VideoProject] via [EditorController] — the
  /// single place background music should be written from, so the
  /// preview player never drifts out of sync with the composition (the
  /// timeline's resize/remove callbacks and the music-picker dialog both
  /// go through this instead of writing the composition directly).
  Future<void> _setBgAudio(BackgroundAudio? audio) async {
    final EditorController notifier = ref.read(editorControllerProvider.notifier);
    final bool sourceChanged = ref.read(editorControllerProvider)?.bgAudio?.filePath != audio?.filePath;
    notifier.setBgAudio(audio);
    if (!sourceChanged) {
      if (audio != null) {
        unawaited(_musicController?.setVolume(audio.volume));
      }
      return;
    }
    final VideoPlayerController? old = _musicController;
    _musicController = null;
    _musicInRegion = false;
    _lastAppliedMusicPlaying = null;
    _pendingMusicSeek = null; // the drain loop (if any) exits on its own via the controller-identity check
    await old?.pause();
    await old?.dispose();
    if (audio == null) {
      return;
    }
    final VideoPlayerController controller = VideoPlayerController.file(File(audio.filePath));
    try {
      await controller.initialize();
      await controller.setVolume(audio.volume);
      if (mounted) {
        setState(() => _musicController = controller);
        // Immediate sync rather than waiting for the next transport
        // tick — otherwise newly-attached music sits silent/unsynced
        // until playback naturally advances or the user scrubs.
        _onTransportChanged();
      }
    } catch (_) {
      // The picked file's format isn't one the platform player can open
      // for live preview — FFmpeg's format support at export time is far
      // broader than video_player's, so this only affects the in-editor
      // preview, not whether the music actually ends up in the published
      // Ad. Surface it rather than silently doing nothing, but don't
      // block anything.
      await controller.dispose();
      if (mounted) {
        _showSnack("Couldn't preview this audio here — it'll still be used when you publish.");
      }
    }
  }

  /// trimStart/trimEnd are independently stored on [VideoProject] now
  /// (each edge is its own draggable handle — see [_Timeline]), not
  /// "start plus an auto-derived up-to-10s end" the way the single
  /// drag-to-move trim window used to work, so this is just the
  /// composition's own duration, not a recomputation.
  Duration get _trimmedDuration => ref.read(editorControllerProvider)?.trimmedDuration ?? Duration.zero;

  /// Drags the LEFT edge of the trim selection — the RIGHT edge
  /// (trimEnd) stays fixed, duration is clamped to
  /// [VideoConstraints.min, VideoConstraints.max], matching how a
  /// phone's native gallery/video editor trims (independent edges, not
  /// "move a fixed-length window").
  void _applyTrimStartEdge(double startSeconds) {
    final VideoProject? project = ref.read(editorControllerProvider);
    if (project == null) {
      return;
    }
    final Duration end = project.trimEnd;
    Duration start = Duration(milliseconds: (startSeconds * 1000).round());
    if (start < Duration.zero) {
      start = Duration.zero;
    }
    final Duration minStart = end - VideoConstraints.max;
    final Duration maxStart = end - VideoConstraints.min;
    if (start < minStart && minStart > Duration.zero) {
      start = minStart;
    }
    if (start > maxStart) {
      start = maxStart;
    }
    ref.read(editorControllerProvider.notifier).setTrim(start: start, end: end);
    if (kDebugMode) {
      _log.fine("VIDEO_SEEK_REQUEST target=$start reason=TRIM_EDGE");
      _dbgSeekCount++;
    }
    unawaited(_controller?.seekTo(start));
    // The trim window's own length is the transport's duration (project
    // time 0 = trimStart) — this direct controller.seekTo above isn't
    // routed through the transport's onSeek, but the resulting position
    // change still reaches the transport normally via
    // _reportPlayerPosition once the seek completes.
    _transport?.updateDuration(_trimmedDuration);
  }

  /// Drags the RIGHT edge — the LEFT edge (trimStart) stays fixed, same
  /// duration clamp as the left handle.
  void _applyTrimEndEdge(double endSeconds) {
    final VideoProject? project = ref.read(editorControllerProvider);
    final Duration? total = _controller?.value.duration;
    if (project == null || total == null) {
      return;
    }
    final Duration start = project.trimStart;
    Duration end = Duration(milliseconds: (endSeconds * 1000).round());
    if (end > total) {
      end = total;
    }
    final Duration minEnd = start + VideoConstraints.min;
    final Duration maxEnd = start + VideoConstraints.max;
    if (end < minEnd) {
      end = minEnd;
    }
    if (end > maxEnd) {
      end = maxEnd > total ? total : maxEnd;
    }
    ref.read(editorControllerProvider.notifier).setTrim(start: start, end: end);
    _transport?.updateDuration(_trimmedDuration);
  }

  void _cycleRotation() {
    final AppVideoRotation current = ref.read(editorControllerProvider)?.rotation ?? AppVideoRotation.none;
    final AppVideoRotation next = switch (current) {
      AppVideoRotation.none => AppVideoRotation.degrees90,
      AppVideoRotation.degrees90 => AppVideoRotation.degrees180,
      AppVideoRotation.degrees180 => AppVideoRotation.degrees270,
      AppVideoRotation.degrees270 => AppVideoRotation.none,
    };
    ref.read(editorControllerProvider.notifier).setRotation(next);
  }

  void _toggleFlip(AppFlipDirection direction) {
    final AppFlipDirection current = ref.read(editorControllerProvider)?.flip ?? AppFlipDirection.none;
    ref.read(editorControllerProvider.notifier).setFlip(current == direction ? AppFlipDirection.none : direction);
  }

  void _toggleRemoveAudio() {
    final bool current = ref.read(editorControllerProvider)?.removeAudio ?? false;
    ref.read(editorControllerProvider.notifier).setRemoveAudio(!current);
    // Mute is project-driven, applied through the one mechanism in
    // _onTransportChanged — called directly here just for immediacy
    // (no need to wait for the next transport tick).
    _onTransportChanged();
  }

  /// Wraps EditorController.undo()/redo() with a transport re-sync —
  /// either can restore a project state with a different trim window
  /// (and therefore a different transport duration/valid currentTime
  /// range) than what's currently loaded.
  void _undo() {
    ref.read(editorControllerProvider.notifier).undo();
    _syncTransportAfterProjectChange();
  }

  void _redo() {
    ref.read(editorControllerProvider.notifier).redo();
    _syncTransportAfterProjectChange();
  }

  void _syncTransportAfterProjectChange() {
    final VideoProject? project = ref.read(editorControllerProvider);
    if (project != null) {
      _transport?.updateDuration(project.trimmedDuration);
    }
    _onTransportChanged();
  }

  void _toggleFilterStrip() {
    setState(() => _showFilterStrip = !_showFilterStrip);
  }

  Future<void> _addSpeedZone() async {
    final SpeedZone? zone = await showDialog<SpeedZone>(
      context: context,
      builder: (BuildContext context) => _SpeedZoneDialog(maxDuration: _trimmedDuration),
    );
    if (zone == null) {
      return;
    }
    final List<SpeedZone> existing = ref.read(editorControllerProvider)?.speedZones ?? const <SpeedZone>[];
    if (existing.any((SpeedZone z) => z.overlaps(zone))) {
      _showSnack("That overlaps an existing speed zone.");
      return;
    }
    ref.read(editorControllerProvider.notifier).addSpeedZone(zone);
  }

  /// Drag-resize from the timeline's own edge handles (see [_Timeline]) —
  /// distinct from `_addSpeedZone`'s overlap check, since a zone shrinking
  /// or growing against its own previous bounds isn't "overlapping
  /// itself"; a stray drag past a neighboring zone is left uncorrected on
  /// purpose (rare with the zone counts this editor sees, and clamping
  /// against every sibling on every drag frame isn't worth the
  /// complexity yet).
  void _onResizeZone(SpeedZone oldZone, SpeedZone updated) {
    ref.read(editorControllerProvider.notifier).resizeSpeedZone(oldZone, updated);
  }

  void _onResizeOverlay(VideoOverlay oldOverlay, VideoOverlay updated) {
    ref.read(editorControllerProvider.notifier).updateOverlay(updated);
  }

  // BUG 6 fix: on a real device, tapping Text dimmed the screen (the
  // modal barrier opened) but showed no visible text-entry UI at all.
  // The dialog's content had grown tall (preview box, font picker,
  // style presets, outline/shadow/background toggles, an opacity
  // slider, entrance-effect chips, a time-range slider) — combined with
  // the keyboard opening immediately (autofocus:true) on a real phone's
  // actual screen height, a centered AlertDialog's own intrinsic-sizing
  // behavior is a known-brittle combination for tall, keyboard-heavy
  // content; it can end up effectively zero-height/clipped on some
  // devices while looking fine on a wider emulator. A scroll-controlled
  // bottom sheet is the standard, robust Flutter pattern for exactly
  // this case (tall form + keyboard) — it explicitly sizes itself
  // against the keyboard inset rather than relying on AlertDialog's
  // intrinsic sizing.
  Future<void> _addTextOverlay() async {
    final TextOverlay? overlay = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => _TextOverlaySheet(id: _uuid.v4(), maxDuration: _trimmedDuration),
    );
    if (overlay != null) {
      ref.read(editorControllerProvider.notifier).addOverlay(overlay);
    }
  }

  /// "Sticker" used to just open the device gallery directly, with no
  /// actual sticker library — this offers a curated preset set first
  /// (rendered as [TextOverlay]s, reusing the exact font/drawtext path
  /// already verified working, rather than a new image-compositing
  /// route that would need its own verification) with "choose from
  /// gallery" as an explicit secondary option, not the only one.
  Future<void> _addSticker() async {
    final _StickerChoice? choice = await showDialog<_StickerChoice>(
      context: context,
      builder: (BuildContext context) => const _StickerPickerDialog(),
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case _StickerSymbolChoice(:final String symbol, :final double fontSize):
        final _TimeRange? range = await showDialog<_TimeRange>(
          context: context,
          builder: (BuildContext context) => _TimeRangeDialog(maxDuration: _trimmedDuration),
        );
        if (range == null || !mounted) {
          return;
        }
        ref.read(editorControllerProvider.notifier).addOverlay(
              TextOverlay(
                id: _uuid.v4(),
                xPercent: 0.4,
                yPercent: 0.3,
                startSec: range.start,
                duration: range.end - range.start,
                text: symbol,
                fontSize: fontSize,
                hasOutline: true,
              ),
            );
      case _StickerGalleryChoice():
        await _addImageOverlayFromGallery();
    }
  }

  Future<void> _addImageOverlayFromGallery() async {
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) {
      return;
    }
    final _TimeRange? range = await showDialog<_TimeRange>(
      context: context,
      builder: (BuildContext context) => _TimeRangeDialog(maxDuration: _trimmedDuration),
    );
    if (range == null) {
      return;
    }
    ref.read(editorControllerProvider.notifier).addOverlay(
          ImageOverlay(
            id: _uuid.v4(),
            xPercent: 0.35,
            yPercent: 0.35,
            startSec: range.start,
            duration: range.end - range.start,
            assetPath: file.path,
          ),
        );
  }

  Future<void> _pickMusic() async {
    final PlatformFile? picked = await FilePicker.pickFile(type: FileType.audio);
    final String? path = picked?.path;
    if (path == null || !mounted) {
      return;
    }
    // Real bug found via user report: BackgroundAudio.duration was never
    // set when music was first added, defaulting to null — which
    // musicLocalTimeAt treats as "extends to the end of the trimmed
    // video," regardless of the picked file's own actual length. Any
    // music shorter than the video (the common case — a sound effect or
    // a music snippet) meant the sync logic tried to seek the music
    // controller PAST its own real duration for the rest of the clip,
    // which never produces audible playback there — reported as "music
    // never plays no matter where I scrub to." Probing the file's real
    // duration up front (the same LocalVideoProber this screen already
    // uses for the main clip) and clamping to it fixes this at the
    // source, for every current and future BackgroundAudio consumer.
    final Duration audioDuration = await ref.read(localVideoProberProvider).probeDuration(path);
    if (!mounted) {
      return;
    }
    final BackgroundAudio? audio = await showDialog<BackgroundAudio>(
      context: context,
      builder: (BuildContext context) => _BackgroundAudioDialog(
        filePath: path,
        maxDuration: _trimmedDuration,
        audioDuration: audioDuration,
      ),
    );
    if (audio != null) {
      unawaited(_setBgAudio(audio));
    }
  }

  // Baseline values captured at the start of a drag/pinch/rotate gesture
  // on an overlay — details.scale/details.rotation are cumulative from
  // gesture start, not incremental, so the "before" state has to be
  // remembered once rather than applied delta-by-delta.
  String? _gestureOverlayId;
  double _gestureBaseX = 0;
  double _gestureBaseY = 0;
  double _gestureBaseSize = 0;
  double _gestureBaseRotationDegrees = 0;
  Offset _gestureStartFocalPoint = Offset.zero;

  void _onOverlayScaleStart(VideoOverlay overlay, ScaleStartDetails details) {
    _gestureOverlayId = overlay.id;
    _gestureBaseX = overlay.xPercent;
    _gestureBaseY = overlay.yPercent;
    _gestureBaseSize = switch (overlay) {
      TextOverlay(:final double fontSize) => fontSize,
      ImageOverlay(:final double widthPercent) => widthPercent,
    };
    _gestureBaseRotationDegrees = overlay is ImageOverlay ? overlay.rotationDegrees : 0;
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _onOverlayScaleUpdate(VideoOverlay overlay, ScaleUpdateDetails details, Size previewSize) {
    if (_gestureOverlayId != overlay.id) {
      return;
    }
    final double dx = (details.focalPoint.dx - _gestureStartFocalPoint.dx) / previewSize.width;
    final double dy = (details.focalPoint.dy - _gestureStartFocalPoint.dy) / previewSize.height;
    final double nextX = (_gestureBaseX + dx).clamp(0.0, 1.0);
    final double nextY = (_gestureBaseY + dy).clamp(0.0, 1.0);

    final VideoOverlay updated = switch (overlay) {
      TextOverlay() => TextOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          text: overlay.text,
          argbColor: overlay.argbColor,
          fontSize: (_gestureBaseSize * details.scale).clamp(12.0, 96.0),
          fontFamily: overlay.fontFamily,
          animation: overlay.animation,
          opacity: overlay.opacity,
          hasOutline: overlay.hasOutline,
          hasShadow: overlay.hasShadow,
          hasBackground: overlay.hasBackground,
        ),
      ImageOverlay() => ImageOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          assetPath: overlay.assetPath,
          widthPercent: (_gestureBaseSize * details.scale).clamp(0.08, 0.9),
          rotationDegrees: _gestureBaseRotationDegrees + details.rotation * 180 / pi,
        ),
    };
    ref.read(editorControllerProvider.notifier).updateOverlay(updated);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retake() {
    // Explicit, not just left to dispose() — dispose() only fires once
    // this widget is actually torn down, and a rebuild racing the retake
    // (e.g. the flow controller's state changing step before this
    // screen unmounts) could otherwise leave the flag stuck true, making
    // the leave-confirmation dialog fire on a screen with nothing to lose.
    ref.read(hasUnsavedCreateEditsProvider.notifier).state = false;
    ref.read(createAdFlowControllerProvider.notifier).retake();
  }

  /// Undoes every edit made on this screen — back to the untouched
  /// capture, still on this screen (unlike Retake, which discards the
  /// capture itself and goes back to record/import). Itself one more
  /// undo-able step (routed through EditorController, not a bypass of
  /// it), so hitting Reset by mistake can still be undone.
  void _reset() {
    ref.read(editorControllerProvider.notifier).resetToDefaults(_initialTrimEnd);
    // Reset is a deliberate, rare, one-time action (not hot-path
    // concern) — applied directly rather than through the cache-gated
    // path in _onTransportChanged, since the real controller's current
    // volume/speed may differ from the reset-to defaults (e.g. a speed
    // zone was active) and the cache must reflect reality afterward, not
    // just "what the composition's default happens to be."
    unawaited(_controller?.setVolume(1));
    unawaited(_controller?.setPlaybackSpeed(1.0));
    _lastAppliedMute = false;
    _lastAppliedPreviewSpeed = 1.0;
    _transport?.updateDuration(_initialTrimEnd);
    if (kDebugMode) {
      _log.fine("VIDEO_SEEK_REQUEST target=0:00 reason=RESET");
      _dbgSeekCount++;
    }
    unawaited(_controller?.seekTo(Duration.zero));
    unawaited(_setBgAudio(null));
    _onTransportChanged();
  }

  Future<void> _confirm() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    final VideoProject? project = ref.read(editorControllerProvider);
    if (draft == null || project == null) {
      return;
    }
    setState(() {
      _processing = true;
      _progress = 0;
      _error = null;
    });
    // Real user report: background music mixed correctly into the export
    // (confirmed present in the published file) didn't play in the very
    // next screen's (CaptionPublishStep) preview. This editor keeps two
    // live VideoPlayerControllers (_controller, _musicController) whose
    // teardown in dispose() is fire-and-forget (`.dispose().ignore()`),
    // so their native audio session can still be releasing when the next
    // screen's own controller starts playing moments later — a plausible
    // audio-focus handoff race on Android. Explicitly pausing both here,
    // awaited, before doing anything else, both starts releasing that
    // session earlier and stops two silent audio decoders competing with
    // FFmpeg for device resources during the export itself. The watchdog
    // is stopped first — otherwise, since it drives off `transport.
    // isPlaying` (untouched by a direct controller.pause()) rather than
    // these controllers, its own freeze-recovery logic would see
    // "supposed to be playing, position stalled" on its very next tick
    // and call controller.play() again, undoing this pause.
    _playbackWatchdog?.cancel();
    _transport?.pause();
    _watchdogLastMusicPos = null;
    _watchdogLastVideoPos = null;
    await Future.wait(<Future<void>>[
      if (_controller != null) _controller!.pause().catchError((_) {}),
      if (_musicController != null) _musicController!.pause().catchError((_) {}),
    ]);

    try {
      final bool needsTrim = project.trimStart > Duration.zero || project.trimEnd < draft.duration;
      final bool hasSimpleEdit = project.rotation != AppVideoRotation.none ||
          project.flip != AppFlipDirection.none ||
          project.removeAudio;
      // Color grading has no equivalent in the fast easy_video_editor
      // pipeline (no color-filter support there), so it forces the FFmpeg
      // path the same way a speed zone or overlay does.
      final bool hasAdvancedEdit = project.speedZones.isNotEmpty ||
          project.overlays.isNotEmpty ||
          project.colorFilter != AppColorFilter.none ||
          project.bgAudio != null;

      final LocalVideoDraft finalDraft;
      if (!needsTrim && !hasSimpleEdit && !hasAdvancedEdit) {
        // Nothing was actually changed — publish the capture as-is rather
        // than paying for a no-op re-encode.
        finalDraft = draft;
      } else if (hasAdvancedEdit) {
        // project IS the composition being exported — no separate
        // reconstruction from scattered fields; preview and export read
        // the exact same object.
        final VideoExportService service = ref.read(videoExportServiceProvider);
        _progressSub = service.progress.listen((double p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        });
        final String outputPath = await service.export(project);
        final Duration outputDuration = await ref.read(localVideoProberProvider).probeDuration(outputPath);
        finalDraft = LocalVideoDraft(filePath: outputPath, duration: outputDuration);
      } else {
        final VideoEditRequest request = VideoEditRequest(
          sourcePath: draft.filePath,
          trimStart: project.trimStart,
          trimEnd: project.trimEnd,
          rotation: project.rotation,
          flip: project.flip,
          removeAudio: project.removeAudio,
        );
        final String outputPath = await ref.read(videoEditorServiceProvider).apply(
              request,
              onProgress: (double p) {
                if (mounted) {
                  setState(() => _progress = p);
                }
              },
            );
        final Duration outputDuration = await ref.read(localVideoProberProvider).probeDuration(outputPath);
        finalDraft = LocalVideoDraft(filePath: outputPath, duration: outputDuration);
      }

      // Real, direct user complaint: "quality drops a lot on Next, no
      // matter what I raise the export bitrate to." Rather than keep
      // guessing at FFmpeg args, surface the actual evidence needed to
      // tell "the requested bitrate isn't being honored by this
      // device's hardware encoder" (a real, well-documented Android
      // MediaCodec limitation on some devices — a software fallback
      // would fix it but costs GPL licensing or export speed, not a
      // change to make blindly) apart from any other cause. Debug-only,
      // shown directly on screen (not just logcat) so it's visible
      // without a connected computer.
      if (kDebugMode && finalDraft.filePath != draft.filePath) {
        try {
          final int sourceBytes = await File(draft.filePath).length();
          final int outputBytes = await File(finalDraft.filePath).length();
          final double sourceMbps =
              sourceBytes * 8 / 1000000 / (draft.duration.inMilliseconds / 1000.0);
          final double outputMbps =
              outputBytes * 8 / 1000000 / (finalDraft.duration.inMilliseconds / 1000.0);
          _log.info(
            "EXPORT_QUALITY_CHECK source=${(sourceBytes / 1000000).toStringAsFixed(1)}MB "
            "(${sourceMbps.toStringAsFixed(1)}Mbps) -> "
            "output=${(outputBytes / 1000000).toStringAsFixed(1)}MB (${outputMbps.toStringAsFixed(1)}Mbps) "
            "requested=50Mbps",
          );
          if (mounted) {
            _showSnack(
              "DEBUG: source ${sourceMbps.toStringAsFixed(1)}Mbps -> "
              "output ${outputMbps.toStringAsFixed(1)}Mbps (requested 50Mbps)",
            );
          }
        } catch (_) {
          // Best-effort diagnostic only — never block publishing on it.
        }
      }

      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(finalDraft);
    } catch (e) {
      setState(() => _error = "Couldn't process this clip: $e");
    } finally {
      await _progressSub?.cancel();
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rawPreviewMode) {
      return _buildRawPreview();
    }
    if (kDebugMode) _dbgEditorRebuildCount++;
    final VideoPlayerController? controller = _controller;
    final VideoProject? project = ref.watch(editorControllerProvider);
    final bool ready = controller != null && controller.value.isInitialized && project != null;

    final bool hasEdits = project?.hasAnyEdit ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final StateController<bool> flag = ref.read(hasUnsavedCreateEditsProvider.notifier);
      if (flag.state != hasEdits) {
        flag.state = hasEdits;
      }
    });

    // Same IndexedStack problem as the feed (see app_shell.dart's doc
    // comment on activeShellBranchIndexProvider): switching to a
    // different bottom-nav tab while on this screen doesn't pause this
    // preview on its own — without this listener the clip (with audio)
    // kept playing behind whichever tab the user switched to.
    ref.listen(activeShellBranchIndexProvider, (int? previous, int next) {
      // Routed through the transport (not controller.play()/pause()
      // directly) so isPlaying keeps exactly one owner — the ruler's
      // play/pause icon and every other transport-driven bit of UI stay
      // correct after a tab switch, not just the raw player itself.
      final EditorTransport? transport = _transport;
      if (transport == null) {
        return;
      }
      if (next == 2) {
        transport.play();
      } else {
        transport.pause();
      }
    });

    final EditorController editorNotifier = ref.read(editorControllerProvider.notifier);

    return Scaffold(
      // Immersive per the editor spec's section 12: no title clutter, no
      // giant bottom Continue button (removed below) — "Next" is the one
      // primary action, top-right, and video stays the visual focus.
      // Undo/redo stay directly visible (used often enough that burying
      // them in a menu would cost more than the AppBar space they take);
      // Reset/Retake — rarer, more consequential actions — are grouped
      // into one overflow menu instead of their own permanent buttons.
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Undo",
            onPressed: (_processing || !editorNotifier.canUndo) ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: "Redo",
            onPressed: (_processing || !editorNotifier.canRedo) ? null : _redo,
          ),
          PopupMenuButton<VoidCallback>(
            enabled: !_processing,
            onSelected: (VoidCallback action) => action(),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
              PopupMenuItem<VoidCallback>(value: _reset, child: const Text("Reset edits")),
              PopupMenuItem<VoidCallback>(value: _retake, child: const Text("Retake")),
              // videoeditor9.txt: temporary hard-isolation A/B test entry
              // point — debug builds only, never visible/reachable in a
              // release build.
              if (kDebugMode)
                PopupMenuItem<VoidCallback>(
                  value: () => unawaited(_enterRawPreviewMode()),
                  child: const Text("Raw preview mode (debug)"),
                ),
              // videoeditor10.txt's standalone-route lifecycle isolation
              // experiment — debug builds only. Unlike raw preview mode
              // above (which stays inside this same TrimStep instance),
              // this genuinely leaves/disposes TrimStep first.
              if (kDebugMode)
                PopupMenuItem<VoidCallback>(
                  value: _openStandaloneRawPlayerRoute,
                  child: const Text("Standalone route (debug)"),
                ),
            ],
          ),
          TextButton(
            onPressed: (!ready || _processing) ? null : () => unawaited(_confirm()),
            child: Text(_processing ? "${(_progress * 100).round()}%" : "Next"),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 9 / 16,
                child: ready
                    ? LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final Size previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                          return ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                _VideoPreview(
                                  controller: controller,
                                  rotation: project.rotation,
                                  flip: project.flip,
                                  colorFilter: project.colorFilter,
                                ),
                                // On-device diagnostic (this round): shows
                                // the existing debug counters live, on
                                // screen, so the exact same physical-device
                                // stutter test that already proved raw/
                                // standalone smooth vs. normal-mode
                                // stuttering can also show WHICH counter (if
                                // any) climbs during that stutter — without
                                // needing adb/logcat access. Reuses
                                // _transport's own notifyListeners (already
                                // firing ~10x/sec) rather than adding a new
                                // timer, so this doesn't add a new
                                // per-tick cost of its own beyond one small
                                // Text rebuild.
                                if (kDebugMode)
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: _DebugOverlay(state: this),
                                  ),
                                for (final VideoOverlay overlay in project.overlays)
                                  // BUG 7 fix, now transport-driven
                                  // (videoeditor6.txt section 8):
                                  // visibility is a pure function of
                                  // VideoProject + EditorTransport's
                                  // currentTime — EditorTransport is the
                                  // one clock every overlay's [startSec,
                                  // endSec) window is evaluated against,
                                  // not the player's own position
                                  // directly (which would bypass the
                                  // scrub/seek-in-flight gating the
                                  // transport provides). Reactive via
                                  // AnimatedBuilder so only this one
                                  // overlay's visibility/animation
                                  // rebuilds per tick, not the full
                                  // preview tree.
                                  //
                                  // _OverlayPreview is now built INSIDE
                                  // builder (not passed as AnimatedBuilder's
                                  // cached `child`) — real bug found via
                                  // user report: entrance animations
                                  // (slide-in/pop-in) were implemented for
                                  // export only, never in the live
                                  // preview, because the previous
                                  // structure cached the whole overlay
                                  // subtree as a static `child` that never
                                  // rebuilt per tick, so there was nowhere
                                  // for animation progress to be applied.
                                  // localLayerTime comes from
                                  // EditorTransport.localLayerTimeAt — the
                                  // exact "animation clock foundation"
                                  // built for this purpose, now actually
                                  // used by an animation for the first
                                  // time.
                                  AnimatedBuilder(
                                    animation: _transport!,
                                    builder: (BuildContext context, Widget? child) {
                                      final bool visible =
                                          EditorTransport.isOverlayVisibleAt(overlay, _transport!.currentTime);
                                      if (!visible) {
                                        return const SizedBox.shrink();
                                      }
                                      final Duration localLayerTime =
                                          EditorTransport.localLayerTimeAt(overlay, _transport!.currentTime);
                                      return Positioned(
                                        left: overlay.xPercent * previewSize.width,
                                        top: overlay.yPercent * previewSize.height,
                                        child: GestureDetector(
                                          // onScale (not onPan) so one
                                          // finger moves it, two fingers
                                          // pinch to resize and rotate
                                          // (images) — all through the same
                                          // callback pair, since a
                                          // GestureDetector can't mix
                                          // onPanUpdate and onScaleUpdate
                                          // without them fighting over the
                                          // gesture arena.
                                          onScaleStart: (ScaleStartDetails d) => _onOverlayScaleStart(overlay, d),
                                          onScaleUpdate: (ScaleUpdateDetails d) =>
                                              _onOverlayScaleUpdate(overlay, d, previewSize),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: <Widget>[
                                              _OverlayPreview(
                                                overlay: overlay,
                                                previewWidth: previewSize.width,
                                                localLayerTime: localLayerTime,
                                              ),
                                              Positioned(
                                                right: -10,
                                                top: -10,
                                                child: GestureDetector(
                                                  onTap: () => ref
                                                      .read(editorControllerProvider.notifier)
                                                      .removeOverlay(overlay.id),
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.black87,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                    : ColoredBox(
                        color: Colors.black12,
                        child: Center(
                          child: _initError == null
                              ? const CircularProgressIndicator()
                              : Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(Icons.error_outline, size: 32),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(_initError!, textAlign: TextAlign.center),
                                      const SizedBox(height: AppSpacing.md),
                                      FilledButton(
                                        onPressed: _startInitialization,
                                        child: const Text("Try again"),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (ready) ...<Widget>[
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      _ToolButton(
                        icon: Icons.rotate_90_degrees_cw_outlined,
                        label: project.rotation == AppVideoRotation.none ? "Rotate" : "${project.rotation.value}°",
                        selected: project.rotation != AppVideoRotation.none,
                        onTap: _cycleRotation,
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip H",
                        selected: project.flip == AppFlipDirection.horizontal,
                        onTap: () => _toggleFlip(AppFlipDirection.horizontal),
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip V",
                        selected: project.flip == AppFlipDirection.vertical,
                        onTap: () => _toggleFlip(AppFlipDirection.vertical),
                        iconTurns: 1,
                      ),
                      _ToolButton(
                        icon: project.removeAudio ? Icons.volume_off : Icons.volume_up,
                        label: "Mute",
                        selected: project.removeAudio,
                        onTap: _toggleRemoveAudio,
                      ),
                      _ToolButton(
                        icon: Icons.palette_outlined,
                        label: project.colorFilter.label,
                        selected: project.colorFilter != AppColorFilter.none || _showFilterStrip,
                        onTap: _toggleFilterStrip,
                      ),
                      _ToolButton(
                        icon: Icons.music_note_outlined,
                        label: "Music",
                        selected: project.bgAudio != null,
                        onTap: () => unawaited(_pickMusic()),
                      ),
                      _ToolButton(
                        icon: Icons.slow_motion_video_outlined,
                        label: "Slow-mo",
                        onTap: () => unawaited(_addSpeedZone()),
                      ),
                      _ToolButton(
                        icon: Icons.text_fields,
                        label: "Text",
                        onTap: () => unawaited(_addTextOverlay()),
                      ),
                      _ToolButton(
                        icon: Icons.emoji_emotions_outlined,
                        label: "Sticker",
                        onTap: () => unawaited(_addSticker()),
                      ),
                    ],
                  ),
                ),

                if (_showFilterStrip) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        for (final AppColorFilter filter in AppColorFilter.values)
                          _FilterPreviewChip(
                            filter: filter,
                            thumbnailPath: _thumbnailPaths.isNotEmpty ? _thumbnailPaths.first : null,
                            selected: project.colorFilter == filter,
                            onTap: () => ref.read(editorControllerProvider.notifier).setColorFilter(filter),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.md),
                _Timeline(
                  controller: controller,
                  transport: _transport!,
                  thumbnailPaths: _thumbnailPaths,
                  originalDuration: controller.value.duration,
                  trimStartSeconds: project.trimStart.inMilliseconds / 1000.0,
                  trimmedDuration: _trimmedDuration,
                  onTrimStartChanged: _applyTrimStartEdge,
                  onTrimEndChanged: _applyTrimEndEdge,
                  speedZones: project.speedZones,
                  overlays: project.overlays,
                  bgAudio: project.bgAudio,
                  onRemoveZone: (SpeedZone z) => ref.read(editorControllerProvider.notifier).removeSpeedZone(z),
                  onResizeZone: _onResizeZone,
                  onRemoveOverlay: (String id) => ref.read(editorControllerProvider.notifier).removeOverlay(id),
                  onResizeOverlay: _onResizeOverlay,
                  onResizeMusic: (BackgroundAudio updated) => unawaited(_setBgAudio(updated)),
                  onRemoveMusic: () => unawaited(_setBgAudio(null)),
                  onDebugTimelineUpdate: kDebugMode ? () => _dbgTimelineUpdateCount++ : null,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),

              if (_processing)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The video texture and its optional rotate/flip/filter layers, isolated
/// into their own widget (videoeditor8.txt section 4/9). Two deliberate
/// differences from the block this replaced: (a) rotation==none,
/// flip==none, and colorFilter==none each skip building their respective
/// wrapper widget entirely instead of always constructing an
/// identity-transform `RotatedBox`/`Transform`/`ColorFiltered` — a
/// zero-edit clip's preview tree is therefore just
/// `AspectRatio(child: VideoPlayer(controller))`, the same shape
/// `caption_publish_step.dart` renders; (b) a `RepaintBoundary` wraps the
/// whole thing, so the video texture's own per-frame repaints (driven by
/// the native player, not by Flutter's widget rebuild cycle) don't force
/// the rest of `TrimStep`'s tree — tool row, timeline, overlays — into
/// the same repaint pass, matching how the bare `VideoPlayer` on the
/// Publish screen never does either.
class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.controller,
    required this.rotation,
    required this.flip,
    required this.colorFilter,
  });

  final VideoPlayerController controller;
  final AppVideoRotation rotation;
  final AppFlipDirection flip;
  final AppColorFilter colorFilter;

  @override
  Widget build(BuildContext context) {
    Widget video = AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
    if (flip != AppFlipDirection.none) {
      video = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          flip == AppFlipDirection.horizontal ? -1 : 1,
          flip == AppFlipDirection.vertical ? -1 : 1,
          1,
        ),
        child: video,
      );
    }
    if (rotation != AppVideoRotation.none) {
      video = RotatedBox(quarterTurns: rotation.quarterTurns, child: video);
    }
    if (colorFilter != AppColorFilter.none) {
      video = ColorFiltered(colorFilter: colorFilter.previewFilter, child: video);
    }
    return RepaintBoundary(child: Center(child: video));
  }
}

/// Debug-only, on-screen live state readout (`kDebugMode` only) — added
/// after a reported oscillation where a first Play press only moved the
/// video and a second Play press only played music, with nothing
/// incrementing at all. Deliberately driven by its OWN `Timer.periodic`
/// rather than `_transport`'s notifications: the exact bug under
/// investigation is a scenario where `_transport` itself might stop
/// notifying (a frozen video), which would otherwise freeze this
/// overlay's own display too and hide the very evidence needed to see
/// it. Isolated into its own small widget so this periodic refresh never
/// costs a rebuild of the rest of the editor tree.
class _DebugOverlay extends StatefulWidget {
  const _DebugOverlay({required this.state});
  final _TrimStepState state;

  @override
  State<_DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<_DebugOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 300ms: fast enough to feel live for manual play/pause testing,
    // cheap enough (one small Text rebuild) to not matter even though
    // it's unconditional while this overlay is mounted.
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _TrimStepState s = widget.state;
    final VideoPlayerController? controller = s._controller;
    final EditorTransport? transport = s._transport;
    final VideoPlayerController? music = s._musicController;
    final BackgroundAudio? bg = s.ref.read(editorControllerProvider)?.bgAudio;
    final Duration? bgEnd = bg == null
        ? null
        : bg.startSec + (bg.duration ?? (s._trimmedDuration - bg.startSec));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Colors.black54,
      child: Text(
        "seek=${s._dbgSeekCount} play=${s._dbgPlayCount} pause=${s._dbgPauseCount}\n"
        "speed=${s._dbgSpeedChangeCount} mute=${s._dbgMuteChangeCount}\n"
        "tl=${s._dbgTimelineUpdateCount} rebuild=${s._dbgEditorRebuildCount}\n"
        "mSeek=${s._dbgMusicSeekCount} mPlay=${s._dbgMusicPlayCount} mPause=${s._dbgMusicPauseCount}\n"
        "musicInRegion=${s._musicInRegion} errors=${s._dbgErrorCount}\n"
        // Real-state flags (not counts): v/m are the NATIVE controllers'
        // own reported isPlaying; t is the transport's; lastV/lastM are
        // what this screen last actually told each controller to be;
        // vPos/mPos are raw positions, to see directly whether either
        // decoder is truly frozen vs. just unreported.
        "v=${controller?.value.isPlaying} t=${transport?.isPlaying} m=${music?.value.isPlaying}\n"
        "lastV=${s._lastAppliedIsPlaying} lastM=${s._lastAppliedMusicPlaying}\n"
        "vPos=${controller?.value.position.inMilliseconds} mPos=${music?.value.position.inMilliseconds}\n"
        // Added after a report of music audibly cutting out ~500ms into
        // playback while video keeps going: distinguishes "the music's
        // own assigned window on the timeline is genuinely that short"
        // (bgStart/bgEnd would show it) from an actual sync bug — tPos
        // is transport.currentTime for direct side-by-side comparison
        // against bgStart/bgEnd.
        "bgStart=${bg?.startSec.inMilliseconds} bgEnd=${bgEnd?.inMilliseconds} "
        "tPos=${transport?.currentTime.inMilliseconds}\n"
        // Rolling history of the last several music play/pause
        // transitions (see _logMusicEvent) — catching the exact instant
        // audio cuts out in a single manually-timed screenshot is
        // genuinely hard; this shows what just happened even if the
        // screenshot lands slightly after the fact.
        "${s._dbgMusicEvents.join('\n')}"
        "${s._dbgLastError != null ? '\n${s._dbgLastError}' : ''}",
        style: TextStyle(
          color: s._dbgErrorCount > 0 ? Colors.redAccent : Colors.greenAccent,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.iconTurns = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int iconTurns;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.15) : null,
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RotatedBox(quarterTurns: iconTurns, child: Icon(icon, size: 20)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry in the horizontal filter picker (CLAUDE.md-adjacent spec
/// section 10: "horizontally scrollable filter selector with visual
/// previews," not a bare label). Uses a real frame from the clip's own
/// filmstrip when one's available (same thumbnails the timeline shows)
/// so the preview is the actual footage, not a generic swatch; falls
/// back to a plain tinted square before thumbnails finish generating.
class _FilterPreviewChip extends StatelessWidget {
  const _FilterPreviewChip({
    required this.filter,
    required this.thumbnailPath,
    required this.selected,
    required this.onTap,
  });

  final AppColorFilter filter;
  final String? thumbnailPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? path = thumbnailPath;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                child: ColorFiltered(
                  colorFilter: filter.previewFilter,
                  child: path != null
                      ? Image.file(File(path), fit: BoxFit.cover, width: 52, height: 52)
                      : ColoredBox(color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(filter.label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// The timeline: a visibly bounded panel (a bordered/tinted [Container],
/// not empty space) with a fixed-width label column on the left naming
/// each lane ("Clip", "Speed", "Music", "Text") and, to the right, a
/// time-mapped track area per lane — a lane's background is drawn even
/// when it's empty, so it's clear that's the region a slow-mo zone or
/// music clip would occupy, not an arbitrary gap.
///
/// Centered-playhead, horizontally-scrolling (spec section 3: "the
/// playhead should preferably remain centered while the timeline moves
/// underneath it" — the standard mobile pattern, not desktop's
/// drag-a-marker-across-a-fixed-ruler). Content lays out at a fixed
/// [_TimelineState._pixelsPerSecond] scale, not stretched to the
/// viewport, so there's always real horizontal scroll even for this
/// format's short (<=10s) clips — scale is what makes the ruler/chips
/// legible, not how much content there is. The ruler shows a tick +
/// number per second; the whole scrollable area is the scrub surface
/// (drag anywhere to seek); a static playhead line (outside the scroll
/// view, `IgnorePointer`) marks "now."
///
/// The Clip lane's trim selection is two independent edge handles (drag
/// left to change where the clip starts, drag right to change where it
/// ends — a phone gallery editor's model, not one draggable window of a
/// fixed length) over a clean filmstrip, with the excluded portions
/// dimmed rather than the selected portion filled — no permanent colored
/// block sits over the thumbnails.
///
/// Speed-zone, music, and overlay items are all directly drag-resizable
/// from their own left/right edge handles (a visibly larger grip than a
/// plain body tap, hit area roughly twice the visual size), in addition
/// to tap-to-remove on the body of the chip/bar. Every chip also prints
/// its own start–end time under its label.
class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.controller,
    required this.transport,
    required this.thumbnailPaths,
    required this.originalDuration,
    required this.trimStartSeconds,
    required this.trimmedDuration,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
    required this.speedZones,
    required this.overlays,
    required this.bgAudio,
    required this.onRemoveZone,
    required this.onResizeZone,
    required this.onRemoveOverlay,
    required this.onResizeOverlay,
    required this.onResizeMusic,
    required this.onRemoveMusic,
    this.onDebugTimelineUpdate,
  });

  final VideoPlayerController controller;
  final EditorTransport transport;
  final List<String> thumbnailPaths;
  final Duration originalDuration;
  final double trimStartSeconds;
  final Duration trimmedDuration;
  final ValueChanged<double> onTrimStartChanged;
  final ValueChanged<double> onTrimEndChanged;
  final List<SpeedZone> speedZones;
  final List<VideoOverlay> overlays;
  final BackgroundAudio? bgAudio;
  final void Function(SpeedZone) onRemoveZone;
  final void Function(SpeedZone oldZone, SpeedZone updated) onResizeZone;
  final void Function(String) onRemoveOverlay;
  final void Function(VideoOverlay oldOverlay, VideoOverlay updated) onResizeOverlay;
  final void Function(BackgroundAudio updated) onResizeMusic;
  final VoidCallback onRemoveMusic;
  final VoidCallback? onDebugTimelineUpdate;

  static const double _labelWidth = 52;
  static const double _rulerHeight = 22;
  static const double _trimLaneHeight = 44;
  static const double _laneHeight = 40;
  static const double _laneGap = 6;
  static const Duration _minZoneDuration = Duration(milliseconds: 300);

  static String _fmt(Duration d) => "${(d.inMilliseconds / 1000.0).toStringAsFixed(1)}s";

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  /// Fixed regardless of clip length or viewport width — legibility
  /// (ruler ticks, chip labels) is what sets this, not "does the content
  /// fit the screen." At 70px/s a 10s clip is 700px wide, comfortably
  /// scrollable on any phone.
  static const double _pixelsPerSecond = 70;
  static const double _textRowGap = 4;

  late final ScrollController _scrollController;

  /// True only while an actual user drag is moving the scroll view —
  /// distinguishes a user scrubbing (which should drive `seekTo`) from
  /// this widget's own `jumpTo` calls following normal playback (which
  /// must NOT feed back into another seek, or forward playback and
  /// auto-scroll would fight each other every frame).
  bool _isUserScrubbing = false;

  /// True while a trim-handle or edge-resize drag is in progress, so the
  /// ScrollView's own physics can be disabled for that gesture — without
  /// this, a drag that starts on a resize handle is ambiguous with "drag
  /// to scroll the timeline" and the outer ScrollView tends to win,
  /// since both are the same axis. Genuinely the single highest-risk
  /// piece of this widget to get right without a physical device — see
  /// this round's CLAUDE.md entry.
  bool _gestureLockScroll = false;

  /// Coalesces auto-scroll follows to at most once per rendered frame
  /// (videoeditor7.txt section 2/4/12: "pointer/position event -> update
  /// UI immediately... never block" and "do not let timeline auto-scroll
  /// interfere with video playback"). Without this, every single
  /// transport position report (the native player reports roughly every
  /// 100ms while playing, but undo/redo/other transport writes can also
  /// notify in bursts) would run a synchronous `jumpTo` — and therefore a
  /// full scroll Start/Update/End notification cycle plus a Scrollable
  /// relayout — on the very same call stack as the video's own position
  /// callback, competing with it for the same UI-thread frame budget.
  /// Deferring to a post-frame callback, and reading
  /// `transport.currentTime` only when that callback actually runs
  /// (never the value captured at schedule time), means a burst of ticks
  /// between frames collapses into exactly one `jumpTo`.
  bool _autoScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Auto-scroll now follows the ONE transport clock, not the player
    // controller directly (videoeditor6.txt section 1/11) — the
    // coalescing/scrub-vs-programmatic distinction this relies on lives
    // in EditorTransport itself, not duplicated here.
    widget.transport.addListener(_onTransportPositionChanged);
  }

  @override
  void dispose() {
    widget.transport.removeListener(_onTransportPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// Auto-scrolls the timeline to follow the transport's own clock
  /// (normal playback, or any other component's seek) — gated on
  /// `_isUserScrubbing` so this jump is never itself misread as a new
  /// user drag by the `NotificationListener` below (jumpTo's resulting
  /// ScrollUpdateNotification carries no `dragDetails`, so it wouldn't
  /// be anyway, but skipping the jump outright while the user's own
  /// finger is driving the scroll avoids visibly fighting their gesture
  /// for a frame). This is the transport-generalized version of the
  /// exact same feedback-loop-prevention this screen already had.
  void _onTransportPositionChanged() {
    if (_isUserScrubbing || !mounted || _autoScrollScheduled) {
      return;
    }
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollScheduled = false;
      if (_isUserScrubbing || !mounted || !_scrollController.hasClients) {
        return;
      }
      // Timeline content is laid out in SOURCE time (0 = start of the
      // original clip); transport.currentTime is PROJECT time (0 =
      // trimStart) — convert at this one boundary. Read fresh here
      // (not captured when this callback was scheduled), so whatever
      // the transport's latest position is by the time the frame
      // actually runs is what gets applied.
      final double projectSec = widget.transport.currentTime.inMilliseconds / 1000.0;
      final double sourceSec = widget.trimStartSeconds + projectSec;
      final double target = TimelineGeometry.scrollOffsetForTime(sourceSec, _pixelsPerSecond);
      final ScrollPosition position = _scrollController.position;
      final double clamped = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      // Skip a jump too small to be visible — avoids paying for a full
      // scroll-notification cycle when nothing would actually move.
      if ((clamped - position.pixels).abs() < 0.5) {
        return;
      }
      widget.onDebugTimelineUpdate?.call();
      _scrollController.jumpTo(clamped);
    });
  }

  void _setGestureLock(bool locked) {
    if (_gestureLockScroll != locked) {
      setState(() => _gestureLockScroll = locked);
    }
  }

  /// Converts a scroll offset (source-time pixels) into a project-time
  /// [Duration] clamped to the current trim window — the shared
  /// conversion both the drag-update and drag-end paths below use.
  Duration _projectTimeForScrollOffset(double pixels, double totalSec) {
    final double sourceSec = TimelineGeometry.timeForScrollOffset(pixels, _pixelsPerSecond).clamp(0.0, totalSec);
    final double projectSec =
        (sourceSec - widget.trimStartSeconds).clamp(0.0, widget.trimmedDuration.inMilliseconds / 1000.0);
    return Duration(milliseconds: (projectSec * 1000).round());
  }

  Future<void> _confirmRemoveZone(BuildContext context, SpeedZone zone) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this speed zone?"),
        content: Text("${zone.factor}x from ${zone.start.inSeconds}s to ${zone.end.inSeconds}s."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveZone(zone);
    }
  }

  Future<void> _confirmRemoveOverlay(BuildContext context, VideoOverlay overlay) async {
    final String label = overlay is TextOverlay ? '"${overlay.text}"' : "this sticker";
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this?"),
        content: Text("Removes $label from the video."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveOverlay(overlay.id);
    }
  }

  Future<void> _confirmRemoveMusic(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this music?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveMusic();
    }
  }

  Widget _lane(ColorScheme scheme, {required double top, required double height}) => Positioned(
        left: 0,
        right: 0,
        top: top,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      );

  /// A draggable grip at a lane item's edge — `onDeltaSeconds` receives
  /// the drag delta already converted from pixels to seconds. Hit area
  /// (32dp) is roughly twice the visual grip's own size, per the same
  /// touch-target research already applied once to the trim-window
  /// handle. Wrapped in the scroll-gesture lock (see `_gestureLockScroll`
  /// doc comment) so dragging it resizes instead of scrolling the
  /// timeline underneath your finger.
  Widget _edgeHandle({
    required double left,
    required double top,
    required double height,
    required ValueChanged<double> onDeltaSeconds,
  }) {
    return Positioned(
      left: left - 16,
      top: top,
      width: 32,
      height: height,
      child: Listener(
        onPointerDown: (_) => _setGestureLock(true),
        onPointerUp: (_) => _setGestureLock(false),
        onPointerCancel: (_) => _setGestureLock(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) => onDeltaSeconds(d.delta.dx / _pixelsPerSecond),
          child: Center(
            child: Container(
              width: 8,
              height: height * 0.7,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.black26),
                boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black45, blurRadius: 3)],
              ),
              child: const Icon(Icons.drag_indicator, size: 10, color: Colors.black45),
            ),
          ),
        ),
      ),
    );
  }

  /// Purely visual now — the ruler's own tap/drag-to-seek gesture was
  /// removed; the ScrollView's native scroll (see the `NotificationListener`
  /// in `build`) is the scrub surface for the *entire* timeline now, not
  /// just this one lane, matching the centered-playhead model.
  Widget _ruler(ColorScheme scheme, double totalSec) {
    final int lastTick = totalSec.floor();
    return Positioned(
      left: 0,
      top: 0,
      height: _Timeline._rulerHeight,
      width: totalSec * _pixelsPerSecond,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int i = 0; i <= lastTick; i++)
            Positioned(
              left: i * _pixelsPerSecond - 10,
              top: 0,
              width: 20,
              child: Column(
                children: <Widget>[
                  Container(width: 1, height: 5, color: scheme.onSurfaceVariant),
                  Text("${i}s", style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Greedy interval-packing: overlapping text/sticker layers get
  /// separate rows (per the spec's own ASCII diagram of two text layers
  /// stacked as distinct tracks) instead of visually colliding in one
  /// lane. Sorted by start time; an overlay goes in the first row whose
  /// last-placed item already ended by the time this one starts, else a
  /// new row.
  Map<String, int> _packOverlayRows(List<VideoOverlay> overlays) {
    final List<VideoOverlay> sorted = List<VideoOverlay>.of(overlays)
      ..sort((VideoOverlay a, VideoOverlay b) => a.startSec.compareTo(b.startSec));
    final List<Duration> rowEndTimes = <Duration>[];
    final Map<String, int> rowOf = <String, int>{};
    for (final VideoOverlay o in sorted) {
      int assigned = -1;
      for (int r = 0; r < rowEndTimes.length; r++) {
        if (rowEndTimes[r] <= o.startSec) {
          assigned = r;
          break;
        }
      }
      if (assigned == -1) {
        assigned = rowEndTimes.length;
        rowEndTimes.add(o.endSec);
      } else {
        rowEndTimes[assigned] = o.endSec;
      }
      rowOf[o.id] = assigned;
    }
    return rowOf;
  }

  @override
  Widget build(BuildContext context) {
    final double totalSec = widget.originalDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0) {
      return const SizedBox.shrink();
    }
    final double trimmedSec = widget.trimmedDuration.inMilliseconds / 1000.0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final BackgroundAudio? music = widget.bgAudio;
    double? musicLeft, musicWidth;
    Duration musicStart = Duration.zero, musicEnd = Duration.zero;
    if (music != null) {
      musicStart = music.startSec;
      final Duration musicDuration = music.duration ?? (widget.trimmedDuration - music.startSec);
      musicEnd = musicStart + musicDuration;
      musicLeft = (musicStart.inMilliseconds / 1000.0 + widget.trimStartSeconds) * _pixelsPerSecond;
      musicWidth = musicDuration.inMilliseconds / 1000.0 * _pixelsPerSecond;
    }

    final Map<String, int> overlayRow = _packOverlayRows(widget.overlays);
    final int textRows = overlayRow.values.isEmpty ? 1 : overlayRow.values.reduce(max) + 1;
    final double textLaneHeight = textRows * _Timeline._laneHeight + (textRows - 1) * _textRowGap;

    final double trimTop = _Timeline._rulerHeight + _Timeline._laneGap;
    final double speedTop = trimTop + _Timeline._trimLaneHeight + _Timeline._laneGap;
    final double musicTop = speedTop + _Timeline._laneHeight + _Timeline._laneGap;
    final double overlayTop = musicTop + _Timeline._laneHeight + _Timeline._laneGap;
    final double totalHeight = overlayTop + textLaneHeight;
    final double contentWidth = totalSec * _pixelsPerSecond;
    final double selLeft = widget.trimStartSeconds * _pixelsPerSecond;
    final double selWidth = trimmedSec * _pixelsPerSecond;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SizedBox(
        height: totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _Timeline._labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: _Timeline._rulerHeight,
                    child: AnimatedBuilder(
                      animation: widget.transport,
                      builder: (BuildContext context, Widget? child) => InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () =>
                            widget.transport.isPlaying ? widget.transport.pause() : widget.transport.play(),
                        child: Icon(
                          widget.transport.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._trimLaneHeight, child: _LaneLabel("Clip", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._laneHeight, child: _LaneLabel("Speed", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._laneHeight, child: _LaneLabel("Music", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: textLaneHeight, child: _LaneLabel("Text", scheme)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double viewportWidth = constraints.maxWidth;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      // User vs. programmatic scroll is still
                      // distinguished exactly as before
                      // (dragDetails != null); what changed is that the
                      // resulting begin/request/end calls now go through
                      // EditorTransport's own coalescing (latest-wins,
                      // generation-safe — see editor_transport.dart)
                      // instead of this widget's own former
                      // _pendingSeek/_seekInFlight pair, so every
                      // scrubbing surface in the editor (this timeline,
                      // and any future one) shares the exact same
                      // coalescing guarantees instead of each
                      // reimplementing it.
                      if (notification is ScrollStartNotification && notification.dragDetails != null) {
                        _isUserScrubbing = true;
                        widget.transport.beginScrub();
                      } else if (notification is ScrollUpdateNotification && _isUserScrubbing) {
                        widget.transport
                            .requestSeek(_projectTimeForScrollOffset(notification.metrics.pixels, totalSec));
                      } else if (notification is ScrollEndNotification && _isUserScrubbing) {
                        // THE root cause found via the on-device counter
                        // overlay: ScrollPosition.jumpTo() (the
                        // programmatic auto-follow in
                        // _onTransportPositionChanged) itself dispatches
                        // its own ScrollStartNotification/
                        // ScrollUpdateNotification/ScrollEndNotification
                        // sequence — the Start/Update legs were already
                        // correctly ignored (dragDetails == null /
                        // !_isUserScrubbing), but this End leg was NOT
                        // gated at all, so every single auto-follow jump
                        // was also calling endScrub() -> requestSeek() on
                        // the real video controller. That's a genuine,
                        // real decoder seek (unlike play()/pause(), which
                        // don't force a decode-position change) firing at
                        // roughly the same rate as playback position
                        // updates themselves — confirmed physically via
                        // the debug overlay showing `seek` and `tl`
                        // (timeline update) climbing in lockstep. Gating
                        // this on `_isUserScrubbing` (only ever true
                        // between a REAL drag's Start and End) is the fix.
                        _isUserScrubbing = false;
                        widget.transport
                            .endScrub(_projectTimeForScrollOffset(notification.metrics.pixels, totalSec));
                      }
                      return false;
                    },
                    child: SizedBox(
                      height: totalHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            physics: _gestureLockScroll
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              // Real user feedback: replaced the earlier
                              // centered-playhead padding (equal on both
                              // sides) with left-anchored padding — just
                              // enough leading space for the playhead's
                              // own fixed offset, and enough trailing
                              // space for the clip's last instant to
                              // still reach the playhead.
                              padding: EdgeInsets.only(
                                left: TimelineGeometry.playheadOffset,
                                right: viewportWidth - TimelineGeometry.playheadOffset,
                              ),
                              child: SizedBox(
                                width: contentWidth,
                                height: totalHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    // Lane backgrounds — drawn even when
                                    // empty, so every lane's own area is
                                    // visible, not just wherever
                                    // something happens to be placed.
                                    _lane(scheme, top: trimTop, height: _Timeline._trimLaneHeight),
                                    _lane(scheme, top: speedTop, height: _Timeline._laneHeight),
                                    _lane(scheme, top: musicTop, height: _Timeline._laneHeight),
                                    _lane(scheme, top: overlayTop, height: textLaneHeight),

                                    _ruler(scheme, totalSec),

                                    // Base track — real decoded frames
                                    // when the filmstrip has generated, a
                                    // plain bar otherwise (best-effort —
                                    // see _generateThumbnails' own doc
                                    // comment).
                                    if (widget.thumbnailPaths.isNotEmpty)
                                      Positioned(
                                        top: trimTop,
                                        left: 0,
                                        width: contentWidth,
                                        height: _Timeline._trimLaneHeight,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(AppRadius.sm),
                                          child: Row(
                                            children: <Widget>[
                                              for (final String path in widget.thumbnailPaths)
                                                Expanded(
                                                  child: Image.file(
                                                    File(path),
                                                    fit: BoxFit.cover,
                                                    height: _Timeline._trimLaneHeight,
                                                    errorBuilder: (_, __, ___) =>
                                                        ColoredBox(color: scheme.surfaceContainerHighest),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      Positioned(
                                        top: trimTop + 20,
                                        left: 0,
                                        width: contentWidth,
                                        child: Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),

                                    // Trim selection — a clean filmstrip
                                    // with the EXCLUDED portions dimmed
                                    // (not a filled block over the
                                    // selected one — that read as a
                                    // permanent colored rectangle sitting
                                    // on top of the thumbnails, not a
                                    // trim control) and a thin bright
                                    // outline around what's kept. Purely
                                    // visual/non-interactive — the two
                                    // edge handles below are the only
                                    // drag surface, so the body of the
                                    // filmstrip stays free for
                                    // scroll-to-scrub.
                                    if (selLeft > 0)
                                      Positioned(
                                        left: 0,
                                        width: selLeft,
                                        top: trimTop,
                                        height: _Timeline._trimLaneHeight,
                                        child: const IgnorePointer(
                                          child: ColoredBox(color: Colors.black54),
                                        ),
                                      ),
                                    if (selLeft + selWidth < contentWidth)
                                      Positioned(
                                        left: selLeft + selWidth,
                                        width: contentWidth - selLeft - selWidth,
                                        top: trimTop,
                                        height: _Timeline._trimLaneHeight,
                                        child: const IgnorePointer(
                                          child: ColoredBox(color: Colors.black54),
                                        ),
                                      ),
                                    Positioned(
                                      left: selLeft,
                                      width: selWidth,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      child: IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(color: scheme.primary, width: 2),
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _edgeHandle(
                                      left: selLeft,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      onDeltaSeconds: (double deltaSec) => widget.onTrimStartChanged(
                                        widget.trimStartSeconds + deltaSec,
                                      ),
                                    ),
                                    _edgeHandle(
                                      left: selLeft + selWidth,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      onDeltaSeconds: (double deltaSec) => widget.onTrimEndChanged(
                                        widget.trimStartSeconds + trimmedSec + deltaSec,
                                      ),
                                    ),

                                    // Speed zones, positioned relative to
                                    // the *original* clip (zone times are
                                    // relative to the trim window's own
                                    // start). Tapping the body asks
                                    // before removing; the edge handles
                                    // resize instead.
                                    for (final SpeedZone zone in widget.speedZones) ...<Widget>[
                                      Positioned(
                                        left: (zone.start.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        width: (zone.end - zone.start).inMilliseconds / 1000.0 * _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveZone(context, zone)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.primary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Text(
                                                  "${zone.factor}x slow-mo",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(zone.start)}–${_Timeline._fmt(zone.end)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: (zone.start.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              zone.start + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > zone.end - _Timeline._minZoneDuration
                                                  ? zone.end - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeZone(
                                            zone,
                                            SpeedZone(start: clamped, end: zone.end, factor: zone.factor),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: (zone.end.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              zone.end + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < zone.start + _Timeline._minZoneDuration
                                                  ? zone.start + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeZone(
                                            zone,
                                            SpeedZone(start: zone.start, end: clamped, factor: zone.factor),
                                          );
                                        },
                                      ),
                                    ],

                                    // Music bar — same shape as a speed
                                    // zone: body taps to remove, edges
                                    // drag to resize its window.
                                    if (music != null && musicLeft != null && musicWidth != null) ...<Widget>[
                                      Positioned(
                                        left: musicLeft,
                                        width: musicWidth,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveMusic(context)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.tertiary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: <Widget>[
                                                    Icon(Icons.music_note, size: 12, color: Colors.white),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      "music",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(musicStart)}–${_Timeline._fmt(musicEnd)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: musicLeft,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              musicStart + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > musicEnd - _Timeline._minZoneDuration
                                                  ? musicEnd - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeMusic(
                                            BackgroundAudio(
                                              filePath: music.filePath,
                                              volume: music.volume,
                                              fadeInDuration: music.fadeInDuration,
                                              fadeOutDuration: music.fadeOutDuration,
                                              startSec: clamped,
                                              duration: musicEnd - clamped,
                                            ),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: musicLeft + musicWidth,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              musicEnd + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < musicStart + _Timeline._minZoneDuration
                                                  ? musicStart + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeMusic(
                                            BackgroundAudio(
                                              filePath: music.filePath,
                                              volume: music.volume,
                                              fadeInDuration: music.fadeInDuration,
                                              fadeOutDuration: music.fadeOutDuration,
                                              startSec: musicStart,
                                              duration: clamped - musicStart,
                                            ),
                                          );
                                        },
                                      ),
                                    ],

                                    // Overlay markers — a labeled chip
                                    // (the actual text, or "sticker"),
                                    // sized/positioned by real duration,
                                    // and allocated to a row (see
                                    // _packOverlayRows) so overlapping
                                    // layers don't collide visually.
                                    for (final VideoOverlay overlay in widget.overlays) ...<Widget>[
                                      Positioned(
                                        left: (overlay.startSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        // Real bug found via user report: an
                                        // upper clamp here (220px) meant the
                                        // visual chip stopped short of the
                                        // overlay's actual duration for
                                        // anything longer than ~3.1s, while
                                        // the right _edgeHandle below is
                                        // (correctly) positioned at the
                                        // TRUE, unclamped endSec — so the
                                        // drag handle appeared detached, far
                                        // to the right of the chip it was
                                        // supposed to belong to. Only a
                                        // lower clamp remains (so a very
                                        // short overlay still has a visible/
                                        // tappable chip), matching how speed
                                        // zones already render unclamped.
                                        width: max(
                                          40.0,
                                          overlay.duration.inMilliseconds / 1000.0 * _pixelsPerSecond,
                                        ),
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveOverlay(context, overlay)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.secondary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: <Widget>[
                                                    Icon(
                                                      overlay is TextOverlay
                                                          ? Icons.text_fields
                                                          : Icons.emoji_emotions_outlined,
                                                      size: 12,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 2),
                                                    Flexible(
                                                      child: Text(
                                                        overlay is TextOverlay ? overlay.text : "sticker",
                                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(overlay.startSec)}–${_Timeline._fmt(overlay.endSec)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: (overlay.startSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              overlay.startSec + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > overlay.endSec - _Timeline._minZoneDuration
                                                  ? overlay.endSec - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeOverlay(
                                            overlay,
                                            _withOverlayTiming(overlay, clamped, overlay.endSec - clamped),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: (overlay.endSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              overlay.endSec + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < overlay.startSec + _Timeline._minZoneDuration
                                                  ? overlay.startSec + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeOverlay(
                                            overlay,
                                            _withOverlayTiming(
                                              overlay,
                                              overlay.startSec,
                                              clamped - overlay.startSec,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Fixed left-anchored playhead — outside the
                          // scrollable content, so it's the timeline that
                          // moves underneath it, not the other way
                          // around. Per direct user feedback, moved from
                          // the timeline's horizontal center to a small
                          // fixed offset from the left (see
                          // TimelineGeometry.playheadOffset) so the
                          // timeline reads left-to-right, starting from
                          // the left, instead of centered with a wide
                          // empty margin on either side.
                          Positioned(
                            left: TimelineGeometry.playheadOffset - 1,
                            top: 0,
                            height: totalHeight,
                            child: const IgnorePointer(
                              child: ColoredBox(
                                color: Colors.redAccent,
                                child: SizedBox(width: 2, height: double.infinity),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds [overlay] with a new [start]/[duration], preserving every
/// other field — a plain top-level function rather than a method on the
/// sealed [VideoOverlay] hierarchy itself, since the domain model
/// (`video_project.dart`) is deliberately kept free of anything
/// UI-specific and this is only ever called from the timeline's resize
/// handles.
VideoOverlay _withOverlayTiming(VideoOverlay overlay, Duration start, Duration duration) {
  return switch (overlay) {
    TextOverlay() => TextOverlay(
        id: overlay.id,
        xPercent: overlay.xPercent,
        yPercent: overlay.yPercent,
        startSec: start,
        duration: duration,
        text: overlay.text,
        argbColor: overlay.argbColor,
        fontSize: overlay.fontSize,
        fontFamily: overlay.fontFamily,
        animation: overlay.animation,
        opacity: overlay.opacity,
        hasOutline: overlay.hasOutline,
        hasShadow: overlay.hasShadow,
        hasBackground: overlay.hasBackground,
      ),
    ImageOverlay() => ImageOverlay(
        id: overlay.id,
        xPercent: overlay.xPercent,
        yPercent: overlay.yPercent,
        startSec: start,
        duration: duration,
        assetPath: overlay.assetPath,
        widthPercent: overlay.widthPercent,
        rotationDegrees: overlay.rotationDegrees,
      ),
  };
}

class _LaneLabel extends StatelessWidget {
  const _LaneLabel(this.text, this.scheme);
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _OverlayPreview extends StatelessWidget {
  const _OverlayPreview({required this.overlay, required this.previewWidth, required this.localLayerTime});

  final VideoOverlay overlay;
  final double previewWidth;

  /// How far into this overlay's own local timeline the preview
  /// currently is — `EditorTransport.localLayerTimeAt`'s own output,
  /// always `>= 0` and reproducible for a given (overlay, transport
  /// time) pair regardless of play/seek/scrub/replay. Only meaningful
  /// for [TextOverlay]'s entrance animation right now.
  final Duration localLayerTime;

  /// Matches `VideoFilterGraphBuilder._animDuration`/`_popInFontsizeExpr`'s
  /// own 0.35s/0.25s ramps exactly, so what's previewed here is the same
  /// timing the actual export produces — not just a plausible
  /// approximation.
  static const double _slideInDuration = 0.35;
  static const double _popInDuration = 0.25;

  @override
  Widget build(BuildContext context) {
    return switch (overlay) {
      final TextOverlay text => _buildText(text),
      ImageOverlay(:final String assetPath, :final double widthPercent, :final double rotationDegrees) =>
        Transform.rotate(
          angle: rotationDegrees * pi / 180,
          child: SizedBox(width: previewWidth * widthPercent, child: Image.file(File(assetPath))),
        ),
    };
  }

  Widget _buildText(TextOverlay text) {
    final double localSeconds = localLayerTime.inMilliseconds / 1000.0;

    double fontSize = text.fontSize;
    double slideOffsetX = 0;
    switch (text.animation) {
      case TextAnimation.none:
        break;
      case TextAnimation.slideIn:
        // Off-screen-right (the full preview width, matching the
        // export's own `w` frame-width reference) at progress=0,
        // target position at progress=1.
        final double progress = (localSeconds / _slideInDuration).clamp(0.0, 1.0);
        slideOffsetX = previewWidth * (1 - progress);
      case TextAnimation.popIn:
        final double progress = (localSeconds / _popInDuration).clamp(0.0, 1.0);
        fontSize = text.fontSize * (0.4 + 0.6 * progress);
    }

    final Widget content = Opacity(
      opacity: text.opacity,
      child: Container(
        padding: text.hasBackground ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
        decoration: text.hasBackground
            ? BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4))
            : null,
        child: Text(
          text.text,
          style: TextStyle(
            color: Color(text.argbColor),
            fontSize: fontSize,
            fontFamily: text.fontFamily.flutterFamily,
            fontWeight: FontWeight.bold,
            shadows: <Shadow>[
              if (text.hasOutline)
                for (final Offset o in const <Offset>[
                  Offset(-1, -1),
                  Offset(1, -1),
                  Offset(-1, 1),
                  Offset(1, 1),
                ])
                  Shadow(color: Colors.black87, offset: o),
              if (text.hasShadow) const Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 3),
            ],
          ),
        ),
      ),
    );

    return slideOffsetX == 0 ? content : Transform.translate(offset: Offset(slideOffsetX, 0), child: content);
  }
}

final class _TimeRange {
  const _TimeRange({required this.start, required this.end});
  final Duration start;
  final Duration end;
}

/// What the sticker picker returned: a preset symbol, or "go pick a real
/// image from the gallery instead."
sealed class _StickerChoice {
  const _StickerChoice();
}

final class _StickerSymbolChoice extends _StickerChoice {
  const _StickerSymbolChoice(this.symbol, this.fontSize);
  final String symbol;
  final double fontSize;
}

final class _StickerGalleryChoice extends _StickerChoice {
  const _StickerGalleryChoice();
}

/// Preset sticker glyphs, rendered through the same drawtext/font
/// pipeline as a text overlay (not a new image-compositing path) — kept
/// to plain symbol characters within Roboto's own glyph coverage rather
/// than color emoji, which a bundled non-emoji TTF can't render (a
/// missing-glyph is a soft failure — the symbol just doesn't draw — but
/// a whole category of stickers that silently don't render would be a
/// worse experience than not offering it; a real emoji/reaction category
/// needs either image sprites or accepting that render risk, not
/// pretending plain symbols are equivalent).
const List<String> _stickerGraphics = <String>["★", "♥", "✓", "✗", "➤", "‼", "●", "▲", "✦", "☆"];

/// AdGag's own "everything is an ad" bit (CLAUDE.md sections 1/2) as a
/// curated sticker set — the ad-commerce parody vocabulary the whole
/// product's tone is built on, not a generic sticker pack.
const List<String> _stickerAdParody = <String>[
  "SALE", "NEW!", "WOW!", "HOT", "SOLD", "LIMITED", "99%", "BUY IT", "BUT WAIT!", "BEST EVER",
];

class _StickerPickerDialog extends StatelessWidget {
  const _StickerPickerDialog();

  Widget _grid(BuildContext context, List<String> items, double fontSize) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: <Widget>[
        for (final String item in items)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => Navigator.of(context).pop(_StickerSymbolChoice(item, fontSize)),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: Text(
                item,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fontSize > 40 ? 28 : 13, fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add a sticker"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Ad parody", style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              _grid(context, _stickerAdParody, 28),
              const SizedBox(height: AppSpacing.md),
              Text("Graphics", style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              _grid(context, _stickerGraphics, 64),
              const Divider(height: AppSpacing.xl),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const _StickerGalleryChoice()),
                icon: const Icon(Icons.image_outlined),
                label: const Text("Choose an image from gallery instead"),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
      ],
    );
  }
}

class _TimeRangeDialog extends StatefulWidget {
  const _TimeRangeDialog({required this.maxDuration});
  final Duration maxDuration;

  @override
  State<_TimeRangeDialog> createState() => _TimeRangeDialogState();
}

class _TimeRangeDialogState extends State<_TimeRangeDialog> {
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    return AlertDialog(
      title: const Text("When should this show?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
          RangeSlider(
            values: RangeValues(_start, _end),
            max: maxSec,
            onChanged: (RangeValues v) => setState(() {
              _start = v.start;
              _end = v.end;
            }),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _TimeRange(
              start: Duration(milliseconds: (_start * 1000).round()),
              end: Duration(milliseconds: (_end * 1000).round()),
            ),
          ),
          child: const Text("OK"),
        ),
      ],
    );
  }
}

class _SpeedZoneDialog extends StatefulWidget {
  const _SpeedZoneDialog({required this.maxDuration});
  final Duration maxDuration;

  @override
  State<_SpeedZoneDialog> createState() => _SpeedZoneDialogState();
}

class _SpeedZoneDialogState extends State<_SpeedZoneDialog> {
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;
  double _factor = 0.5;

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    return AlertDialog(
      title: const Text("Speed zone"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
          RangeSlider(
            values: RangeValues(_start, _end),
            max: maxSec,
            onChanged: (RangeValues v) => setState(() {
              _start = v.start;
              _end = v.end;
            }),
          ),
          Text("Speed: ${_factor.toStringAsFixed(2)}x${_factor < 1 ? ' (slow motion)' : ''}"),
          Slider(
            value: _factor,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            onChanged: (double v) => setState(() => _factor = v),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            SpeedZone(
              start: Duration(milliseconds: (_start * 1000).round()),
              end: Duration(milliseconds: (_end * 1000).round()),
              factor: _factor,
            ),
          ),
          child: const Text("Add"),
        ),
      ],
    );
  }
}

class _TextOverlaySheet extends StatefulWidget {
  const _TextOverlaySheet({required this.id, required this.maxDuration});
  final String id;
  final Duration maxDuration;

  @override
  State<_TextOverlaySheet> createState() => _TextOverlaySheetState();
}

class _TextStyle {
  const _TextStyle(this.label, this.fontSize, this.argbColor, this.weight);
  final String label;
  final double fontSize;
  final int argbColor;
  final FontWeight weight;
}

const List<_TextStyle> _textStyles = <_TextStyle>[
  _TextStyle("Bold", 32, 0xFFFFFFFF, FontWeight.w900),
  _TextStyle("Classic", 26, 0xFFFFFFFF, FontWeight.w600),
  _TextStyle("Big", 44, 0xFFFFFFFF, FontWeight.w800),
  _TextStyle("Yellow", 30, 0xFFFFD400, FontWeight.w800),
  _TextStyle("Pink", 30, 0xFFFF2D8C, FontWeight.w800),
  _TextStyle("Small", 20, 0xFFFFFFFF, FontWeight.w600),
];

class _TextOverlaySheetState extends State<_TextOverlaySheet> {
  final TextEditingController _textController = TextEditingController();
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;
  int _styleIndex = 0;
  TextFontFamily _fontFamily = TextFontFamily.classic;
  TextAnimation _animation = TextAnimation.none;
  double _opacity = 1.0;
  bool _hasOutline = false;
  bool _hasShadow = false;
  bool _hasBackground = false;

  @override
  void initState() {
    super.initState();
    // The Add button's enabled state depends on this text — without a
    // listener the button never rebuilds when the user types, and only
    // seemed to "unstick" when something else (the range slider)
    // happened to trigger a setState first.
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    final _TextStyle style = _textStyles[_styleIndex];
    // BUG 6 fix: was a centered AlertDialog, which on a real device
    // (unlike this dev environment's own checking) rendered invisible —
    // tapping Text dimmed the screen with no visible form. A
    // scroll-controlled bottom sheet is the robust, standard Flutter
    // pattern for a tall form that opens the keyboard immediately
    // (autofocus:true below): it explicitly pads for the keyboard inset
    // and caps its own height, rather than relying on AlertDialog's
    // brittle intrinsic sizing under those conditions.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text("Add text", style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(controller: _textController, autofocus: true, maxLength: 60),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              color: Colors.black,
              alignment: Alignment.center,
              child: Opacity(
                opacity: _opacity,
                child: Container(
                  padding: _hasBackground ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
                  decoration: _hasBackground
                      ? BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Text(
                    _textController.text.isEmpty ? "Preview" : _textController.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(style.argbColor),
                      fontSize: style.fontSize,
                      fontWeight: style.weight,
                      fontFamily: _fontFamily.flutterFamily,
                      shadows: <Shadow>[
                        if (_hasOutline)
                          for (final Offset o in const <Offset>[
                            Offset(-1, -1),
                            Offset(1, -1),
                            Offset(-1, 1),
                            Offset(1, 1),
                          ])
                            Shadow(color: Colors.black87, offset: o),
                        if (_hasShadow) const Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Font", style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: TextFontFamily.values.length,
                itemBuilder: (BuildContext context, int i) {
                  final TextFontFamily family = TextFontFamily.values[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(family.displayName, style: TextStyle(fontFamily: family.flutterFamily)),
                      selected: _fontFamily == family,
                      onSelected: (_) => setState(() => _fontFamily = family),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Style", style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                FilterChip(
                  label: const Text("Outline"),
                  selected: _hasOutline,
                  onSelected: (bool v) => setState(() => _hasOutline = v),
                ),
                FilterChip(
                  label: const Text("Shadow"),
                  selected: _hasShadow,
                  onSelected: (bool v) => setState(() => _hasShadow = v),
                ),
                FilterChip(
                  label: const Text("Background"),
                  selected: _hasBackground,
                  onSelected: (bool v) => setState(() => _hasBackground = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Opacity: ${(_opacity * 100).round()}%"),
            Slider(
              value: _opacity,
              min: 0.2,
              max: 1.0,
              onChanged: (double v) => setState(() => _opacity = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _textStyles.length,
                itemBuilder: (BuildContext context, int i) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(_textStyles[i].label),
                    selected: _styleIndex == i,
                    onSelected: (_) => setState(() => _styleIndex = i),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Entrance effect", style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                for (final TextAnimation anim in TextAnimation.values)
                  ChoiceChip(
                    label: Text(
                      switch (anim) {
                        TextAnimation.none => "None",
                        TextAnimation.slideIn => "Slide in",
                        TextAnimation.popIn => "Pop in",
                      },
                    ),
                    selected: _animation == anim,
                    onSelected: (_) => setState(() => _animation = anim),
                  ),
              ],
            ),
                    const SizedBox(height: AppSpacing.sm),
                    Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
                    RangeSlider(
                      values: RangeValues(_start, _end),
                      max: maxSec,
                      onChanged: (RangeValues v) => setState(() {
                        _start = v.start;
                        _end = v.end;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _textController.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                              TextOverlay(
                                id: widget.id,
                                xPercent: 0.1,
                                yPercent: 0.1,
                                startSec: Duration(milliseconds: (_start * 1000).round()),
                                duration: Duration(milliseconds: ((_end - _start) * 1000).round()),
                                text: _textController.text.trim(),
                                argbColor: style.argbColor,
                                fontSize: style.fontSize,
                                fontFamily: _fontFamily,
                                animation: _animation,
                                opacity: _opacity,
                                hasOutline: _hasOutline,
                                hasShadow: _hasShadow,
                                hasBackground: _hasBackground,
                              ),
                            ),
                    child: const Text("Add"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundAudioDialog extends StatefulWidget {
  const _BackgroundAudioDialog({
    required this.filePath,
    required this.maxDuration,
    required this.audioDuration,
  });
  final String filePath;
  final Duration maxDuration;

  /// The picked audio file's own real, probed duration — used to clamp
  /// the resulting [BackgroundAudio.duration] so playback is never
  /// asked to seek past what the file actually contains (see
  /// `_pickMusic`'s own doc comment on the bug this fixes).
  final Duration audioDuration;

  @override
  State<_BackgroundAudioDialog> createState() => _BackgroundAudioDialogState();
}

class _BackgroundAudioDialogState extends State<_BackgroundAudioDialog> {
  double _volume = 0.5;
  double _fadeIn = 1.0;
  double _fadeOut = 1.0;

  @override
  Widget build(BuildContext context) {
    final double maxFade = (widget.maxDuration.inMilliseconds / 1000.0).clamp(0, 5);
    final double detectedSec = widget.audioDuration.inMilliseconds / 1000.0;
    final double usedSec =
        (widget.audioDuration < widget.maxDuration ? widget.audioDuration : widget.maxDuration).inMilliseconds /
            1000.0;
    return AlertDialog(
      title: const Text("Background music"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Directly surfaces what the app detected as the file's own
          // length (not just what gets used after clamping to the clip)
          // — real user reports of music cutting out early are otherwise
          // impossible to distinguish from "the detected length was
          // wrong" without this being visible up front.
          Text(
            "Detected length: ${detectedSec.toStringAsFixed(1)}s"
            "${usedSec < detectedSec ? " (using first ${usedSec.toStringAsFixed(1)}s to fit the clip)" : ""}",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text("Volume: ${(_volume * 100).round()}%"),
          Slider(value: _volume, onChanged: (double v) => setState(() => _volume = v)),
          Text("Fade in: ${_fadeIn.toStringAsFixed(1)}s"),
          Slider(value: _fadeIn, max: maxFade, onChanged: (double v) => setState(() => _fadeIn = v)),
          Text("Fade out: ${_fadeOut.toStringAsFixed(1)}s"),
          Slider(value: _fadeOut, max: maxFade, onChanged: (double v) => setState(() => _fadeOut = v)),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            BackgroundAudio(
              filePath: widget.filePath,
              volume: _volume,
              fadeInDuration: Duration(milliseconds: (_fadeIn * 1000).round()),
              fadeOutDuration: Duration(milliseconds: (_fadeOut * 1000).round()),
              duration: widget.audioDuration < widget.maxDuration ? widget.audioDuration : widget.maxDuration,
            ),
          ),
          child: const Text("Add"),
        ),
      ],
    );
  }
}

extension on AppColorFilter {
  String get label => switch (this) {
        AppColorFilter.none => "Original",
        AppColorFilter.warm => "Warm",
        AppColorFilter.cool => "Cool",
        AppColorFilter.blackAndWhite => "Mono",
        AppColorFilter.vintage => "Vintage",
        AppColorFilter.vivid => "Vivid",
        AppColorFilter.dramatic => "Dramatic",
      };

  /// A `ColorFilter.matrix` approximation of the FFmpeg `eq`/`hue` filter
  /// [VideoFilterGraphBuilder] applies for real at render time — close
  /// enough that what's previewed here matches what gets published,
  /// without needing to round-trip through FFmpeg just to preview a
  /// color grade.
  ColorFilter get previewFilter => switch (this) {
        AppColorFilter.none => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, 0, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.warm => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, 24, //
            0, 1, 0, 0, 6, //
            0, 0, 1, 0, -18, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.cool => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, -18, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 24, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.blackAndWhite => const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.vintage => const ColorFilter.matrix(<double>[
            0.9, 0.1, 0.0, 0, 10, //
            0.05, 0.85, 0.05, 0, 4, //
            0.05, 0.1, 0.75, 0, -6, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.vivid => const ColorFilter.matrix(<double>[
            1.35, -0.32, -0.03, 0, 0, //
            -0.10, 1.13, -0.03, 0, 0, //
            -0.10, -0.32, 1.42, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.dramatic => const ColorFilter.matrix(<double>[
            1.25, -0.05, -0.02, 0, -25, //
            -0.05, 1.2, -0.02, 0, -25, //
            -0.02, -0.05, 1.15, 0, -30, //
            0, 0, 0, 1, 0, //
          ]),
      };
}

extension on AppVideoRotation {
  int get value => switch (this) {
        AppVideoRotation.none => 0,
        AppVideoRotation.degrees90 => 90,
        AppVideoRotation.degrees180 => 180,
        AppVideoRotation.degrees270 => 270,
      };

  int get quarterTurns => switch (this) {
        AppVideoRotation.none => 0,
        AppVideoRotation.degrees90 => 1,
        AppVideoRotation.degrees180 => 2,
        AppVideoRotation.degrees270 => 3,
      };
}
