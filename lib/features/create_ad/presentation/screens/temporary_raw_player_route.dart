import "dart:async" show unawaited;
import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

/// videoeditor10.txt's proposed standalone-route lifecycle isolation
/// experiment. TEMPORARY diagnostic scaffolding — reached only from
/// TrimStep's debug menu, never part of the normal navigation graph a
/// real user encounters.
///
/// Unlike TrimStep's own "Raw preview mode" (videoeditor9.txt), which
/// stays inside the same still-mounted `TrimStep`/`_TrimStepState`, this
/// is a genuinely separate route: the caller uses
/// `GoRouter.pushReplacement`, which disposes `CreateAdScreen` (and
/// therefore `TrimStep` — its `EditorTransport`, its thumbnail-service
/// reference, its `_Timeline`, everything) *before* this screen is ever
/// built. Nothing related to the editor is alive underneath this
/// screen. The player code itself is intentionally the exact same
/// sequence as `caption_publish_step.dart`: file -> initialize ->
/// setLooping -> play -> bare `AspectRatio(child: VideoPlayer(...))`.
class TemporaryRawPlayerRoute extends StatefulWidget {
  const TemporaryRawPlayerRoute({required this.videoPath, super.key});

  final String videoPath;

  @override
  State<TemporaryRawPlayerRoute> createState() => _TemporaryRawPlayerRouteState();
}

class _TemporaryRawPlayerRouteState extends State<TemporaryRawPlayerRoute> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final VideoPlayerController controller = VideoPlayerController.file(File(widget.videoPath));
    _controller = controller;
    unawaited(
      controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
        unawaited(controller.setLooping(true));
        unawaited(controller.play());
      }),
    );
  }

  @override
  void dispose() {
    _controller?.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      appBar: AppBar(title: const Text("Standalone raw player (debug)")),
      body: SafeArea(
        child: Center(
          child: ready
              ? AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
