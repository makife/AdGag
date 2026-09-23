import "dart:async";

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";

import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/video_constraints.dart";

/// Fullscreen record UI communicating the 10s limit clearly (CLAUDE.md
/// section 4). Tap to start, tap again (or auto-stop at 10s) to finish.
/// Recordings shorter than [VideoConstraints.min] are discarded with a
/// message rather than silently accepted, since a sub-1.5s clip is very
/// likely an accidental tap, not an intentional Ad.
///
/// NOTE: this is the least verifiable file in the codebase — camera
/// lifecycle behavior can only really be confirmed on a physical device,
/// which isn't available in this environment. Test this screen first and
/// carefully once Flutter is installed.
class CameraRecordView extends StatefulWidget {
  const CameraRecordView({required this.onRecorded, super.key});

  final void Function(String filePath, Duration duration) onRecorded;

  @override
  State<CameraRecordView> createState() => _CameraRecordViewState();
}

class _CameraRecordViewState extends State<CameraRecordView> {
  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _controller;
  Timer? _tick;
  DateTime? _recordingStartedAt;
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _switchingCamera = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_setUp());
  }

  Future<void> _setUp() async {
    final PermissionStatus cameraStatus = await Permission.camera.request();
    final PermissionStatus micStatus = await Permission.microphone.request();
    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() => _error = "Camera and microphone permission are required to record.");
      return;
    }

    try {
      final List<CameraDescription> cameras = await availableCameras();
      _cameras = cameras;
      final CameraDescription description = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _openCamera(description);
    } catch (e) {
      setState(() => _error = "Couldn't start the camera: $e");
    }
  }

  Future<void> _openCamera(CameraDescription description) async {
    final CameraController controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// Switches between front and back cameras (CLAUDE.md section 4 doesn't
  /// specify this explicitly, but every camera-first creation flow needs
  /// it — "advertise yourself" is one of the platform's core examples,
  /// which needs a front-facing camera).
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording || _switchingCamera) {
      return;
    }
    final CameraController? current = _controller;
    if (current == null) {
      return;
    }
    setState(() => _switchingCamera = true);
    final CameraLensDirection nextDirection =
        current.description.lensDirection == CameraLensDirection.back
            ? CameraLensDirection.front
            : CameraLensDirection.back;
    final CameraDescription next = _cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == nextDirection,
      orElse: () => _cameras.first,
    );
    await current.dispose();
    try {
      await _openCamera(next);
    } catch (e) {
      setState(() => _error = "Couldn't switch camera: $e");
    } finally {
      if (mounted) {
        setState(() => _switchingCamera = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (_isRecording) {
      await _stopRecording();
      return;
    }

    await controller.startVideoRecording();
    _recordingStartedAt = DateTime.now();
    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });

    _tick = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      final DateTime? startedAt = _recordingStartedAt;
      if (startedAt == null) {
        return;
      }
      final Duration elapsed = DateTime.now().difference(startedAt);
      setState(() => _elapsed = elapsed);
      if (elapsed >= VideoConstraints.max) {
        unawaited(_stopRecording());
      }
    });
  }

  Future<void> _stopRecording() async {
    _tick?.cancel();
    _tick = null;
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      setState(() => _isRecording = false);
      return;
    }

    final XFile file = await controller.stopVideoRecording();
    final Duration duration = _elapsed;
    setState(() => _isRecording = false);

    if (duration < VideoConstraints.min) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Too short — hold on a little longer.")),
        );
      }
      return;
    }

    widget.onRecorded(file.path, duration);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _controller?.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: AppColors.darkBackground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: AppColors.darkBackground,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final double progress = _elapsed.inMilliseconds / VideoConstraints.max.inMilliseconds;

    return ColoredBox(
      color: AppColors.darkBackground,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CameraPreview(controller),
          if (_cameras.length > 1)
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: SafeArea(
                child: GestureDetector(
                  onTap: (_isRecording || _switchingCamera) ? null : _switchCamera,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                    child: const Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: AppSpacing.xxxl + MediaQuery.paddingOf(context).bottom,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  "${(_elapsed.inMilliseconds / 1000.0).toStringAsFixed(1)}s / ${VideoConstraints.max.inSeconds}s",
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.md),
                GestureDetector(
                  onTap: _toggleRecording,
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: _isRecording ? progress.clamp(0, 1) : 0,
                          strokeWidth: 4,
                          color: AppColors.sold,
                          backgroundColor: Colors.white24,
                        ),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                            borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                            color: AppColors.sold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
