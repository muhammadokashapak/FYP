import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A high-performance MJPEG streaming widget with built-in buffering and fallback support.
/// 
/// Uses the http package to handle MJPEG boundary parsing and provides optimized
/// frame buffering for smooth playback with minimal lag.
class OptimizedMjpegWidget extends StatefulWidget {
  const OptimizedMjpegWidget({
    super.key,
    required this.streamUrl,
    this.onConnectionError,
    this.onFrameReceived,
    this.placeholder,
    this.error,
    this.fit = BoxFit.cover,
    this.timeout = const Duration(seconds: 15),
  });

  /// The MJPEG stream URL (e.g., http://192.168.137.176/)
  final String streamUrl;

  /// Callback when connection fails (can switch to capture fallback)
  final VoidCallback? onConnectionError;

  /// Callback when a frame is successfully received
  final Function(Uint8List)? onFrameReceived;

  /// Widget to show while loading (default: CircularProgressIndicator)
  final Widget? placeholder;

  /// Widget to show on error
  final Widget? error;

  /// How to fit the image
  
  final BoxFit fit;

  /// Connection timeout
  final Duration timeout;

  @override
  State<OptimizedMjpegWidget> createState() => _OptimizedMjpegWidgetState();
}

class _OptimizedMjpegWidgetState extends State<OptimizedMjpegWidget> {
  late http.Client _httpClient;
  StreamSubscription<List<int>>? _streamSubscription;
  final List<int> _buffer = [];
  Uint8List? _currentFrame;
  bool _isConnecting = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _httpClient = http.Client();
    _startStream();
  }

  @override
  void didUpdateWidget(OptimizedMjpegWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _stopStream();
      _startStream();
    }
  }

  @override
  void dispose() {
    _stopStream();
    _httpClient.close();
    super.dispose();
  }

  void _stopStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  Future<void> _startStream() async {
    if (!mounted) return;

    _buffer.clear();
    setState(() {
      _isConnecting = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      request.headers['Accept'] = 'multipart/x-mixed-replace, image/jpeg, */*';
      request.headers['Connection'] = 'keep-alive';
      request.headers['User-Agent'] = 'Flutter';

      final response = await _httpClient.send(request).timeout(widget.timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentType = response.headers['content-type'] ?? '';
      final boundary = _extractBoundary(contentType);
      if (boundary == null) {
        throw Exception('No MJPEG boundary found');
      }

      _parseStream(response.stream, boundary);

      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = error.toString();
          _isConnecting = false;
        });
      }
      widget.onConnectionError?.call();
    }
  }

  String? _extractBoundary(String contentType) {
    final match = RegExp(r'boundary=(.*)', caseSensitive: false).firstMatch(contentType);
    if (match == null) return null;
    final boundary = match.group(1)?.trim();
    if (boundary == null || boundary.isEmpty) return null;
    return boundary.replaceAll('"', '');
  }

  void _parseStream(Stream<List<int>> stream, String boundary) {
    final boundaryBytes = utf8.encode('--$boundary');
    final headerEnd = utf8.encode('\r\n\r\n');

    _streamSubscription = stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _processBuffer(boundaryBytes, headerEnd);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = error.toString();
          });
        }
        widget.onConnectionError?.call();
      },
      onDone: () {
        if (mounted && !_hasError) {
          setState(() {
            _isConnecting = false;
          });
        }
      },
      cancelOnError: true,
    );
  }

  void _processBuffer(List<int> boundaryBytes, List<int> headerEnd) {
    while (true) {
      final boundaryIndex = _indexOf(_buffer, boundaryBytes);
      if (boundaryIndex < 0) break;

      final partStart = boundaryIndex + boundaryBytes.length;
      if (_buffer.length <= partStart) break;

      _buffer.removeRange(0, partStart);

      final headerIndex = _indexOf(_buffer, headerEnd);
      if (headerIndex < 0) break;

      final imageStart = headerIndex + headerEnd.length;
      if (_buffer.length <= imageStart) break;

      final nextBoundaryIndex = _indexOf(_buffer, boundaryBytes, imageStart);
      if (nextBoundaryIndex < 0) break;

      final jpegData = _buffer.sublist(imageStart, nextBoundaryIndex - 2);
      if (jpegData.isNotEmpty) {
        final frame = Uint8List.fromList(jpegData);
        widget.onFrameReceived?.call(frame);

        if (mounted) {
          setState(() {
            _currentFrame = frame;
            _isConnecting = false;
            _hasError = false;
          });
        }
      }

      _buffer.removeRange(0, nextBoundaryIndex);
    }
  }

  int _indexOf(List<int> buffer, List<int> pattern, [int start = 0]) {
    for (var i = start; i + pattern.length <= buffer.length; i++) {
      var found = true;
      for (var j = 0; j < pattern.length; j++) {
        if (buffer[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.error ??
          Container(
            color: Colors.grey[200],
            child: Center(
              child: Text('Error: $_errorMessage'),
            ),
          );
    }

    if (_isConnecting || _currentFrame == null) {
      return widget.placeholder ??
          Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
    }

    return Image.memory(
      _currentFrame!,
      gaplessPlayback: true,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
