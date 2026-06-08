import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Single detection result from the TFLite model.
class ObjectDetectionResult {
  ObjectDetectionResult({
    required this.label,
    required this.confidence,
    required this.position,
  });

  final String label;
  final double confidence;
  /// "left", "front", or "right" based on bounding box center.
  final String position;

  String toSpokenSentence() {
    final object = label.toLowerCase();
    switch (position) {
      case 'left':
        return 'A $object is on your left';
      case 'right':
        return 'A $object is on your right';
      default:
        return 'A $object is in front of you';
    }
  }
}

/// Handles loading the TFLite model and running inference.
///
/// This implementation assumes an object detection model with SSD-style outputs:
///  - boxes  : [1, N, 4] (ymin, xmin, ymax, xmax) normalized 0-1
///  - scores : [1, N]
///  - classes: [1, N] (float class indices)
///  - numDet : [1]
/// If your model is different (e.g. YOLO), you can adjust the parsing logic
/// inside [_parseBestDetection].
class DetectionService {
  DetectionService._();

  static final DetectionService instance = DetectionService._();

  Interpreter? _interpreter;
  List<String> _labels = const [];
  List<int>? _inputShape; // [1, height, width, 3]
  bool _isInitialized = false;
  bool get isReady => _isInitialized;

  static const List<String> _fallbackLabels = [
    'background', 'person', 'chair', 'table', 'obstacle',
    'car', 'bottle', 'cup', 'door', 'laptop',
    'phone', 'bag', 'book', 'stairs', 'wall', 'other',
  ];

  Future<void> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (_labels.isEmpty) {
        debugPrint('[DetectionService] ⚠ labels.txt empty — using fallback');
        _labels = _fallbackLabels;
      } else {
        debugPrint('[DetectionService] Labels: $_labels');
      }
    } catch (e) {
      debugPrint('[DetectionService] ⚠ labels.txt missing — using fallback: $e');
      _labels = _fallbackLabels;
    }
  }

  Future<void> init() async {
    if (_interpreter != null) return;

    try {
      final byteData = await rootBundle.load('assets/models/best_int8.tflite');
      final modelBuffer = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      debugPrint('[DetectionService] Model buffer: ${modelBuffer.length} bytes');

      await _loadLabels();

      _interpreter = Interpreter.fromBuffer(
        modelBuffer,
        options: InterpreterOptions()..threads = 2,
      );
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _isInitialized = true;

      // Debug: log model IO for easier troubleshooting with custom models.
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      // These prints appear in `flutter run` console and help us adapt
      // the parsing logic if the model is not SSD-style.
      debugPrint('TFLite input tensors:');
      for (final t in inputTensors) {
        debugPrint('  name=${t.name} shape=${t.shape}');
      }
      debugPrint('TFLite output tensors:');
      for (final t in outputTensors) {
        debugPrint('  name=${t.name} shape=${t.shape}');
      }
    } catch (e, stack) {
      debugPrint('[DetectionService] FATAL ERROR in init(): $e');
      debugPrint('$stack');
      _isInitialized = false;
    }
  }

  /// Runs detection on an image file path and returns the best detection, or
  /// null if nothing passes the confidence threshold.
  Future<ObjectDetectionResult?> detectFromImageFile(
    String imagePath, {
    double minScore = 0.5,
  }) async {
    if (_interpreter == null) {
      await init();
    }
    if (_inputShape == null) return null;

    final file = File(imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final height = _inputShape![1];
    final width = _inputShape![2];
    final resized = img.copyResize(decoded, width: width, height: height);

    // Model expects uint8 input (int8/uint8 quantized models are typical here).
    final input = List.generate(
      1 * height * width * 3,
      (i) => 0,
      growable: false,
    ).reshape([1, height, width, 3]);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt().clamp(0, 255);
        final g = pixel.g.toInt().clamp(0, 255);
        final b = pixel.b.toInt().clamp(0, 255);
        input[0][y][x][0] = r;
        input[0][y][x][1] = g;
        input[0][y][x][2] = b;
      }
    }

    try {
      // Prepare outputs for SSD-style detection.
      final outputs = _interpreter!.getOutputTensors();
      if (outputs.length < 3) {
        // Model is not SSD-style (e.g. YOLO or custom). For now, bail out
        // gracefully and let TTS say "No object detected" instead of crashing.
        debugPrint(
          'DetectionService: expected at least 3 output tensors, '
          'found ${outputs.length}. Skipping detection.',
        );
        return null;
      }

      final boxesTensor = _interpreter!.getOutputTensor(0);
      _interpreter!.getOutputTensor(1);
      _interpreter!.getOutputTensor(2);

      final boxesShape = boxesTensor.shape; // [1, N, 4]
      final numBoxes = boxesShape[1];

      final boxes = List.generate(
        1,
        (_) => List.generate(
          numBoxes,
          (_) => List<double>.filled(4, 0.0),
        ),
      );
      final scores = [List<double>.filled(numBoxes, 0.0)];
      final classes = [List<double>.filled(numBoxes, 0.0)];

      final outputMap = <int, Object>{
        0: boxes,
        1: scores,
        2: classes,
      };

      _interpreter!.runForMultipleInputs([input], outputMap);

      return _parseBestDetection(
        boxes: boxes[0],
        scores: scores[0],
        classes: classes[0],
        minScore: minScore,
      );
    } on ArgumentError catch (e) {
      // Handles "Invalid output Tensor index" and similar issues gracefully.
      debugPrint('DetectionService: TFLite output mismatch: $e');
      return null;
    } catch (e) {
      debugPrint('DetectionService: unexpected error: $e');
      return null;
    }
  }

  ObjectDetectionResult? _parseBestDetection({
    required List<List<double>> boxes,
    required List<double> scores,
    required List<double> classes,
    required double minScore,
  }) {
    int bestIndex = -1;
    double bestScore = 0.0;

    for (var i = 0; i < scores.length; i++) {
      final score = scores[i];
      if (score >= minScore && score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex == -1) return null;

    final box = boxes[bestIndex];
    final xmin = box[1];
    final xmax = box[3];

    final centerX = (xmin + xmax) / 2.0;
    final position = _positionFromCenter(centerX);

    final classIndex = classes[bestIndex].toInt();
    final label = (classIndex >= 0 && classIndex < _labels.length)
        ? _labels[classIndex]
        : 'object';

    return ObjectDetectionResult(
      label: label,
      confidence: bestScore,
      position: position,
    );
  }

  String _positionFromCenter(double centerX) {
    // centerX is expected to be normalized 0..1
    if (centerX < 0.33) return 'left';
    if (centerX > 0.66) return 'right';
    return 'front';
  }
}
