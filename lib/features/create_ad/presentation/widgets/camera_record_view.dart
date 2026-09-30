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
import "../ar/ar_effects.dart";

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

  /// [rotationDegrees]: how far (clockwise) the recording must be turned to
  /// be upright — 90/270 when the phone was held sideways (see
  /// [_rotationForTake]). The editor starts with that rotation.
  final void Function(String filePath, Duration duration, int rotationDegrees) onRecorded;

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

  /// Live AR (Android): how to show the GL-processed preview when the camera
  /// was opened with the AR pipeline (null = normal preview).
  ArPreviewInfo? _arInfo;
  bool _arPickerOpen = false;

  /// How the phone is physically held. The UI stays portrait (like the
  /// system camera) and the on-screen controls turn in place to stay
  /// upright; a take started sideways is handed to the editor with a 90°
  /// rotation, so it comes out as a landscape video.
  DeviceOrientation _orientation = DeviceOrientation.portraitUp;

  /// The orientation the current take was started in (frozen for the take).
  DeviceOrientation _takeOrientation = DeviceOrientation.portraitUp;
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
      setState(() => _error = AppLocalizations.of(context).cameraPermission);
      return;
    }

    try {
      final List<CameraDescription> cameras = await availableCameras();
      _cameras = cameras;
      final CameraDescription description = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _openCameraOrWithoutAr(description);
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context).cameraStartFailed("$e"));
    }
  }

  /// Opens [description]; if that fails with a live AR effect picked, drops
  /// the effect, reopens without it and explains (AR must never cost the
  /// camera). Also notices when the native side already fell back.
  Future<void> _openCameraOrWithoutAr(CameraDescription description) async {
    final bool withAr = Platform.isAndroid && ArCameraBridge.selectedEffect != null;
    try {
      await _openCamera(description);
    } catch (e) {
      if (!withAr) {
        rethrow;
      }
      final String details = "$e\n\n${await ArCameraBridge.lastError() ?? ""}";
      await _releaseCamera();
      ArCameraBridge.selectedEffect = null;
      await _openCamera(description);
      _showArFailure(details);
      return;
    }
    if (withAr && _arInfo == null && !await ArCameraBridge.isPipelineBound()) {
      // The native bind failed and opened the camera without AR.
      final String? details = await ArCameraBridge.lastError();
      await ArCameraBridge.setEffect(null);
      _showArFailure(details);
    }
  }

  void _showArFailure(String? details) {
    if (!mounted) {
      return;
    }
    setState(() {}); // the picker shows "no effect" again
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(AppLocalizations.of(context).arUnavailable),
          content: details == null || details.trim().isEmpty
              ? null
              : SizedBox(
                  height: 280,
                  child: SingleChildScrollView(
                    child: SelectableText(details, style: const TextStyle(fontSize: 11)),
                  ),
                ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context).genericDone)),
          ],
        ),
      ),
    );
  }

  Future<void> _openCamera(CameraDescription description) async {
    // The native side decides at bind time whether this camera gets the AR
    // pipeline: only when an effect is picked.
    if (Platform.isAndroid) {
      try {
        await ArCameraBridge.setEffect(ArCameraBridge.selectedEffect);
      } catch (_) {
        ArCameraBridge.selectedEffect = null; // no AR on this build/device
      }
    }
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
    final ArPreviewInfo? arInfo = await _readArPreviewInfo();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _arInfo = arInfo;
    });
  }

  /// With the AR pipeline bound, CameraX reports the preview buffer's
  /// transform shortly after binding; wait briefly for it.
  Future<ArPreviewInfo?> _readArPreviewInfo() async {
    if (!Platform.isAndroid || ArCameraBridge.selectedEffect == null) {
      return null;
    }
    try {
      if (!await ArCameraBridge.isPipelineBound()) {
        return null;
      }
      for (int i = 0; i < 30; i++) {
        final ArPreviewInfo? info = await ArCameraBridge.previewInfo();
        if (info != null) {
          return info;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } catch (_) {
      // Fall back to the normal preview widget.
    }
    return null;
  }

  /// Picks a live AR effect (null = none). Switching between effects is
  /// instant; turning AR on for a camera opened without it reopens the
  /// camera (the effect has to be part of the camera's setup).
  Future<void> _selectArEffect(String? id) async {
    final CameraController? current = _controller;
    if (current == null || _switchingCamera) {
      return;
    }
    bool bound = false;
    try {
      bound = await ArCameraBridge.isPipelineBound();
      await ArCameraBridge.setEffect(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).arUnavailable)));
      }
      return;
    }
    if (id == null || bound || _isRecording) {
      setState(() {}); // just redraw the picker's selection
      return;
    }
    setState(() {
      _switchingCamera = true;
      _controller = null;
    });
    await current.dispose();
    try {
      await _openCameraOrWithoutAr(current.description);
    } catch (e) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).cameraStartFailed("$e"));
      }
    } finally {
      if (mounted) {
        setState(() => _switchingCamera = false);
      }
    }
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
      await _openCameraOrWithoutAr(next);
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context).cameraSwitchFailed("$e"));
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

    // NOT lockCaptureOrientation: locking the camera to landscape made
    // CameraPreview rotate itself (a stretched preview) and stopping the
    // recording hang (user report). The camera records as the UI is —
    // portrait — and the editor turns a sideways take upright instead.
    _takeOrientation = _orientation;
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
          SnackBar(content: Text(AppLocalizations.of(context).cameraTooShort)),
        );
      }
      return;
    }

    // Fully release the camera + recorder BEFORE handing off: the next
    // screen is the native editor, which immediately needs hardware
    // codecs of its own — a still-releasing camera session was one cause
    // of the editor's DECODER_INIT_FAILED / crash-on-open reports.
    final int rotation = _rotationForTake();
    await _releaseCamera();
    widget.onRecorded(file.path, duration, rotation);
  }

  /// Clockwise degrees that make a take upright. The frame is recorded in
  /// the portrait UI's orientation, so with the phone turned left (its top
  /// pointing left) the world's "up" lies along the frame's right edge:
  /// turn it 270° clockwise. The front camera's recording isn't mirrored,
  /// so its image is left-right swapped relative to the phone — the
  /// opposite turn. Android only (the iOS camera plugin records in the
  /// device orientation itself).
  int _rotationForTake() {
    if (!Platform.isAndroid) {
      return 0;
    }
    final bool front = _controller?.description.lensDirection == CameraLensDirection.front;
    return switch (_takeOrientation) {
      DeviceOrientation.landscapeLeft => front ? 90 : 270,
      DeviceOrientation.landscapeRight => front ? 270 : 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.portraitUp => 0,
    };
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

  /// The camera preview. With the AR pipeline the texture is a GL-processed
  /// buffer: it's turned/mirrored exactly as CameraX reports ([_arInfo]),
  /// instead of by the plugin's rotation logic (made for the camera's own
  /// buffers — it would turn this one sideways).
  Widget _preview(CameraController controller) {
    final ArPreviewInfo? ar = _arInfo;
    if (ar == null || ar.hasCameraTransform) {
      // aspectRatio is reported in the sensor's natural (landscape)
      // orientation, so it's inverted for the portrait UI — without an
      // AspectRatio CameraPreview stretches to fill its box.
      return AspectRatio(aspectRatio: 1 / controller.value.aspectRatio, child: CameraPreview(controller));
    }
    final bool quarter = (ar.rotationDegrees ~/ 90).isOdd;
    Widget view = AspectRatio(
      aspectRatio: ar.width / ar.height,
      child: Texture(textureId: controller.cameraId),
    );
    view = RotatedBox(quarterTurns: (ar.rotationDegrees ~/ 90) % 4, child: view);
    if (ar.mirroring) {
      view = Transform.flip(flipX: true, child: view);
    }
    return AspectRatio(aspectRatio: quarter ? ar.height / ar.width : ar.width / ar.height, child: view);
  }

  Widget _roundButton({required IconData icon, required String tooltip, VoidCallback? onTap, bool active = false}) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? AppColors.brandTurquoise : Colors.black38,
            shape: BoxShape.circle,
          ),
          child: _upright(Icon(icon, color: Colors.white, size: 24)),
        ),
      ),
    );
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
          Center(child: _preview(controller)),
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
          Positioned(
            top: AppSpacing.md,
            right: AppSpacing.md,
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  if (_cameras.length > 1)
                    _roundButton(
                      icon: Icons.cameraswitch_outlined,
                      tooltip: AppLocalizations.of(context).cameraSwitch,
                      onTap: (_isRecording || _switchingCamera) ? null : _switchCamera,
                    ),
                  if (Platform.isAndroid) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _roundButton(
                      icon: Icons.face_retouching_natural,
                      tooltip: AppLocalizations.of(context).arEffects,
                      active: _arPickerOpen || ArCameraBridge.selectedEffect != null,
                      onTap: () => setState(() => _arPickerOpen = !_arPickerOpen),
                    ),
                  ],
                ],
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
                if (_arPickerOpen) ...<Widget>[
                  _ArEffectStrip(
                    selected: ArCameraBridge.selectedEffect,
                    onSelect: (String? id) => unawaited(_selectArEffect(id)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
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

/// Horizontal list of live AR effects: "none" first, then each effect as an
/// emoji chip. The selected one is ringed in the brand colour.
class _ArEffectStrip extends StatelessWidget {
  const _ArEffectStrip({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    Widget chip({required String? id, required Widget child, required String label}) {
      final bool isSelected = id == selected;
      return Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          onTap: () => onSelect(id),
          child: Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? AppColors.brandTurquoise : Colors.white24, width: isSelected ? 3 : 1),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: <Widget>[
          chip(id: null, label: l10n.arNone, child: const Icon(Icons.block, color: Colors.white70)),
          for (final ArEffect e in ArEffect.all)
            chip(id: e.id, label: e.label(l10n), child: Text(e.emoji, style: const TextStyle(fontSize: 28))),
        ],
      ),
    );
  }
}
