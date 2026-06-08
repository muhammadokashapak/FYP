import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── WINDOWS HOTSPOT ISOLATION WARNING ────────────────────────────────────
// Windows hotspot has "Network Isolation" enabled by default which
// BLOCKS communication between devices connected to the same hotspot.
//
// SYMPTOM: Stream works in PC browser but NOT on Android phone.
//
// FIX (run on Windows laptop as Administrator in PowerShell):
//   1. Get-NetConnectionProfile
//      Find hotspot adapter name (e.g. "Local Area Connection* 12")
//   2. Set-NetConnectionProfile -Name "YOUR_ADAPTER_NAME" -NetworkCategory Private
//   3. Restart-NetAdapter -Name "YOUR_ADAPTER_NAME"
//
// BEST FIX: Connect both phone and ESP32 to a real Wi-Fi router instead.
// ─────────────────────────────────────────────────────────────────────────

/// Service to connect to ESP32-CAM MJPEG stream and extract individual JPEG frames.
/// MJPEG is a continuous HTTP stream where each JPEG frame is delimited by
/// SOI (Start of Image) marker [0xFF, 0xD8] and EOI (End of Image) marker [0xFF, 0xD9].
///
/// This service:
/// - Connects to the MJPEG stream URL
/// - Extracts individual JPEG frames by scanning for boundary markers
/// - Throttles frame emission to avoid backlog (max 8 FPS)
/// - Auto-reconnects on connection loss with exponential backoff
/// - Exposes a `Stream<Uint8List>` of raw JPEG bytes for downstream inference
class MjpegStreamService {
  final int maxRetries = 5;
  static const String defaultStreamUrl = 'http://192.168.137.176/';
  static const int maxFps = 8;
  static const int _maxRetries = 5;
  static const Duration _retryDelay = Duration(seconds: 2);

  // JPEG boundary markers
  static const int _jpegSoiHigh = 0xFF;
  static const int _jpegSoiLow = 0xD8; // SOI: [FF D8]
  static const int _jpegEoiHigh = 0xFF;
  static const int _jpegEoiLow = 0xD9; // EOI: [FF D9]

  // Stream management
  late StreamController<Uint8List> _frameController;
  http.Client? _httpClient;
  StreamSubscription? _streamSubscription;
  bool _isConnected = false;
  int _retryCount = 0;
  int _frameCount = 0;
  Timer? _capturePollTimer;
  final Set<String> _triedUrls = {};

  // FPS throttling
  DateTime? _lastFrameEmitTime;
  final int _minFrameIntervalMs = (1000 / maxFps).toInt();

  // Memory management: track if inference is still processing previous frame
  bool _isInferencing = false;

  /// Initialize the service. Creates a broadcast stream for frames.
  MjpegStreamService() {
    _frameController = StreamController<Uint8List>.broadcast();
   
  }

  /// Expose frames as a broadcast stream. Multiple listeners can subscribe.
  Stream<Uint8List> get frames => _frameController.stream;

  /// Check if currently connected to MJPEG stream.
  bool get isConnected => _isConnected;

  /// Track inference processing state to prevent frame backlog.
  /// Called by downstream inference service to signal processing.
  void setInferencingState(bool isProcessing) {
    _isInferencing = isProcessing;
  }

  /// Start connecting to the MJPEG stream at the given URL.
  /// Automatically retries on connection loss up to [_maxRetries] times.
  Future<void> start(String url) async {
    if (_frameController.isClosed) {
      _frameController = StreamController<Uint8List>.broadcast();
    }
    final normalizedUrl = normalizeUrl(url);
    debugPrint('[MJPEG] ═══════════════════════════════════');
    debugPrint('[MJPEG] Attempting connection to: $normalizedUrl');
    debugPrint('[MJPEG] Timestamp: ${DateTime.now().toIso8601String()}');

    _retryCount = 0;

    final alive = await isAlive(normalizedUrl);
    if (!alive) {
      debugPrint('[MJPEG] ❌ Device not reachable at $normalizedUrl');
      _frameController.addError(
        Exception('ESP32-CAM not reachable at $normalizedUrl. Check network.'),
      );
      return;
    }

    await _connect(normalizedUrl);
  }

  static String normalizeUrl(String rawInput) {
    String url = rawInput.trim();
    // Keep a trailing slash if the user explicitly provided a full URL ending
    // with '/', but we normalize away accidental trailing slashes for consistency.
    if (url.length > 1 && url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // If the user provided only a host, default to the common ESP32-CAM stream path.
    final uri = Uri.parse(url);
    if (uri.path.isEmpty || uri.path == '/') {
      url = url.endsWith('/') ? '${url}stream' : '$url/stream';
    }
    return url;
  }

  static Future<bool> isAlive(String baseUrl) async {
    try {
      // Ping the base host (strip any `/stream` legacy path if present).
      final pingUrl =
          baseUrl.contains('/stream') ? baseUrl.replaceAll('/stream', '') : baseUrl;

      debugPrint('[PING] Testing reachability: $pingUrl');

      final response = await http
          .get(
            Uri.parse(pingUrl),
            headers: {'Connection': 'close'},
          )
          .timeout(const Duration(seconds: 2));  // Reduced from 4s to 2s

      debugPrint('[PING] ✅ Device alive. HTTP ${response.statusCode}');
      return true;
    } on TimeoutException {
      debugPrint('[PING] ❌ TIMEOUT — Device not reachable at $baseUrl');
      debugPrint('[PING] Checklist:');
      debugPrint('[PING]   1. Is ESP32 powered on?');
      debugPrint('[PING]   2. Is phone on same Wi-Fi/hotspot as ESP32?');
      debugPrint('[PING]   3. Try opening $baseUrl in Chrome on the phone.');
      debugPrint('[PING]   4. Windows hotspot isolates devices — check hotspot settings.');
      return false;
    } on SocketException catch (e) {
      debugPrint('[PING] ❌ SOCKET ERROR: $e');
      return false;
    } catch (e) {
      debugPrint('[PING] ❌ Unknown error during ping: $e');
      return false;
    }
  }

  /// Internal connection logic with retry mechanism.
  Future<void> _connect(String url) async {
    try {
      _httpClient = http.Client();

      debugPrint('[MJPEG] Attempting HTTP connection: $url');
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri);
      request.headers.addAll({
        'Accept': 'multipart/x-mixed-replace, */*',
        'Connection': 'keep-alive',
        'Cache-Control': 'no-cache',
      });
      request.persistentConnection = true;

      // Send request and get streamed response with 15s timeout (increased from 8s)
      final streamedResponse = await _httpClient!.send(request)
          .timeout(const Duration(seconds: 15));

      debugPrint('[MJPEG] HTTP status code: ${streamedResponse.statusCode}');
      final contentType = (streamedResponse.headers['content-type'] ?? '').toLowerCase();
      debugPrint('[MJPEG] Content-Type: $contentType');
      debugPrint('[MJPEG] Response headers: ${streamedResponse.headers}');

      if (streamedResponse.statusCode != 200) {
        debugPrint('[MJPEG] ❌ Connection rejected. Status: ${streamedResponse.statusCode}');
        throw Exception(
          'HTTP ${streamedResponse.statusCode}: ${streamedResponse.reasonPhrase}',
        );
      }

      // If we got HTML (ESP32 web UI), this is NOT an MJPEG stream.
      // Auto-try common ESP32-CAM endpoints.
      if (contentType.contains('text/html') ||
          (!contentType.contains('multipart') && !contentType.contains('image/jpeg'))) {
        debugPrint('[MJPEG] ⚠ Endpoint returned non-stream content-type ($contentType).');
        _triedUrls.add(url);

        final fallback = _nextFallbackUrl(uri);
        if (fallback != null && !_triedUrls.contains(fallback)) {
          debugPrint('[MJPEG] ↪ Retrying with fallback endpoint: $fallback');
          _httpClient?.close();
          return await _connect(fallback);
        }

        // Final fallback: capture polling (still images) to keep feed alive.
        final captureUrl = _captureUrlFromHost(uri);
        debugPrint('[MJPEG] ↪ Falling back to capture polling: $captureUrl');
        _httpClient?.close();
        await _startCapturePolling(Uri.parse(captureUrl));
        return;
      }

      _isConnected = true;
      _retryCount = 0;
      debugPrint('[MJPEG] ✅ Connected successfully. Stream open.');

      // Listen to the response stream and extract frames
      await _processStream(streamedResponse.stream);
    } catch (e) {
      _isConnected = false;
      debugPrint('[MJPEG] ❌ Stream error: $e');
      debugPrint('[MJPEG] Error type: ${e.runtimeType}');

      // Auto-reconnect with exponential backoff
      if (_retryCount < _maxRetries) {
        _retryCount++;
        debugPrint('[MJPEG] Retry attempt: $_retryCount of $_maxRetries');
        await Future.delayed(_retryDelay);
        await _connect(url);
      } else {
        debugPrint('[MJPEG] Max retries ($_maxRetries) exceeded. Stopping.');
        if (!_frameController.isClosed) {
          await _frameController.close();
        }
      }
    }
  }

  String? _nextFallbackUrl(Uri original) {
    final host = original.host.isNotEmpty ? original.host : original.authority;
    final scheme = original.scheme.isNotEmpty ? original.scheme : 'http';

    // If user typed only host, ESP32-CAM common stream is on port 81 at /stream.
    final candidates = <String>[
      '$scheme://$host:81/stream',
      '$scheme://$host/stream',
      '$scheme://$host:81/',
    ];

    for (final c in candidates) {
      if (!_triedUrls.contains(c)) return c;
    }
    return null;
  }

  String _captureUrlFromHost(Uri uri) {
    final host = uri.host.isNotEmpty ? uri.host : uri.authority;
    final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
    // Many ESP32-CAM examples serve capture at /capture (often on port 80).
    return '$scheme://$host:80/capture';
  }

  Future<void> _startCapturePolling(Uri captureUri) async {
    _capturePollTimer?.cancel();
    _isConnected = true;
    _retryCount = 0;
    debugPrint('[MJPEG] ✅ Capture polling started.');

    // Poll at ~2 FPS (lightweight) to avoid blocking UI.
    _capturePollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final resp = await http
            .get(captureUri, headers: {'Connection': 'close'})
            .timeout(const Duration(seconds: 3));
        final ct = (resp.headers['content-type'] ?? '').toLowerCase();
        if (resp.statusCode == 200 && ct.contains('image/jpeg')) {
          await _emitFrameIfReady(Uint8List.fromList(resp.bodyBytes));
        }
      } catch (_) {
        // Ignore transient polling errors; retry on next tick.
      }
    });
  }

  /// Process the MJPEG stream by scanning for JPEG frame boundaries.
  /// Emits complete JPEG frames as Uint8List on the frames stream.
  Future<void> _processStream(Stream<List<int>> stream) async {
    final buffer = <int>[];
    _frameCount = 0;

    try {
      await for (final chunk in stream) {
        buffer.addAll(chunk);

        // Scan buffer for complete JPEG frames
        while (buffer.length >= 2) {
          // Find SOI marker [FF D8]
          final soiIndex = _findMarker(buffer, _jpegSoiHigh, _jpegSoiLow);
          if (soiIndex == -1) {
            // No SOI found, keep last byte in case it's part of next marker
            buffer.removeRange(0, buffer.length - 1);
            break;
          }

          // Remove bytes before SOI
          if (soiIndex > 0) {
            buffer.removeRange(0, soiIndex);
          }

          // Look for EOI marker [FF D9] after SOI
          // EOI should be at least 10 bytes after SOI (smallest valid JPEG)
          if (buffer.length < 12) break;

          final eoiIndex = _findMarker(buffer, _jpegEoiHigh, _jpegEoiLow, startFrom: 10);
          if (eoiIndex == -1) {
            // EOI not found yet, wait for more data
            break;
          }

          // Extract complete JPEG frame (inclusive of EOI marker)
          final frameLength = eoiIndex + 2;
          final frame = Uint8List.fromList(buffer.sublist(0, frameLength));

          // Remove processed frame from buffer
          buffer.removeRange(0, frameLength);

          _frameCount++;
          if (_frameCount <= 5) {
            debugPrint('[MJPEG] Frame #$_frameCount extracted — ${frame.length} bytes');
          }
          if (_frameCount == 1) {
            debugPrint('[MJPEG] ✅ FIRST FRAME RECEIVED — pipeline is working.');
          }

          // Emit frame with FPS throttling and inference backlog check
          await _emitFrameIfReady(frame);
        }
      }

      debugPrint('[MJPEG] ⚠ Stream closed unexpectedly. Will retry in 2s.');
      _isConnected = false;
    } catch (e) {
      debugPrint('[MJPEG] ❌ Stream error: $e');
      _isConnected = false;
    }
  }

  /// Emit frame if FPS throttle allows and inference is not backlogged.
  Future<void> _emitFrameIfReady(Uint8List frame) async {
    // Skip if inference is still processing (prevents backlog)
    if (_isInferencing) {
      return;
    }

    // Check FPS throttle
    final now = DateTime.now();
    if (_lastFrameEmitTime != null) {
      final elapsedMs = now.difference(_lastFrameEmitTime!).inMilliseconds;
      if (elapsedMs < _minFrameIntervalMs) {
        // Frame arrived too soon, skip it
        return;
      }
    }

    _lastFrameEmitTime = now;

    if (!_frameController.isClosed) {
      _frameController.add(frame);
      debugPrint('[MjpegStreamService] Emitted frame (${frame.length} bytes)');
    }
  }

  /// Scan buffer for a specific 2-byte marker [high, low].
  /// Returns index of the high byte, or -1 if not found.
  int _findMarker(List<int> buffer, int high, int low, {int startFrom = 0}) {
    for (int i = startFrom; i < buffer.length - 1; i++) {
      if (buffer[i] == high && buffer[i + 1] == low) {
        return i;
      }
    }
    return -1;
  }

  /// Stop the stream and clean up resources.
  void stop() {
    debugPrint('[MjpegStreamService] Stopping stream service');
    _streamSubscription?.cancel();
    _httpClient?.close();
    _capturePollTimer?.cancel();
    _capturePollTimer = null;
    _isConnected = false;

    if (!_frameController.isClosed) {
      _frameController.close();
    }
  }

  /// Clean up resources when service is disposed.
  void dispose() {
    stop();
  }
}
