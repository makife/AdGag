import "dart:async";
import "dart:io";

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:permission_handler/permission_handler.dart";

import "../../../../core/media/device_orientation_stream.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/video_constraints.dart";

/// Fullscreen record UI communicating the time limit clearly (CLAUDE.md
/// section 4). Tap to start, tap again (or auto-stop at [maxDuration]) to
/// finish. Used both for the first take (up to the full 30s) and for extra
/// takes from the editor timeline's "+" (only the time that's left, with a
/// Cancel button back to the editor).
/// Recordings shorter than [VideoConstraints.min] are discarded with a
/// message rather than silently accepted, since a sub-1.5s clip is very
/// likely an accidental tap, not an intentional Ad.
///
/// NOTE: this is the least verifiable file in the codebase — camera
/// lifecycle behavior can only really be confirmed on a physical device,
/// which isn't available in this environment. Test this screen first and
/// carefully once Flutter is installed.
class CameraRecordView extends StatefulWidget {
  const CameraRecordView({
    required this.onRecorded,
    this.maxDuration = VideoConstraints.max,
    this.onCancel,
    this.onPickFromGallery,
    super.key,
  });

  final void Function(String filePath, Duration duration) onRecorded;

  /// Recording auto-stops here — less than [VideoConstraints.max] for an
  /// extra take, since all takes together share the 30s cap.
  final Duration maxDuration;

  /// When set, a back/cancel button is shown top-left.
  final VoidCallback? onCancel;

  /// When set, a gallery button is shown next to the record button. The
  /// camera is fully released before this is called (the gallery picker
  /// is a separate screen, and the editor that follows needs the codecs).
  final VoidCallback? onPickFromGallery;

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

  /// How the phone is physically held. The UI stays portrait (like the
  /// system camera); a sideways phone records a LANDSCAPE video and the
  /// on-screen controls turn in place to stay upright.
  DeviceOrientation _orientation = DeviceOrientation.portraitUp;
  StreamSubscription<DeviceOrientation>? _orientationSub;

  @override
  void initState() {
    super.initState();
    _orientationSub = physicalDeviceOrientation().listen((DeviceOrientation o) {
      // Frozen while recording: a take keeps the orientation it started with.
      if (mounted && !_isRecording && o != _orientation) {
        setState(() => _orientation = o);
      }
    });
    unawaited(_setUp());
  }

  /// Quarter turns that keep a control upright for the way the phone is held.
  double get _iconTurns => switch (_orientation) {
        DeviceOrientation.landscapeLeft => 0.25,
        DeviceOrientation.landscapeRight => -0.25,
        DeviceOrientation.portraitDown => 0.5,
        DeviceOrientation.portraitUp => 0,
      };

  Widget _upright(Widget child) => AnimatedRotation(
        turns: _iconTurns,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: child,
      );

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
      // Was ResolutionPreset.high (~720p on most devices) — a real,
      // concrete cause of "export looks lower quality than expected":
      // the *source* recording was already well below the phone's own
      // capability before any editing/export ever touched it. veryHigh
      // targets 1080p (this format's documented export target — see
      // VideoFilterGraphBuilder/FfmpegVideoExportService, section 8 of
      // the video-editor spec), which the export pipeline no longer
      // downscales from (see the explicit format=yuv420p fix there —
      // it fixes hardware-encoder compatibility, not resolution, but
      // together the two mean 1080p in reliably means 1080p out).
      ResolutionPreset.veryHigh,
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
    // Null the controller out *before* disposing it — otherwise a build()
    // triggered by this setState (or the dispose() below) renders
    // CameraPreview against an already-disposed controller, which throws
    // a CameraException that isn't caught by the try/catch below (it
    // happens during widget build, not inside the awaited call) and
    // surfaces as Flutter's red error screen.
    setState(() {
      _switchingCamera = true;
      _controller = null;
    });
    final CameraLensDirection nextDirection = current.description.lensDirection == CameraLensDirection.back
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

    // Record in the orientation the phone is physically held in (the camera
    // plugin otherwise follows the UI, which is locked to portrait — a
    // sideways phone then recorded a sideways portrait video). Android only:
    // on iOS the plugin already follows the device.
    if (Platform.isAndroid) {
      try {
        await controller.lockCaptureOrientation(_orientation);
      } catch (_) {
        // Recording in portrait is better than not recording at all.
      }
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
      if (elapsed >= widget.maxDuration) {
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

    // Fully release the camera + recorder BEFORE handing off: the next
    // screen is the native editor, which immediately needs hardware
    // codecs of its own — a still-releasing camera session was one cause
    // of the editor's DECODER_INIT_FAILED / crash-on-open reports.
    await _releaseCamera();
    widget.onRecorded(file.path, duration);
  }

  /// Nulls the controller first (so build() never renders a disposed
  /// one), then awaits its disposal.
  Future<void> _releaseCamera() async {
    final CameraController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (mounted) {
      setState(() => _controller = null);
    } else {
      _controller = null;
    }
    await controller.dispose();
  }

  Future<void> _cancel() async {
    await _releaseCamera();
    widget.onCancel?.call();
  }

  Future<void> _pickFromGallery() async {
    await _releaseCamera();
    widget.onPickFromGallery?.call();
  }

  @override
  void dispose() {
    unawaited(_orientationSub?.cancel());
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                if (widget.onCancel != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: () => unawaited(_cancel()),
                    child: Text(AppLocalizations.of(context).captureCancelExtraClip),
                  ),
                ],
              ],
            ),
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

    final double progress = _elapsed.inMilliseconds / widget.maxDuration.inMilliseconds;

    return ColoredBox(
      color: AppColors.darkBackground,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // CameraPreview stretches to fill whatever box it's given rather
          // than preserving its own aspect ratio — placed directly under
          // StackFit.expand (full-screen, ~9:16) it visibly distorted the
          // image ("ince uzun" — stretched thin and tall). aspectRatio is
          // reported in the sensor's natural (landscape) orientation, so
          // it's inverted here for portrait display — the standard fix for
          // this exact camera-plugin gotcha.
          Center(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
          if (widget.onCancel != null)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: SafeArea(
                child: TextButton.icon(
                  // Disabled mid-recording: stop first, so a take is never
                  // silently thrown away by a stray tap.
                  onPressed: _isRecording ? null : () => unawaited(_cancel()),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black38,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  icon: _upright(const Icon(Icons.arrow_back)),
                  label: Text(AppLocalizations.of(context).captureCancelExtraClip),
                ),
              ),
            ),
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
                    child: _upright(const Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 24)),
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
                _upright(
                  Text(
                    "${(_elapsed.inMilliseconds / 1000.0).toStringAsFixed(1)}s / "
                    "${(widget.maxDuration.inMilliseconds / 1000.0).toStringAsFixed(1)}s",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // Balances the gallery button so the record button stays centered.
                    SizedBox(width: widget.onPickFromGallery != null ? 76 : 0),
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
                    if (widget.onPickFromGallery != null)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xl),
                        child: GestureDetector(
                          onTap: _isRecording ? null : () => unawaited(_pickFromGallery()),
                          child: Opacity(
                            opacity: _isRecording ? 0.4 : 1,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white70),
                              ),
                              child: _upright(const Icon(Icons.photo_library_outlined, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
