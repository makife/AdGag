import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/media/native_editor_bridge.dart";
import "../../domain/local_video_draft.dart";
import "../providers/create_ad_flow_controller.dart";

/// The real (only) editing entry point: opens the native editor
/// (`NativeEditorActivity` on Android, Swift/AVFoundation on iOS) the
/// instant this step is reached. See `native_editor_bridge.dart`'s own
/// doc comment for why editing is entirely native — there is no
/// Flutter-side editor to fall back to anymore.
///
/// This screen itself is just a thin launcher + loading/error state —
/// all the actual editing UI lives in the native Activity. If the
/// native editor fails (a real, caught, surfaced crash — not silence,
/// see `NativeEditorActivity`'s own uncaught-exception handling), this
/// screen shows the real error with a Retry.
class NativeEditorStep extends ConsumerStatefulWidget {
  const NativeEditorStep({super.key});

  @override
  ConsumerState<NativeEditorStep> createState() => _NativeEditorStepState();
}

class _NativeEditorStepState extends ConsumerState<NativeEditorStep> {
  String? _error;
  bool _launching = true;
  bool _isCrashLogFromLastAttempt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkForLeftoverCrashThenOpen()));
  }

  /// A hard native crash (see `native_editor_bridge.dart`'s own doc
  /// comment on `readAndClearDebugLog`) kills the whole app process —
  /// there is no live Dart callback to catch it, only a checkpoint log
  /// written to disk that survives the crash and can be read back the
  /// NEXT time this screen is reached. Checked first, before attempting
  /// to auto-launch the native editor again, so a real crash trace is
  /// never silently lost.
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
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _launching = true;
      _error = null;
      _isCrashLogFromLastAttempt = false;
    });
    try {
      final NativeEditorResult? result = await NativeEditorBridge.openEditor(draft.filePath);
      if (!mounted) {
        return;
      }
      if (result == null) {
        // User backed out of the native editor without exporting —
        // matches Retake, not an error.
        ref.read(createAdFlowControllerProvider.notifier).retake();
        return;
      }
      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(
            LocalVideoDraft(filePath: result.filePath, duration: Duration(milliseconds: result.durationMs)),
          );
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
    final String? error = _error;
    return Scaffold(
      body: SafeArea(
        child: error != null
            // Real layout bug found via user report/screenshot
            // ("BOTTOM OVERFLOWED BY 11785 PIXELS"): a long checkpoint
            // log (accumulated across several trim/seek edits in a
            // normal session) genuinely overflowed the old
            // Center+Column layout, which had no scroll container at
            // all — pushing Retry off-screen and making this error
            // state effectively untappable. The icon/title/Retry now
            // stay fixed; only the log text itself scrolls, in the
            // space actually available, however long it is.
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
                    FilledButton(onPressed: () => unawaited(_open()), child: const Text("Retry")),
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
