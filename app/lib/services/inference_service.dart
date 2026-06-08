// Interpreter.fromAsset() calls rootBundle.load() which requires ServicesBinding.
// Background isolates have NO bindings. BackgroundIsolateBinaryMessenger is
// NOT a real fix. The correct fix: load model bytes on main isolate via
// rootBundle, pass Uint8List to background isolate, use Interpreter.fromBuffer().

import 'dart:async';
import 'dart:isolate';
import 'dart:math' show exp, max, min, sqrt;
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
    this.isSceneClassification = false,
  });

  final String label;
  final double confidence;

  /// Normalized 0.0-1.0 coordinates (left, top, right, bottom).
  final ui.Rect boundingBox;

  /// True for whole-scene ImageNet-style classification (no real bbox).
  final bool isSceneClassification;

  @override
  String toString() =>
      'DetectionResult(label=$label, conf=${confidence.toStringAsFixed(2)}, box=$boundingBox)';
}

/// Sendable camera frame data copied from CameraImage before isolate inference.
class CameraInferenceFrame {
  const CameraInferenceFrame({
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    this.sensorOrientation = 0,
  });

  final int width;
  final int height;
  final String formatGroup;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;

  /// Clockwise rotation from sensor to device native orientation (degrees).
  final int sensorOrientation;
}

class _WorkerInitMessage {
  const _WorkerInitMessage({
    required this.replyTo,
    required this.modelBuffer,
    required this.labels,
    required this.confidenceThresh,
    required this.nmsIouThresh,
    required this.inputH,
    required this.inputW,
  });

  final SendPort replyTo;
  final Uint8List modelBuffer;
  final List<String> labels;
  final double confidenceThresh;
  final double nmsIouThresh;
  final int inputH;
  final int inputW;
}

class _InferenceRequest {
  _InferenceRequest.jpeg({required this.id, required this.imageBytes})
    : frame = null;

  _InferenceRequest.cameraFrame({required this.id, required this.frame})
    : imageBytes = null;

  final int id;
  final Uint8List? imageBytes;
  final CameraInferenceFrame? frame;
}

class _InferenceResponse {
  const _InferenceResponse({
    required this.id,
    required this.detections,
    this.error,
    this.stackTrace,
  });

  final int id;
  final List<DetectionResult> detections;
  final String? error;
  final String? stackTrace;
}

class _WorkerStartupError {
  const _WorkerStartupError(this.error, this.stackTrace);

  final String error;
  final String stackTrace;
}

class _CloseInferenceWorker {
  const _CloseInferenceWorker();
}

class _PersistentInferenceWorker {
  _PersistentInferenceWorker._({
    required Isolate isolate,
    required ReceivePort receivePort,
    required StreamSubscription<Object?> subscription,
    required SendPort sendPort,
    required Map<int, Completer<List<DetectionResult>>> pending,
  }) : _isolate = isolate,
       _receivePort = receivePort,
       _subscription = subscription,
       _sendPort = sendPort,
       _pending = pending;

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final StreamSubscription<Object?> _subscription;
  final SendPort _sendPort;
  final Map<int, Completer<List<DetectionResult>>> _pending;

  int _nextRequestId = 0;
  bool _isClosed = false;

  static Future<_PersistentInferenceWorker> start({
    required Uint8List modelBuffer,
    required List<String> labels,
    required double confidenceThresh,
    required double nmsIouThresh,
    required int inputH,
    required int inputW,
  }) async {
    final receivePort = ReceivePort();
    final ready = Completer<SendPort>();
    final pending = <int, Completer<List<DetectionResult>>>{};

    late final StreamSubscription<Object?> subscription;
    subscription = receivePort.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }

      if (message is _WorkerStartupError) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError(message.error),
            StackTrace.fromString(message.stackTrace),
          );
        }
        return;
      }

      if (message is _InferenceResponse) {
        final completer = pending.remove(message.id);
        if (completer == null || completer.isCompleted) return;

        final error = message.error;
        if (error != null) {
          completer.completeError(
            Exception(error),
            StackTrace.fromString(message.stackTrace ?? ''),
          );
        } else {
          completer.complete(message.detections);
        }
      }
    });

    final isolate = await Isolate.spawn(
      _inferenceWorkerMain,
      _WorkerInitMessage(
        replyTo: receivePort.sendPort,
        modelBuffer: modelBuffer,
        labels: labels,
        confidenceThresh: confidenceThresh,
        nmsIouThresh: nmsIouThresh,
        inputH: inputH,
        inputW: inputW,
      ),
      debugName: 'TFLiteInferenceWorker',
    );

    try {
      final sendPort = await ready.future;
      final worker = _PersistentInferenceWorker._(
        isolate: isolate,
        receivePort: receivePort,
        subscription: subscription,
        sendPort: sendPort,
        pending: pending,
      );
      debugPrint('[InferenceWorker] ✅ Ready');
      return worker;
    } catch (_) {
      await subscription.cancel();
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<List<DetectionResult>> runJpeg(Uint8List imageBytes) {
    return _run(
      _InferenceRequest.jpeg(id: _nextRequestId++, imageBytes: imageBytes),
    );
  }

  Future<List<DetectionResult>> runCameraFrame(CameraInferenceFrame frame) {
    return _run(
      _InferenceRequest.cameraFrame(id: _nextRequestId++, frame: frame),
    );
  }

  Future<List<DetectionResult>> _run(_InferenceRequest request) {
    if (_isClosed) {
      return Future.error(StateError('Inference worker is closed.'));
    }

    final completer = Completer<List<DetectionResult>>();
    _pending[request.id] = completer;
    _sendPort.send(request);
    return completer.future;
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _sendPort.send(const _CloseInferenceWorker());
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(const <DetectionResult>[]);
      }
    }
    _pending.clear();
    await _subscription.cancel();
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> _inferenceWorkerMain(_WorkerInitMessage init) async {
  final receivePort = ReceivePort();
  Interpreter? interpreter;

  try {
    interpreter = Interpreter.fromBuffer(
      init.modelBuffer,
      options: InterpreterOptions()..threads = 2,
    );
    init.replyTo.send(receivePort.sendPort);
  } catch (e, stack) {
    init.replyTo.send(_WorkerStartupError(e.toString(), stack.toString()));
    receivePort.close();
    return;
  }

  try {
    await for (final message in receivePort) {
      if (message is _CloseInferenceWorker) {
        break;
      }

      if (message is! _InferenceRequest) continue;

      try {
        final decoded = message.imageBytes != null
            ? img.decodeImage(message.imageBytes!)
            : InferenceService._decodeCameraFrame(message.frame!);

        if (decoded == null) {
          debugPrint('[InferenceWorker] ⚠ Unsupported or invalid camera frame');
          init.replyTo.send(
            _InferenceResponse(
              id: message.id,
              detections: const <DetectionResult>[],
            ),
          );
          continue;
        }

        final detections = InferenceService._runModelOnImage(
          interpreter: interpreter,
          decoded: decoded,
          labels: init.labels,
          detectorConfThresh: init.confidenceThresh,
          classifierConfThresh: InferenceService._classifierConfThresh,
          iouThresh: init.nmsIouThresh,
          inputH: init.inputH,
          inputW: init.inputW,
          frame: message.frame,
        );
        init.replyTo.send(
          _InferenceResponse(id: message.id, detections: detections),
        );
      } catch (e, stack) {
        init.replyTo.send(
          _InferenceResponse(
            id: message.id,
            detections: const <DetectionResult>[],
            error: e.toString(),
            stackTrace: stack.toString(),
          ),
        );
      }
    }
  } finally {
    interpreter.close();
    receivePort.close();
  }
}

class InferenceService {
  InferenceService._();

  static final InferenceService instance = InferenceService._();

  static const String _modelAsset = 'assets/models/best_int8.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';
  static const double _detectorConfThresh = 0.50;
  static const double _classifierConfThresh = 0.08;
  static const double _nmsThresh = 0.45;
  static const int _maxDetections = 8;
  static const int _classifierResize = 256;

  Uint8List? _modelBuffer;
  List<String> _labels = [];
  int _inputH = 320;
  int _inputW = 320;
  bool _isReady = false;
  _PersistentInferenceWorker? _worker;
  Future<_PersistentInferenceWorker>? _workerFuture;

  static const List<String> _fallbackLabels = [
    'background',
    'person',
    'chair',
    'table',
    'obstacle',
    'car',
    'bottle',
    'cup',
    'door',
    'laptop',
    'phone',
    'bag',
    'book',
    'stairs',
    'wall',
    'other',
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
    if (_isReady && _modelBuffer != null) return;

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
      await _ensureWorker();
      debugPrint('[Inference] ✅ Ready. H=$_inputH W=$_inputW');
    } catch (e, stack) {
      _isReady = false;
      await _worker?.close();
      _worker = null;
      _workerFuture = null;
      if (e.toString().contains('labels.txt')) {
        throw Exception(
          'Setup incomplete: labels file missing. Check assets/models/labels.txt',
        );
      }
      if (e.toString().contains('best_int8.tflite') ||
          e.toString().contains('.tflite')) {
        throw Exception('Setup incomplete: AI model file missing.');
      }
      debugPrint('[Inference] FATAL ERROR in initialize(): $e');
      debugPrint('$stack');
      rethrow;
    }
  }

  Future<List<DetectionResult>> runInference(Uint8List jpegBytes) async {
    if (!_isReady || _modelBuffer == null) return [];

    final worker = await _ensureWorker();
    return worker.runJpeg(jpegBytes);
  }

  Future<List<DetectionResult>> runInferenceOnCameraFrame(
    CameraInferenceFrame frame,
  ) async {
    if (!_isReady || _modelBuffer == null) return [];

    final worker = await _ensureWorker();
    return worker.runCameraFrame(frame);
  }

  Future<_PersistentInferenceWorker> _ensureWorker() async {
    final existing = _worker;
    if (existing != null) return existing;

    final inFlight = _workerFuture;
    if (inFlight != null) return inFlight;

    final modelBuffer = _modelBuffer;
    if (modelBuffer == null) {
      throw StateError('Inference model is not loaded.');
    }

    final future = _PersistentInferenceWorker.start(
      modelBuffer: modelBuffer,
      labels: _labels,
        confidenceThresh: _detectorConfThresh,
      nmsIouThresh: _nmsThresh,
      inputH: _inputH,
      inputW: _inputW,
    );
    _workerFuture = future;

    try {
      _worker = await future;
      return _worker!;
    } finally {
      _workerFuture = null;
    }
  }

  static List<DetectionResult> _runModelOnImage({
    required Interpreter interpreter,
    required img.Image decoded,
    required List<String> labels,
    required double detectorConfThresh,
    required double classifierConfThresh,
    required double iouThresh,
    required int inputH,
    required int inputW,
    CameraInferenceFrame? frame,
  }) {
    final outputTensor = interpreter.getOutputTensor(0);
    final outShape = outputTensor.shape;
    final isClassifier = outShape.length == 2;

    final processed = isClassifier
        ? _preprocessClassifierInput(
            decoded,
            cropSize: inputH,
            sensorOrientation: frame?.sensorOrientation ?? 0,
            isCameraFrame: frame != null,
          )
        : img.copyResize(decoded, width: inputW, height: inputH);

    final inputTensor = interpreter.getInputTensor(0);
    final input = isClassifier
        ? _imageToNestedInput(processed)
        : _imageToModelInput(processed, inputTensor);

    debugPrint(
      '[InferenceIsolate] Output shape: $outShape  type: ${outputTensor.type}',
    );

    if (isClassifier) {
      final numClasses = outShape[1];
      final output = [List<int>.filled(numClasses, 0)];
      interpreter.run(input, output);
      debugPrint('[InferenceIsolate] Inference complete.');

      final oriented = _orientClassifierImage(
        decoded,
        sensorOrientation: frame?.sensorOrientation ?? 0,
        isCameraFrame: frame != null,
      );
      final subjectBox = _estimateSubjectBoundingBox(oriented);
      final detections = _postProcessClassifierUint8(
        scores: output.first,
        labels: labels,
        confThresh: classifierConfThresh,
      );
      return _attachSubjectBoundingBox(detections, subjectBox);
    }

    final outputBytes = Uint8List(outputTensor.numBytes());
    interpreter.run(input, outputBytes);
    debugPrint('[InferenceIsolate] Inference complete.');

    final flatOutput = _decodeTensorOutput(outputBytes, outputTensor);

    if (outShape.length != 3) {
      debugPrint('[InferenceIsolate] Unsupported output shape: $outShape');
      return [];
    }

    return _postProcess(
      outputData: _reshapeOutput3D(flatOutput, outShape),
      outputShape: outShape,
      labels: labels,
      confThresh: detectorConfThresh,
      iouThresh: iouThresh,
      imgW: inputW.toDouble(),
      imgH: inputH.toDouble(),
    );
  }

  /// ImageNet MobileNet preprocessing: EXIF fix, camera rotation, resize + center crop.
  static img.Image _orientClassifierImage(
    img.Image image, {
    required int sensorOrientation,
    required bool isCameraFrame,
  }) {
    var processed = img.bakeOrientation(image);
    if (isCameraFrame && sensorOrientation != 0) {
      processed = img.copyRotate(processed, angle: sensorOrientation);
    }
    return processed;
  }

  static img.Image _preprocessClassifierInput(
    img.Image image, {
    required int cropSize,
    required int sensorOrientation,
    required bool isCameraFrame,
  }) {
    final processed = _orientClassifierImage(
      image,
      sensorOrientation: sensorOrientation,
      isCameraFrame: isCameraFrame,
    );

    final scale = _classifierResize / min(processed.width, processed.height);
    final newW = (processed.width * scale).round();
    final newH = (processed.height * scale).round();
    final resized = img.copyResize(processed, width: newW, height: newH);

    final x = max(0, (newW - cropSize) ~/ 2);
    final y = max(0, (newH - cropSize) ~/ 2);
    return img.copyCrop(
      resized,
      x: x,
      y: y,
      width: cropSize,
      height: cropSize,
    );
  }

  static List<List<List<List<int>>>> _imageToNestedInput(img.Image image) {
    return [
      List.generate(
        image.height,
        (y) => List.generate(
          image.width,
          (x) {
            final pixel = image.getPixel(x, y);
            return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
          },
        ),
      ),
    ];
  }

  static Object _imageToModelInput(img.Image resized, Tensor inputTensor) {
    final byteLength = resized.width * resized.height * 3;

    switch (inputTensor.type) {
      case TensorType.float32:
        final input = Float32List(byteLength);
        var offset = 0;
        for (int y = 0; y < resized.height; y++) {
          for (int x = 0; x < resized.width; x++) {
            final pixel = resized.getPixel(x, y);
            input[offset++] = pixel.r.toDouble();
            input[offset++] = pixel.g.toDouble();
            input[offset++] = pixel.b.toDouble();
          }
        }
        return input.buffer;
      case TensorType.int8:
        final input = Uint8List(byteLength);
        var offset = 0;
        for (int y = 0; y < resized.height; y++) {
          for (int x = 0; x < resized.width; x++) {
            final pixel = resized.getPixel(x, y);
            input[offset++] = _signedByte(pixel.r.toInt());
            input[offset++] = _signedByte(pixel.g.toInt());
            input[offset++] = _signedByte(pixel.b.toInt());
          }
        }
        return input;
      case TensorType.uint8:
        final input = Uint8List(byteLength);
        var offset = 0;
        for (int y = 0; y < resized.height; y++) {
          for (int x = 0; x < resized.width; x++) {
            final pixel = resized.getPixel(x, y);
            input[offset++] = pixel.r.toInt().clamp(0, 255).toInt();
            input[offset++] = pixel.g.toInt().clamp(0, 255).toInt();
            input[offset++] = pixel.b.toInt().clamp(0, 255).toInt();
          }
        }
        return input;
      default:
        throw UnsupportedError(
          'Unsupported TFLite input type: ${inputTensor.type}',
        );
    }
  }

  static int _signedByte(int value) {
    return ((value - 128).clamp(-128, 127).toInt()) & 0xFF;
  }

  static List<double> _decodeTensorOutput(Uint8List bytes, Tensor tensor) {
    final byteData = ByteData.sublistView(bytes);

    switch (tensor.type) {
      case TensorType.float32:
        return List<double>.generate(
          bytes.length ~/ 4,
          (i) => byteData.getFloat32(i * 4, Endian.little),
          growable: false,
        );
      case TensorType.uint8:
        return List<double>.generate(
          bytes.length,
          (i) => _dequantize(byteData.getUint8(i), tensor),
          growable: false,
        );
      case TensorType.int8:
        return List<double>.generate(
          bytes.length,
          (i) => _dequantize(byteData.getInt8(i), tensor),
          growable: false,
        );
      case TensorType.int16:
        return List<double>.generate(
          bytes.length ~/ 2,
          (i) => _dequantize(byteData.getInt16(i * 2, Endian.little), tensor),
          growable: false,
        );
      case TensorType.int32:
        return List<double>.generate(
          bytes.length ~/ 4,
          (i) => _dequantize(byteData.getInt32(i * 4, Endian.little), tensor),
          growable: false,
        );
      default:
        throw UnsupportedError(
          'Unsupported TFLite output type: ${tensor.type}',
        );
    }
  }

  static double _dequantize(num rawValue, Tensor tensor) {
    try {
      final params = tensor.params;
      if (params.scale != 0) {
        return (rawValue - params.zeroPoint) * params.scale;
      }
    } catch (_) {
      // Quantization params are not always available on every runtime.
    }
    return rawValue.toDouble();
  }

  static List<List<List<double>>> _reshapeOutput3D(
    List<double> flatOutput,
    List<int> shape,
  ) {
    var index = 0;
    return List.generate(
      shape[0],
      (_) => List.generate(
        shape[1],
        (_) => List.generate(
          shape[2],
          (_) => flatOutput[index++],
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    );
  }

  static img.Image? _decodeCameraFrame(CameraInferenceFrame frame) {
    final format = frame.formatGroup.toLowerCase();
    if (format.contains('jpeg') && frame.planes.isNotEmpty) {
      return img.decodeImage(frame.planes.first);
    }
    if (format.contains('bgra')) {
      return _bgra8888ToImage(frame);
    }
    if (format.contains('yuv420')) {
      return _yuv420ToImage(frame);
    }
    return null;
  }

  static img.Image? _bgra8888ToImage(CameraInferenceFrame frame) {
    if (frame.planes.isEmpty) return null;

    final bytes = frame.planes.first;
    final rowStride = _rowStride(frame, 0, frame.width * 4);
    final pixelStride = _pixelStride(frame, 0, 4);
    final output = img.Image(width: frame.width, height: frame.height);

    for (int y = 0; y < frame.height; y++) {
      for (int x = 0; x < frame.width; x++) {
        final index = y * rowStride + x * pixelStride;
        if (index + 2 >= bytes.length) continue;

        final b = bytes[index];
        final g = bytes[index + 1];
        final r = bytes[index + 2];
        output.setPixelRgb(x, y, r, g, b);
      }
    }

    return output;
  }

  static img.Image? _yuv420ToImage(CameraInferenceFrame frame) {
    if (frame.planes.length < 3) return null;

    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final yRowStride = _rowStride(frame, 0, frame.width);
    final uvRowStride = _rowStride(frame, 1, frame.width ~/ 2);
    final uvPixelStride = _pixelStride(frame, 1, 1);
    final output = img.Image(width: frame.width, height: frame.height);

    for (int y = 0; y < frame.height; y++) {
      for (int x = 0; x < frame.width; x++) {
        final yIndex = y * yRowStride + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
        if (yIndex >= yPlane.length ||
            uvIndex >= uPlane.length ||
            uvIndex >= vPlane.length) {
          continue;
        }

        final yValue = yPlane[yIndex].toDouble();
        final uValue = uPlane[uvIndex].toDouble() - 128.0;
        final vValue = vPlane[uvIndex].toDouble() - 128.0;

        final r = _clampByte(yValue + 1.403 * vValue);
        final g = _clampByte(yValue - 0.344 * uValue - 0.714 * vValue);
        final b = _clampByte(yValue + 1.770 * uValue);
        output.setPixelRgb(x, y, r, g, b);
      }
    }

    return output;
  }

  static int _rowStride(
    CameraInferenceFrame frame,
    int planeIndex,
    int fallback,
  ) {
    if (planeIndex >= frame.bytesPerRow.length) return fallback;
    return frame.bytesPerRow[planeIndex];
  }

  static int _pixelStride(
    CameraInferenceFrame frame,
    int planeIndex,
    int fallback,
  ) {
    if (planeIndex >= frame.bytesPerPixel.length) return fallback;
    final stride = frame.bytesPerPixel[planeIndex];
    return stride <= 0 ? fallback : stride;
  }

  static int _clampByte(num value) {
    return value.round().clamp(0, 255).toInt();
  }

  /// MobileNet quantized classifiers output uint8 logits in [0, 255].
  static List<DetectionResult> _postProcessClassifierUint8({
    required List<int> scores,
    required List<String> labels,
    required double confThresh,
  }) {
    if (scores.isEmpty) return [];

    final indexes = List<int>.generate(scores.length, (index) => index);
    final hasBackgroundLabel =
        labels.isNotEmpty && labels.first.toLowerCase() == 'background';
    if (hasBackgroundLabel && indexes.length > 1) {
      indexes.remove(0);
    }

    indexes.sort((a, b) => scores[b].compareTo(scores[a]));

    if (kDebugMode && indexes.isNotEmpty) {
      final summary = indexes
          .take(3)
          .map((i) {
            final label = i < labels.length ? labels[i] : 'class $i';
            final pct = (scores[i] / 255.0 * 100).round();
            return '$label $pct%';
          })
          .join(', ');
      debugPrint('[PostProcess] classifier top: $summary');
    }

    final detections = <DetectionResult>[];
    for (final index in indexes.take(_maxDetections)) {
      final confidence = (scores[index] / 255.0).clamp(0.0, 1.0).toDouble();
      if (confidence < confThresh) continue;

      final label = index < labels.length ? labels[index] : 'class $index';
      detections.add(
        DetectionResult(
          label: label,
          confidence: confidence,
          boundingBox: ui.Rect.zero,
        ),
      );
    }

    return detections;
  }

  /// Estimates a tight normalized box around the main subject in the frame.
  static ui.Rect _estimateSubjectBoundingBox(img.Image image) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) {
      return _centerCropNormalizedRect(1, 1, _classifierResize);
    }

    const analysisSize = 128;
    final scale = analysisSize / max(width, height);
    final sampleW = max(1, (width * scale).round());
    final sampleH = max(1, (height * scale).round());
    final sample = img.copyResize(image, width: sampleW, height: sampleH);

    double bgR = 0;
    double bgG = 0;
    double bgB = 0;
    var borderCount = 0;

    void sampleBorderPixel(int x, int y) {
      final pixel = sample.getPixel(x, y);
      bgR += pixel.r;
      bgG += pixel.g;
      bgB += pixel.b;
      borderCount++;
    }

    for (var x = 0; x < sampleW; x++) {
      sampleBorderPixel(x, 0);
      sampleBorderPixel(x, sampleH - 1);
    }
    for (var y = 1; y < sampleH - 1; y++) {
      sampleBorderPixel(0, y);
      sampleBorderPixel(sampleW - 1, y);
    }

    bgR /= borderCount;
    bgG /= borderCount;
    bgB /= borderCount;

    final saliency = List<double>.filled(sampleW * sampleH, 0);
    var maxScore = 0.0;

    for (var y = 0; y < sampleH; y++) {
      for (var x = 0; x < sampleW; x++) {
        final pixel = sample.getPixel(x, y);
        final dr = pixel.r - bgR;
        final dg = pixel.g - bgG;
        final db = pixel.b - bgB;
        final colorDist = sqrt(dr * dr + dg * dg + db * db);

        final right =
            x < sampleW - 1 ? sample.getPixel(x + 1, y) : pixel;
        final down =
            y < sampleH - 1 ? sample.getPixel(x, y + 1) : pixel;
        final edge = (pixel.r - right.r).abs() +
            (pixel.g - right.g).abs() +
            (pixel.b - right.b).abs() +
            (pixel.r - down.r).abs() +
            (pixel.g - down.g).abs() +
            (pixel.b - down.b).abs();

        final centerWeight =
            1.0 - (((x / sampleW) - 0.5).abs() + ((y / sampleH) - 0.5).abs());
        final score = (colorDist * 0.75 + edge * 0.25) * centerWeight;
        saliency[y * sampleW + x] = score;
        if (score > maxScore) maxScore = score;
      }
    }

    if (maxScore <= 2.0) {
      return _centerCropNormalizedRect(width, height, _classifierResize);
    }

    final threshold = maxScore * 0.42;
    var minX = sampleW;
    var minY = sampleH;
    var maxX = 0;
    var maxY = 0;
    var hitCount = 0;

    for (var y = 0; y < sampleH; y++) {
      for (var x = 0; x < sampleW; x++) {
        if (saliency[y * sampleW + x] < threshold) continue;
        minX = min(minX, x);
        minY = min(minY, y);
        maxX = max(maxX, x);
        maxY = max(maxY, y);
        hitCount++;
      }
    }

    if (hitCount < 6) {
      return _centerCropNormalizedRect(width, height, _classifierResize);
    }

    final boxW = (maxX - minX + 1) / sampleW;
    final boxH = (maxY - minY + 1) / sampleH;
    final padX = boxW * 0.1;
    final padY = boxH * 0.1;

    final left = (minX / sampleW - padX).clamp(0.0, 1.0);
    final top = (minY / sampleH - padY).clamp(0.0, 1.0);
    final right = ((maxX + 1) / sampleW + padX).clamp(0.0, 1.0);
    final bottom = ((maxY + 1) / sampleH + padY).clamp(0.0, 1.0);

    return _clampNormalizedRect(
      left,
      top,
      right,
      bottom,
      minSize: 0.12,
      maxSize: 0.62,
    );
  }

  static ui.Rect _centerCropNormalizedRect(
    int imageW,
    int imageH,
    int cropSize,
  ) {
    if (imageW <= 0 || imageH <= 0) {
      return const ui.Rect.fromLTWH(0.3, 0.3, 0.4, 0.4);
    }

    final scale = _classifierResize / min(imageW, imageH);
    final resizedW = imageW * scale;
    final resizedH = imageH * scale;
    final cropW = min(cropSize.toDouble(), resizedW);
    final cropH = min(cropSize.toDouble(), resizedH);
    final x = max(0.0, (resizedW - cropW) / 2) / resizedW;
    final y = max(0.0, (resizedH - cropH) / 2) / resizedH;
    final w = cropW / resizedW;
    final h = cropH / resizedH;

    return _clampNormalizedRect(
      x,
      y,
      x + w,
      y + h,
      minSize: 0.18,
      maxSize: 0.55,
    );
  }

  static ui.Rect _clampNormalizedRect(
    double left,
    double top,
    double right,
    double bottom, {
    required double minSize,
    required double maxSize,
  }) {
    var width = (right - left).clamp(minSize, maxSize);
    var height = (bottom - top).clamp(minSize, maxSize);
    var l = left;
    var t = top;

    if (l + width > 1.0) l = 1.0 - width;
    if (t + height > 1.0) t = 1.0 - height;
    l = l.clamp(0.0, 1.0 - width);
    t = t.clamp(0.0, 1.0 - height);

    width = min(width, maxSize);
    height = min(height, maxSize);

    return ui.Rect.fromLTWH(l, t, width, height);
  }

  static List<DetectionResult> _attachSubjectBoundingBox(
    List<DetectionResult> detections,
    ui.Rect subjectBox,
  ) {
    if (detections.isEmpty) return detections;

    return detections.asMap().entries.map((entry) {
      final detection = entry.value;
      return DetectionResult(
        label: detection.label,
        confidence: detection.confidence,
        boundingBox: entry.key == 0 ? subjectBox : ui.Rect.zero,
      );
    }).toList();
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

    debugPrint(
      '[PostProcess] Layout: ${isTransposed ? 'channel-first' : 'anchor-major'}',
    );
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

    final kept = _nms(
      rawBoxes,
      rawScores,
      rawClasses,
      iouThresh,
    ).take(_maxDetections);
    final detections = kept.map((i) {
      final label = rawClasses[i] < labels.length
          ? labels[rawClasses[i]]
          : 'unknown';
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

    if (kDebugMode && detections.isNotEmpty) {
      final summary = detections
          .map((d) => '${d.label} ${(d.confidence * 100).round()}%')
          .join(', ');
      debugPrint('[PostProcess] ${detections.length} detections: $summary');
    }

    return detections;
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
    final union =
        (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter;
    if (union <= 0) return 0.0;
    return inter / union;
  }
}
