import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import '../services/inference_service.dart';
import '../services/mjpeg_stream_service.dart';
import '../services/tts_service.dart';

/// Provider that manages the complete detection pipeline:
/// 1. Connects to ESP32-CAM MJPEG stream
/// 2. Extracts frames and runs inference every 3rd frame
/// 3. Announces detections via TTS
/// 4. Exposes state for UI (current frame, detections, status)
///
/// This is a ChangeNotifier that broadcasts changes to all UI listeners.
class DetectionProvider extends ChangeNotifier {
  final MjpegStreamService _streamService = MjpegStreamService();
  final InferenceService _inferenceService = InferenceService.instance;
  final TtsService _ttsService = TtsService.instance;

  // State exposed to UI
  Uint8List? _currentFrameBytes;
  List<DetectionResult> _detections = [];
  bool _isStreaming = false;
  String? _errorMessage;
  String? _currentStreamUrl;
  int _fps = 0;
  int _detectionCount = 0;
  bool _isInitialized = false;
  bool _isRunningInference = false;
  Future<void>? _initializeFuture;
  DateTime? _lastInferenceTime;

  // Internal frame processing tracking
  DateTime? _lastFpsCheckTime;
  int _framesInCurrentSecond = 0;
  StreamSubscription? _frameSubscription;

  static const Duration _inferenceInterval = Duration(milliseconds: 800);
  static const ui.Size _distanceFrameSize = ui.Size(320, 240);

  // Getters for UI
  Uint8List? get currentFrameBytes => _currentFrameBytes;
  List<DetectionResult> get detections => _detections;
  bool get isStreaming => _isStreaming;
  String? get errorMessage => _errorMessage;
  int get fps => _fps;
  int get detectionCount => _detectionCount;
  String? get currentStreamUrl => _currentStreamUrl;

  /// Initialize services. Call once before starting stream.
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initializeFuture != null) return _initializeFuture;

    debugPrint('[DetectionProvider] Initializing services...');
    _initializeFuture = () async {
      await _inferenceService.initialize();
      await _ttsService.init();
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
      debugPrint('[DetectionProvider] Initialization complete');
    }();

    try {
      await _initializeFuture;
    } catch (e) {
      final message = e.toString();
      if (message.contains('labels.txt')) {
        _errorMessage = 'Setup incomplete: labels file missing. Check assets/models/labels.txt';
      } else if (message.contains('best_int8.tflite') || message.contains('tflite')) {
        _errorMessage = 'Setup incomplete: AI model file missing.';
      } else {
        _errorMessage = 'Initialization failed: $e';
      }
      debugPrint('[DetectionProvider] ERROR: $_errorMessage');
      notifyListeners();
      rethrow;
    } finally {
      _initializeFuture = null;
    }
  }

  /// Start streaming from ESP32-CAM MJPEG and run detection pipeline.
  Future<void> startStream(String url) async {
    if (_isStreaming) {
      debugPrint('[DetectionProvider] Already streaming, ignoring duplicate start');
      return;
    }

    // Clear any previous error message when retrying
    _errorMessage = null;

    // Normalize the URL first (add scheme, trim whitespace, etc.)
    final normalizedUrl = MjpegStreamService.normalizeUrl(url);
    _currentStreamUrl = normalizedUrl;
    debugPrint('[DetectionProvider] Starting stream from: $normalizedUrl');
    _isStreaming = true;
    _framesInCurrentSecond = 0;
    notifyListeners();

    try {
      await initialize();

      // Try ping but do NOT block stream attempt if it fails
      // Windows hotspot isolation can block ICMP/HTTP ping but still
      // allow MJPEG stream connections in some configurations
      try {
        final ping = await MjpegStreamService.isAlive(normalizedUrl)
            .timeout(const Duration(seconds: 3));
        if (!ping) {
          debugPrint('[DetectionProvider] ⚠ Ping failed but attempting stream anyway...');
          // Do NOT return here — try connecting regardless
        } else {
          debugPrint('[DetectionProvider] ✅ Ping OK. Connecting to stream...');
        }
      } catch (_) {
        debugPrint('[DetectionProvider] ⚠ Ping timed out. Attempting stream anyway...');
        // Do NOT return — attempt stream connection regardless
      }

      // Listen to frame stream and run inference pipeline
      _frameSubscription = _streamService.frames.listen(
        (Uint8List frameBytes) {
          _onFrameReceived(frameBytes);
        },
        onError: (error) {
          debugPrint('[DetectionProvider] Stream error: $error');
          _errorMessage = 'Stream error: $error';
          _isStreaming = false;
          notifyListeners();
        },
        onDone: () {
          debugPrint('[DetectionProvider] Stream closed');
          _isStreaming = false;
          notifyListeners();
        },
      );

      // Start MJPEG stream connection (with auto-reconnect)
      await _streamService.start(normalizedUrl);
    } catch (e) {
      _errorMessage = 'Failed to start stream: $e';
      _isStreaming = false;
      debugPrint('[DetectionProvider] ERROR: $_errorMessage');
      notifyListeners();
    }
  }

  /// Handle incoming frame from MJPEG stream.
  void _onFrameReceived(Uint8List frameBytes) {
    _currentFrameBytes = frameBytes;
    _framesInCurrentSecond++;

    // Update FPS counter (check every second)
    final now = DateTime.now();
    if (_lastFpsCheckTime == null) {
      _lastFpsCheckTime = now;
    } else if (now.difference(_lastFpsCheckTime!).inSeconds >= 1) {
      _fps = _framesInCurrentSecond;
      _framesInCurrentSecond = 0;
      _lastFpsCheckTime = now;
    }

    notifyListeners(); // Update UI with new frame
    unawaited(_runInferenceOnFrame(frameBytes));
  }

  /// Run inference on frame and update detections.
  Future<void> _runInferenceOnFrame(Uint8List frameBytes) async {
    if (!_isStreaming || !_isInitialized || _isRunningInference) return;

    final now = DateTime.now();
    if (_lastInferenceTime != null &&
        now.difference(_lastInferenceTime!) < _inferenceInterval) {
      return;
    }

    _isRunningInference = true;
    _lastInferenceTime = now;

    try {
      final detections = await _inferenceService.runInference(frameBytes);
      if (!_isStreaming) return;

      _detections = detections;
      if (detections.isNotEmpty) {
        _detectionCount += detections.length;
        await _ttsService.announceDetections(detections, _distanceFrameSize);
      }

      _errorMessage = null;
      notifyListeners();
    } catch (e, stack) {
      debugPrint('[DetectionProvider] Inference error: $e');
      debugPrint('$stack');
      if (_isStreaming) {
        _errorMessage = 'Inference failed: $e';
        notifyListeners();
      }
    } finally {
      _isRunningInference = false;
    }
  }

  /// Stop streaming and clean up.
  void stopStream() {
    debugPrint('[DetectionProvider] Stopping stream');
    _isStreaming = false;
    _currentStreamUrl = null;
    _frameSubscription?.cancel();
    _streamService.stop();
    _detections = [];
    _currentFrameBytes = null;
    _lastInferenceTime = null;
    _isRunningInference = false;
    notifyListeners();
  }

  /// Clean up resources when provider is disposed.
  @override
  void dispose() {
    debugPrint('[DetectionProvider] Disposing');
    stopStream();
    _streamService.dispose();
    _ttsService.stop();
    super.dispose();
  }
}
