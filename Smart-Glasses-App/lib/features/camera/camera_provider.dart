import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/detection_service.dart';
import '../../services/settings_service.dart';
// Removed TTS service import since voice notes are disabled
// import '../../services/tts_service.dart';

/// Manages camera lifecycle, preview, capture, and flash.
/// Also coordinates object detection + TTS.
class CameraProvider extends ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  String? _error;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  Timer? _autoDetectTimer;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  bool get isCapturing => _isCapturing;
  FlashMode get flashMode => _flashMode;

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
        return ResolutionPreset.high;
      default:
        return ResolutionPreset.medium;
    }
  }

  /// Request camera permission then initialize first available camera.
  Future<void> init() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _error = 'Camera permission denied';
        notifyListeners();
        return;
      }
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _error = 'No camera found';
        notifyListeners();
        return;
      }

      await _disposeController();
      _controller = CameraController(
        _cameras.first,
        _resolutionFromSettings(),
        imageFormatGroup: ImageFormatGroup.jpeg,
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
      _startAutoDetection();
    } catch (e) {
      _error = e.toString();
      _isInitialized = false;
    }
    notifyListeners();
  }

  Future<void> _disposeController() async {
    _autoDetectTimer?.cancel();
    _autoDetectTimer = null;
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    _isInitialized = false;
  }

  /// Release camera when leaving the screen.
  Future<void> disposeCamera() async {
    await _disposeController();
    notifyListeners();
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
    notifyListeners();
  }

  /// Capture image and run object detection + TTS.
  Future<void> capture() async {
    await _captureAndDetect(isAuto: false);
  }

  String? _lastCapturePath;
  String? _captureError;
  String? get lastCapturePath => _lastCapturePath;
  String? get captureError => _captureError;
  void clearCaptureFeedback() {
    _lastCapturePath = null;
    _captureError = null;
    notifyListeners();
  }

  void _startAutoDetection() {
    _autoDetectTimer?.cancel();
    // Run detection every 3 seconds while camera is active.
    _autoDetectTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _captureAndDetect(isAuto: true),
    );
  }

  Future<void> _captureAndDetect({required bool isAuto}) async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }
    _isCapturing = true;
    notifyListeners();
    try {
      final file = await _controller!.takePicture();
      _lastCapturePath = isAuto ? _lastCapturePath : file.path;

      // Run detection but don't use result since TTS is disabled
      await DetectionService.instance.detectFromImageFile(file.path);
      // Removed TTS call to disable voice notes
      // await TtsService.instance.speakDetection(detection);
    } catch (e) {
      _captureError = e.toString();
    }
    _isCapturing = false;
    notifyListeners();
  }
}
