import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/media/native_editor_bridge.dart";
import "../../domain/local_video_draft.dart";
import "../providers/create_ad_flow_controller.dart";

/// Real editing entry point on Android: opens the native editor
/// (`NativeEditorActivity`, Kotlin/Media3 CompositionPlayer) as soon as
/// this step is reached, instead of asking the user to find it behind a
/// menu. See `native_editor_bridge.dart`'s own doc comment for why the
/// native editor exists at all.
///
/// This screen itself is just a thin launcher + loading/error state —
/// all the actual editing UI lives in the native Activity. If the
/// native editor fails (a real, caught, surfaced crash — not silence,
/// see `NativeEditorActivity`'s own uncaught-exception handling), this
/// screen shows the real error and offers "Use classic editor instead"
/// so a native-side bug never fully blocks publishing.
class NativeEditorStep extends ConsumerStatefulWidget {
  const NativeEditorStep({super.key});

  @override
  ConsumerState<NativeEditorStep> createState() => _NativeEditorStepState();
}

class _NativeEditorStepState extends ConsumerState<NativeEditorStep> {
  String? _error;
  bool _launching = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  Future<void> _open() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _launching = true;
      _error = null;
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        "Native editor failed",
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // Full raw error text, on screen — no ADB/computer
                      // needed to see why, matching this app's own
                      // established debugging discipline.
                      SelectableText(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 20),
                      FilledButton(onPressed: () => unawaited(_open()), child: const Text("Retry")),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.read(useClassicEditorProvider.notifier).state = true,
                        child: const Text("Use classic editor instead"),
                      ),
                    ],
                  ),
                )
              : (_launching ? const CircularProgressIndicator() : const SizedBox.shrink()),
        ),
      ),
    );
  }
}
