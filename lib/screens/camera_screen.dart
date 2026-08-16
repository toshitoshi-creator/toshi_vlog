import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/highlight_reel.dart';
import '../models/video_library.dart';
import '../widgets/camera_controls.dart';
import 'recording_preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.videoLibrary,
    required this.highlightReel,
  });

  final VideoLibrary videoLibrary;
  final HighlightReel highlightReel;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isRecording = false;
  String? _errorMessage;

  FlashMode _flashMode = FlashMode.off;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _baseZoom = 1;

  ResolutionPreset _resolutionPreset = ResolutionPreset.high;
  int _fps = 30;

  bool _isImportingFromGallery = false;

  static const _maxRecordingDuration = Duration(seconds: 5);
  Timer? _autoStopTimer;
  Timer? _recordingTickTimer;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _loadSettings();
    await _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoStopTimer?.cancel();
    _recordingTickTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _autoStopTimer?.cancel();
      _recordingTickTimer?.cancel();
      _isRecording = false;
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeController(_cameras[_cameraIndex]);
    }
  }

  Future<void> _setupCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = '利用可能なカメラがありません');
        return;
      }
      await _initializeController(_cameras[_cameraIndex]);
    } catch (_) {
      setState(() => _errorMessage = 'カメラを初期化できませんでした');
    }
  }

  Future<void> _initializeController(CameraDescription description) async {
    final controller = CameraController(
      description,
      _resolutionPreset,
      enableAudio: true,
      fps: _fps,
    );
    _controller = controller;
    try {
      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      if (!mounted) return;
      final clampedZoom = _currentZoom.clamp(minZoom, maxZoom);
      setState(() {
        _errorMessage = null;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = clampedZoom;
        _baseZoom = clampedZoom;
      });
      await controller.setZoomLevel(clampedZoom);
      if (description.lensDirection == CameraLensDirection.back) {
        try {
          await controller.setFlashMode(_flashMode);
        } catch (_) {
          // Some devices don't support torch; ignore.
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'カメラを初期化できませんでした');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    await _initializeController(_cameras[_cameraIndex]);
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_isRecording) {
      await _stopRecordingAndReview();
    } else {
      try {
        await controller.startVideoRecording();
        _recordingStartedAt = DateTime.now();
        setState(() {
          _isRecording = true;
          _recordingElapsed = Duration.zero;
        });
        _autoStopTimer = Timer(_maxRecordingDuration, _stopRecordingAndReview);
        _recordingTickTimer = Timer.periodic(
          const Duration(milliseconds: 200),
          (_) {
            final startedAt = _recordingStartedAt;
            if (!mounted || startedAt == null) return;
            setState(
              () => _recordingElapsed = DateTime.now().difference(startedAt),
            );
          },
        );
      } catch (_) {
        if (mounted) setState(() => _errorMessage = '録画を開始できませんでした');
      }
    }
  }

  Future<void> _stopRecordingAndReview() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;

    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _recordingTickTimer?.cancel();
    _recordingTickTimer = null;
    _recordingStartedAt = null;

    try {
      final recorded = await controller.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);

      if (!mounted) return;
      final shouldSave = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RecordingPreviewScreen(file: File(recorded.path)),
        ),
      );

      if (shouldSave == true) {
        final savedFile = await widget.videoLibrary.store(recorded.path);
        // Trims the first second into the highlight reel in the background;
        // errors surface via HighlightReel.errorMessage on the まとめ tab.
        widget.highlightReel.addClip(savedFile);
      } else {
        final tempFile = File(recorded.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '録画の保存に失敗しました');
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isImportingFromGallery || _isRecording) return;
    final picker = ImagePicker();
    final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isImportingFromGallery = true);
    try {
      final savedFile = await widget.videoLibrary.store(picked.path);
      widget.highlightReel.addClip(savedFile);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '動画を取り込めませんでした');
    } finally {
      if (mounted) setState(() => _isImportingFromGallery = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.description.lensDirection != CameraLensDirection.back) {
      return;
    }
    final newMode = _flashMode == FlashMode.off
        ? FlashMode.torch
        : FlashMode.off;
    try {
      await controller.setFlashMode(newMode);
      if (mounted) setState(() => _flashMode = newMode);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'このカメラはフラッシュに対応していません');
    }
  }

  Future<void> _setZoom(double zoom) async {
    final controller = _controller;
    if (controller == null) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    setState(() => _currentZoom = clamped);
    await controller.setZoomLevel(clamped);
  }

  Future<void> _reinitializeCurrentCamera() async {
    if (_isRecording || _cameras.isEmpty) return;
    await _controller?.dispose();
    await _initializeController(_cameras[_cameraIndex]);
  }

  Future<void> _changeResolution(ResolutionPreset preset) async {
    if (_resolutionPreset == preset) return;
    setState(() => _resolutionPreset = preset);
    await _reinitializeCurrentCamera();
    await _persistSettings();
  }

  Future<void> _changeFps(int fps) async {
    if (_fps == fps) return;
    setState(() => _fps = fps);
    await _reinitializeCurrentCamera();
    await _persistSettings();
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/camera_settings.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final presetName = raw['resolutionPreset'] as String?;
        _resolutionPreset = ResolutionPreset.values.firstWhere(
          (preset) => preset.name == presetName,
          orElse: () => ResolutionPreset.high,
        );
        _fps = raw['fps'] as int? ?? 30;
      }
    } catch (_) {
      // Keep the defaults.
    }
  }

  Future<void> _persistSettings() async {
    final file = await _settingsFile();
    await file.writeAsString(
      jsonEncode({'resolutionPreset': _resolutionPreset.name, 'fps': _fps}),
    );
  }

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '画質',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ResolutionPreset>(
                      segments: const [
                        ButtonSegment(
                          value: ResolutionPreset.high,
                          label: Text('HD'),
                        ),
                        ButtonSegment(
                          value: ResolutionPreset.ultraHigh,
                          label: Text('4K'),
                        ),
                      ],
                      selected: {_resolutionPreset},
                      onSelectionChanged: (selection) {
                        setSheetState(() {});
                        _changeResolution(selection.first);
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'フレームレート',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 30, label: Text('30fps')),
                        ButtonSegment(value: 60, label: Text('60fps')),
                      ],
                      selected: {_fps},
                      onSelectionChanged: (selection) {
                        setSheetState(() {});
                        _changeFps(selection.first);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isBackCamera =
        controller?.description.lensDirection == CameraLensDirection.back;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (controller != null && controller.value.isInitialized)
              Positioned.fill(
                // CameraPreview sizes itself via an internal AspectRatio to
                // match the sensor's aspect ratio, but AspectRatio can only
                // honor that under loose constraints — Positioned.fill alone
                // hands it tight (exact-fill) constraints, which stretches
                // the image to the full screen box, most noticeably in
                // landscape. Center gives it the loose constraints it needs
                // so it letterboxes instead of distorting.
                child: Center(
                  child: GestureDetector(
                    onScaleStart: (_) => _baseZoom = _currentZoom,
                    onScaleUpdate: (details) =>
                        _setZoom(_baseZoom * details.scale),
                    child: CameraPreview(controller),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_errorMessage != null)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 60),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    TopIconButton(
                      icon: _flashMode == FlashMode.torch
                          ? Icons.flash_on
                          : Icons.flash_off,
                      enabled: isBackCamera && !_isRecording,
                      highlighted: _flashMode == FlashMode.torch,
                      onTap: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    TopIconButton(
                      icon: Icons.settings,
                      enabled: !_isRecording,
                      onTap: _showSettingsSheet,
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZoomPresetRow(
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      currentZoom: _currentZoom,
                      onSelect: _setZoom,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRecording
                          ? '残り${(_maxRecordingDuration - _recordingElapsed).inSeconds.clamp(0, 5)}秒 (タップで終了)'
                          : 'タップで録画開始 (最大5秒)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GalleryPickerButton(
                          enabled: !_isRecording && !_isImportingFromGallery,
                          isLoading: _isImportingFromGallery,
                          onTap: _pickFromGallery,
                        ),
                        const Spacer(),
                        RecordButton(
                          isRecording: _isRecording,
                          onTap: _toggleRecording,
                        ),
                        const Spacer(),
                        SwitchCameraButton(
                          enabled: !_isRecording && _cameras.length > 1,
                          onTap: _switchCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
