import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/video_library.dart';
import '../widgets/camera_controls.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.videoLibrary});

  final VideoLibrary videoLibrary;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
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
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _errorMessage = null);
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
      final file = await controller.stopVideoRecording();
      setState(() => _isRecording = false);
      await widget.videoLibrary.store(file.path);
    } else {
      await controller.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (controller != null && controller.value.isInitialized)
              Positioned.fill(child: CameraPreview(controller))
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_errorMessage != null)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 16),
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
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 56),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
