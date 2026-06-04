// Interpreter.fromAsset() calls rootBundle.load() which requires ServicesBinding.
// Background isolates have NO bindings. BackgroundIsolateBinaryMessenger is
// NOT a real fix. The correct fix: load model bytes on main isolate via
// rootBundle, pass Uint8List to background isolate, use Interpreter.fromBuffer().

import 'dart:math' show exp, max, min;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Detection result from TFLite model inference.
/// Contains label, confidence score, and normalized bounding box.
class DetectionResult {
  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  final String label;
  final double confidence;
  final ui.Rect boundingBox; // normalized 0.0-1.0 coordinates (left, top, right, bottom)

  @override
  String toString() =>
      'DetectionResult(label=$label, conf=${confidence.toStringAsFixed(2)}, box=$boundingBox)';
}

/// Passable parameters for isolate inference.
/// The isolate only uses raw bytes and primitive values.
class _InferenceParams {
  const _InferenceParams({
    required this.modelBuffer,
    required this.imageBytes,
    required this.labels,
    required this.confidenceThresh,
    required this.nmsIouThresh,
    required this.inputH,
    required this.inputW,
  });

  final Uint8List modelBuffer; // raw .tflite bytes — isolate safe
  final Uint8List imageBytes; // JPEG frame from ESP32-CAM
  final List<String> labels;
  final double confidenceThresh;
  final double nmsIouThresh;
  final int inputH;
  final int inputW;
}

class InferenceService {
  InferenceService._();

  static final InferenceService instance = InferenceService._();

  static const String _modelAsset = 'assets/models/best_int8.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';
  static const double _confThresh = 0.45;
  static const double _nmsThresh = 0.45;

  Uint8List? _modelBuffer;
  List<String> _labels = [];
  int _inputH = 320;
  int _inputW = 320;
  bool _isReady = false;

  static const List<String> _fallbackLabels = [
    'background', 'person', 'chair', 'table', 'obstacle',
    'car', 'bottle', 'cup', 'door', 'laptop',
    'phone', 'bag', 'book', 'stairs', 'wall', 'other',
  ];

  Future<void> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString(_labelsAsset);
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(growable: false);
      if (_labels.isEmpty) {
        debugPrint('[Inference] ⚠ labels.txt empty — using fallback');
        _labels = _fallbackLabels;
      } else {
        debugPrint('[Inference] ✅ Labels: $_labels');
      }
    } catch (e) {
      debugPrint('[Inference] ⚠ labels.txt missing — using fallback: $e');
      _labels = _fallbackLabels;
    }
  }

  Future<void> initialize() async {
    try {
      await _loadLabels();

      final byteData = await rootBundle.load(_modelAsset);
      _modelBuffer = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      debugPrint('[Inference] ✅ Model buffer: ${_modelBuffer!.length} bytes');

      final testInterp = Interpreter.fromBuffer(
        _modelBuffer!,
        options: InterpreterOptions()..threads = 1,
      );
      final inShape = testInterp.getInputTensor(0).shape;
      _inputH = inShape[1];
      _inputW = inShape[2];
      debugPrint('[Inference] Input tensor shape: $inShape');

      for (int i = 0; i < testInterp.getOutputTensors().length; i++) {
        final t = testInterp.getOutputTensor(i);
        debugPrint('[Inference] Output[$i] shape: ${t.shape}  type: ${t.type}');
      }
      testInterp.close();

      _isReady = true;
      debugPrint('[Inference] ✅ Ready. H=$_inputH W=$_inputW');
    } catch (e, stack) {
      if (e.toString().contains('labels.txt')) {
        throw Exception('Setup incomplete: labels file missing. Check assets/models/labels.txt');
      }
      if (e.toString().contains('best_int8.tflite') || e.toString().contains('.tflite')) {
        throw Exception('Setup incomplete: AI model file missing.');
      }
      debugPrint('[Inference] FATAL ERROR in initialize(): $e');
      debugPrint('$stack');
      rethrow;
    }
  }

  Future<List<DetectionResult>> runInference(Uint8List jpegBytes) async {
    if (!_isReady || _modelBuffer == null) return [];

    return compute(
      _isolateInfer,
      _InferenceParams(
        modelBuffer: _modelBuffer!,
        imageBytes: jpegBytes,
        labels: _labels,
        confidenceThresh: _confThresh,
        nmsIouThresh: _nmsThresh,
        inputH: _inputH,
        inputW: _inputW,
      ),
    );
  }

  static Future<List<DetectionResult>> _isolateInfer(
    _InferenceParams params,
  ) async {
    Interpreter? interpreter;
    try {
      debugPrint('[InferenceIsolate] Starting inference...');

      interpreter = Interpreter.fromBuffer(
        params.modelBuffer,
        options: InterpreterOptions()..threads = 2,
      );
      debugPrint('[InferenceIsolate] ✅ Model Loaded Successfully');

      final decoded = img.decodeJpg(params.imageBytes);
      if (decoded == null) {
        debugPrint('[InferenceIsolate] ⚠ JPEG decode failed');
        return [];
      }

      final resized = img.copyResize(
        decoded,
        width: params.inputW,
        height: params.inputH,
      );

      final input = List.generate(
        1 * params.inputH * params.inputW * 3,
        (_) => 0,
        growable: false,
      ).reshape([1, params.inputH, params.inputW, 3]);

      for (int y = 0; y < params.inputH; y++) {
        for (int x = 0; x < params.inputW; x++) {
          final int pixel = resized.getPixel(x, y);
          input[0][y][x][0] = img.getRed(pixel).clamp(0, 255);
          input[0][y][x][1] = img.getGreen(pixel).clamp(0, 255);
          input[0][y][x][2] = img.getBlue(pixel).clamp(0, 255);
        }
      }

      final outShape = interpreter.getOutputTensor(0).shape;
      debugPrint('[InferenceIsolate] Output shape: $outShape');

      final outputData = List.generate(
        outShape[0],
        (_) => List.generate(
          outShape[1],
          (_) => List.filled(outShape[2], 0.0),
          growable: false,
        ),
        growable: false,
      );

      interpreter.run(input, outputData);
      debugPrint('[InferenceIsolate] Inference complete.');

      return _postProcess(
        outputData: outputData,
        outputShape: outShape,
        labels: params.labels,
        confThresh: params.confidenceThresh,
        iouThresh: params.nmsIouThresh,
        imgW: params.inputW.toDouble(),
        imgH: params.inputH.toDouble(),
      );
    } catch (e, stack) {
      debugPrint('[InferenceIsolate] FATAL ERROR: $e');
      debugPrint('$stack');
      return [];
    } finally {
      interpreter?.close();
      debugPrint('[InferenceIsolate] Interpreter closed.');
    }
  }

  static List<DetectionResult> _postProcess({
    required List<List<List<double>>> outputData,
    required List<int> outputShape,
    required List<String> labels,
    required double confThresh,
    required double iouThresh,
    required double imgW,
    required double imgH,
  }) {
    final int dim1 = outputShape[1];
    final int dim2 = outputShape[2];
    final bool isTransposed = dim1 < dim2;
    final int numAnchors = isTransposed ? dim2 : dim1;
    final int numAttribs = isTransposed ? dim1 : dim2;
    final int numClasses = numAttribs - 4;

    debugPrint('[PostProcess] Layout: ${isTransposed ? 'channel-first' : 'anchor-major'}');
    debugPrint('[PostProcess] anchors=$numAnchors  classes=$numClasses');

    double val(int anchor, int attrib) => isTransposed
        ? outputData[0][attrib][anchor]
        : outputData[0][anchor][attrib];

    final rawBoxes = <List<double>>[];
    final rawScores = <double>[];
    final rawClasses = <int>[];

    for (int a = 0; a < numAnchors; a++) {
      double bestScore = -1.0;
      int bestClass = -1;
      for (int c = 0; c < numClasses; c++) {
        final score = 1.0 / (1.0 + exp(-val(a, 4 + c)));
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass == 0 || bestScore < confThresh) continue;

      final cx = val(a, 0);
      final cy = val(a, 1);
      final bw = val(a, 2);
      final bh = val(a, 3);
      rawBoxes.add([
        ((cx - bw / 2) / imgW).clamp(0.0, 1.0),
        ((cy - bh / 2) / imgH).clamp(0.0, 1.0),
        ((cx + bw / 2) / imgW).clamp(0.0, 1.0),
        ((cy + bh / 2) / imgH).clamp(0.0, 1.0),
      ]);
      rawScores.add(bestScore);
      rawClasses.add(bestClass);
    }

    final kept = _nms(rawBoxes, rawScores, rawClasses, iouThresh);
    return kept.map((i) {
      final label = rawClasses[i] < labels.length ? labels[rawClasses[i]] : 'unknown';
      debugPrint('[PostProcess] ✅ Detected: $label  conf=${rawScores[i].toStringAsFixed(2)}');
      return DetectionResult(
        label: label,
        confidence: rawScores[i],
        boundingBox: ui.Rect.fromLTRB(
          rawBoxes[i][0],
          rawBoxes[i][1],
          rawBoxes[i][2],
          rawBoxes[i][3],
        ),
      );
    }).toList();
  }

  static List<int> _nms(
    List<List<double>> boxes,
    List<double> scores,
    List<int> classes,
    double iouThresh,
  ) {
    final selected = <int>[];
    final indexes = List<int>.generate(scores.length, (index) => index);
    indexes.sort((a, b) => scores[b].compareTo(scores[a]));

    while (indexes.isNotEmpty) {
      final current = indexes.removeAt(0);
      selected.add(current);
      indexes.removeWhere((idx) {
        if (classes[idx] != classes[current]) return false;
        return _iou(boxes[current], boxes[idx]) > iouThresh;
      });
    }

    return selected;
  }

  static double _iou(List<double> a, List<double> b) {
    final left = max(a[0], b[0]);
    final top = max(a[1], b[1]);
    final right = min(a[2], b[2]);
    final bottom = min(a[3], b[3]);
    final width = right - left;
    final height = bottom - top;
    if (width <= 0 || height <= 0) return 0.0;
    final inter = width * height;
    final union = (a[2] - a[0]) * (a[3] - a[1]) +
        (b[2] - b[0]) * (b[3] - b[1]) -
        inter;
    if (union <= 0) return 0.0;
    return inter / union;
  }
}
