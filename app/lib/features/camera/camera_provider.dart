import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/inference_service.dart';
import '../../services/settings_service.dart';
// Removed TTS service import since voice notes are disabled
// import '../../services/tts_service.dart';

/// Manages camera lifecycle, preview, capture, and flash.
/// Also coordinates object detection + TTS.
class CameraProvider extends ChangeNotifier {
  final InferenceService _inferenceService = InferenceService.instance;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  String? _error;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isStreamingImages = false;
  bool _isDisposed = false;
  bool _forceNextFrame = false;
  DateTime? _lastInferenceTime;
  Future<void>? _initFuture;
  int _cameraSession = 0;
  List<DetectionResult> _detections = [];
  int _detectionCount = 0;

  static const Duration _inferenceInterval = Duration(milliseconds: 800);

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  bool get isCapturing => _isCapturing;
  FlashMode get flashMode => _flashMode;
  List<DetectionResult> get detections => _detections;
  int get detectionCount => _detectionCount;

  /// Flash is inferred from back camera (camera 0.11.x no longer exposes hasFlash on value).
  bool get hasFlash {
    if (_controller == null) return false;
    return _controller!.description.lensDirection == CameraLensDirection.back;
  }

  /// Resolution preset from settings (0=low, 1=medium, 2=high).
  static ResolutionPreset _resolutionFromSettings() {
    final index = SettingsService.cameraResolutionIndex;
    switch (index) {
      case 0:
        return ResolutionPreset.low;
      case 2:
        // High-resolution image streams create a lot of pressure on older
        // Android devices. The model is resized to 320x320 anyway, so medium
        // is the practical upper bound for live detection.
        return ResolutionPreset.medium;
      default:
        return ResolutionPreset.low;
    }
  }

  static ImageFormatGroup _imageFormatGroupForPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ImageFormatGroup.bgra8888;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return ImageFormatGroup.yuv420;
    }
  }

  /// Request camera permission then initialize first available camera.
  Future<void> init() async {
    if (_initFuture != null) return _initFuture!;

    _initFuture = _initCamera();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initCamera() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _error = 'Camera permission denied';
        _notifyListeners();
        return;
      }
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _error = 'No camera found';
        _notifyListeners();
        return;
      }

      await _disposeController();
      _controller = CameraController(
        _cameras.first,
        _resolutionFromSettings(),
        imageFormatGroup: _imageFormatGroupForPlatform(),
        enableAudio: false,
      );
      await _controller!.initialize();
      try {
        _flashMode = _controller!.value.flashMode;
      } catch (_) {
        _flashMode = FlashMode.off;
      }
      _isInitialized = true;
      _error = null;
      _captureError = null;
      _detections = [];
      _detectionCount = 0;
      await _inferenceService.initialize();
      await _startImageDetectionStream();
    } catch (e) {
      _error = e.toString();
      _isInitialized = false;
      await _disposeController();
    }
    _notifyListeners();
  }

  Future<void> _disposeController() async {
    _cameraSession++;
    if (_controller != null) {
      if (_controller!.value.isStreamingImages) {
        try {
          await _controller!.stopImageStream();
        } catch (_) {}
      }
      await _controller!.dispose();
      _controller = null;
    }
    _isInitialized = false;
    _isStreamingImages = false;
    _forceNextFrame = false;
    _lastInferenceTime = null;
    _detections = [];
  }

  /// Release camera when leaving the screen.
  Future<void> disposeCamera() async {
    await _disposeController();
    _notifyListeners();
  }

  /// Toggle flash (off -> auto -> torch -> off). No-op if device does not support flash.
  Future<void> toggleFlash() async {
    if (_controller == null || !hasFlash) return;
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.torch];
    final idx = modes.indexOf(_flashMode);
    _flashMode = modes[(idx + 1) % modes.length];
    try {
      await _controller!.setFlashMode(_flashMode);
    } catch (_) {
      _flashMode = FlashMode.off;
    }
    _notifyListeners();
  }

  /// Ask the live stream to analyze the next available frame immediately.
  Future<void> capture() async {
    if (!_isStreamingImages) {
      _captureError = 'Camera stream is not ready yet';
      _notifyListeners();
      return;
    }

    _forceNextFrame = true;
    _captureError = null;
    _notifyListeners();
  }

  String? _captureError;
  String? get captureError => _captureError;
  void clearCaptureFeedback() {
    _captureError = null;
    _notifyListeners();
  }

  Future<void> _startImageDetectionStream() async {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) return;

    await controller.startImageStream(_handleCameraImage);
    _isStreamingImages = true;
  }

  void _handleCameraImage(CameraImage image) {
    if (!_isInitialized || _isCapturing) {
      return;
    }

    final now = DateTime.now();
    final shouldRunInference =
        _forceNextFrame ||
        _lastInferenceTime == null ||
        now.difference(_lastInferenceTime!) >= _inferenceInterval;
    if (!shouldRunInference) return;

    _forceNextFrame = false;
    _lastInferenceTime = now;
    _isCapturing = true;
    _notifyListeners();

    try {
      final frame = _copyCameraImage(image);
      unawaited(_runLiveInference(frame, _cameraSession));
    } catch (e) {
      _captureError = e.toString();
      _isCapturing = false;
      _notifyListeners();
    }
  }

  Future<void> _runLiveInference(
    CameraInferenceFrame frame,
    int cameraSession,
  ) async {
    try {
      final detections = await _inferenceService.runInferenceOnCameraFrame(
        frame,
      );
      if (!_isInitialized || cameraSession != _cameraSession) return;

      _detections = detections;
      if (_detections.isNotEmpty) {
        _detectionCount += _detections.length;
      }
      _captureError = null;
      // Removed TTS call to disable voice notes
      // await TtsService.instance.speakDetection(detection);
    } catch (e) {
      _captureError = e.toString();
    } finally {
      _isCapturing = false;
      _notifyListeners();
    }
  }

  CameraInferenceFrame _copyCameraImage(CameraImage image) {
    return CameraInferenceFrame(
      width: image.width,
      height: image.height,
      formatGroup: image.format.group.toString(),
      planes: image.planes
          .map((plane) => Uint8List.fromList(plane.bytes))
          .toList(growable: false),
      bytesPerRow: image.planes
          .map((plane) => plane.bytesPerRow)
          .toList(growable: false),
      bytesPerPixel: image.planes
          .map((plane) => plane.bytesPerPixel ?? 1)
          .toList(growable: false),
      sensorOrientation: _controller?.description.sensorOrientation ?? 0,
    );
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_disposeController());
    super.dispose();
  }
}
