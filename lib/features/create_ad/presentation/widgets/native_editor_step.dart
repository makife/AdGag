import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";

import "../../../../core/media/native_editor_bridge.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../providers/create_ad_flow_controller.dart";
import "camera_record_view.dart";

/// The real (only) editing entry point: opens the native editor
/// (`NativeEditorActivity` on Android, Swift/AVFoundation on iOS) the
/// instant this step is reached. See `native_editor_bridge.dart` for why
/// editing is entirely native.
///
/// Besides launching, this screen hosts the "record another clip" round
/// trip: the timeline's "+" closes the native editor with its session
/// state, this screen shows the camera (limited to the time left of the
/// 30s cap, with a Cancel button), then reopens the editor with that
/// state plus the new clip — or without one, if the user cancelled.
class NativeEditorStep extends ConsumerStatefulWidget {
  const NativeEditorStep({super.key});

  @override
  ConsumerState<NativeEditorStep> createState() => _NativeEditorStepState();
}

class _NativeEditorStepState extends ConsumerState<NativeEditorStep> {
  String? _error;
  bool _launching = true;
  bool _isCrashLogFromLastAttempt = false;

  /// Set while recording an extra clip: the editor session to resume, and
  /// how long the new take may be.
  String? _resumeState;
  Duration? _extraClipMax;

  /// Bumped to rebuild the camera from scratch (e.g. after the gallery
  /// picker was cancelled — the camera was released before opening it).
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkForLeftoverCrashThenOpen()));
  }

  /// A hard native crash kills the whole app process — only a checkpoint
  /// log written to disk survives, read back here the NEXT time this
  /// screen is reached, before auto-launching the editor again.
  Future<void> _checkForLeftoverCrashThenOpen() async {
    final String? leftoverLog = await NativeEditorBridge.readAndClearDebugLog();
    if (!mounted) {
      return;
    }
    if (leftoverLog != null) {
      setState(() {
        _error = leftoverLog;
        _isCrashLogFromLastAttempt = true;
        _launching = false;
      });
      return;
    }
    unawaited(_open());
  }

  Future<void> _open() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    await _run(() => NativeEditorBridge.openEditor(videoPath: draft.filePath, rotationDegrees: draft.rotationDegrees));
  }

  /// Reopens the editor with the saved session, appending [newClipPath] if a take was recorded.
  Future<void> _resume({String? newClipPath}) async {
    final String? state = _resumeState;
    if (state == null) {
      return unawaited(_open());
    }
    await _run(() => NativeEditorBridge.openEditor(state: state, newClipPath: newClipPath));
  }

  /// The "+" take from the gallery instead of the camera. Any length is
  /// fine — the native editor trims it to the time that's left.
  Future<void> _pickExtraFromGallery() async {
    try {
      final XFile? file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (!mounted) {
        return;
      }
      if (file != null) {
        await _resume(newClipPath: file.path);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't import that video: $e")));
      }
    }
    // Cancelled or failed: back to the camera (a fresh one).
    if (mounted) {
      setState(() => _cameraGeneration++);
    }
  }

  Future<void> _run(Future<NativeEditorOutcome?> Function() launch) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _launching = true;
      _error = null;
      _isCrashLogFromLastAttempt = false;
      _extraClipMax = null;
    });
    try {
      final NativeEditorOutcome? outcome = await launch();
      if (!mounted) {
        return;
      }
      switch (outcome) {
        case null:
          // Backed out of the editor without exporting — like Retake.
          ref.read(createAdFlowControllerProvider.notifier).retake();
        case NativeEditorExported(:final String filePath, :final int durationMs):
          ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(
                LocalVideoDraft(filePath: filePath, duration: Duration(milliseconds: durationMs)),
              );
        case NativeEditorAddClipRequested(:final String state, :final int remainingMs):
          setState(() {
            _resumeState = state;
            _extraClipMax = Duration(milliseconds: remainingMs.clamp(0, VideoConstraints.max.inMilliseconds));
            _launching = false;
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _launching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Duration? extraClipMax = _extraClipMax;
    if (extraClipMax != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: CameraRecordView(
          key: ValueKey<int>(_cameraGeneration),
          maxDuration: extraClipMax,
          onRecorded: (String filePath, Duration _, int __) => unawaited(_resume(newClipPath: filePath)),
          onCancel: () => unawaited(_resume()),
          onPickFromGallery: () => unawaited(_pickExtraFromGallery()),
        ),
      );
    }

    final String? error = _error;
    return Scaffold(
      body: SafeArea(
        child: error != null
            // Only the log text scrolls, so Retry can never be pushed
            // off-screen by a long checkpoint log.
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _isCrashLogFromLastAttempt
                          ? "The native editor crashed last time — here's the checkpoint log leading up to it"
                          : "Native editor failed",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SelectableText(error, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unawaited(_resumeState != null ? _resume() : _open()),
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              )
            : Center(
                child: _launching ? const CircularProgressIndicator() : const SizedBox.shrink(),
              ),
      ),
    );
  }
}
