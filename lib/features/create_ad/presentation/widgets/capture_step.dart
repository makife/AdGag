import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../providers/create_ad_flow_controller.dart";
import "camera_record_view.dart";

/// "record/import video" (CLAUDE.md section 38). Reuses
/// [CreateAdFlowController.onVideoCaptured] regardless of source, so
/// record vs. import never forks into separate downstream logic.
class CaptureStep extends ConsumerStatefulWidget {
  const CaptureStep({super.key});

  @override
  ConsumerState<CaptureStep> createState() => _CaptureStepState();
}

class _CaptureStepState extends ConsumerState<CaptureStep> {
  bool _busy = false;
  String? _error;

  Future<void> _record() async {
    final (String, Duration)? result = await Navigator.of(context).push<(String, Duration)>(
      MaterialPageRoute<(String, Duration)>(
        builder: (BuildContext routeContext) => CameraRecordView(
          onRecorded: (String path, Duration duration) {
            Navigator.of(routeContext).pop((path, duration));
          },
        ),
      ),
    );

    if (result != null) {
      final LocalVideoDraft draft = LocalVideoDraft(filePath: result.$1, duration: result.$2);
      ref.read(createAdFlowControllerProvider.notifier).onVideoCaptured(draft);
    }
  }

  Future<void> _importFromGallery() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile? file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: VideoConstraints.max,
      );
      if (file == null) {
        return; // user cancelled
      }
      final Duration duration = await ref.read(localVideoProberProvider).probeDuration(file.path);
      final LocalVideoDraft draft = LocalVideoDraft(filePath: file.path, duration: duration);
      ref.read(createAdFlowControllerProvider.notifier).onVideoCaptured(draft);
    } catch (e) {
      setState(() => _error = "Couldn't import that video: $e");
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Record or import")),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_error != null) ...<Widget>[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: AppSpacing.lg),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _record,
              icon: const Icon(Icons.videocam),
              label: const Text("Record"),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text("Import from gallery"),
            ),
          ],
        ),
      ),
    );
  }
}
