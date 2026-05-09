import 'package:flutter/foundation.dart';

import '../../services/detection_service.dart';

/// ChangeNotifier to manage model loading state and provide access to DetectionService.
///
/// Usage in widgets with Consumer:
/// ```dart
/// Consumer<ModelLoaderProvider>(
///   builder: (context, modelProvider, child) {
///     if (modelProvider.isLoading) {
///       return const CircularProgressIndicator();
///     }
///     if (modelProvider.error != null) {
///       return Text('Error: ${modelProvider.error}');
///     }
///     return Text('Model ready');
///   },
/// )
/// ```
class ModelLoaderProvider extends ChangeNotifier {
  ModelLoaderProvider._();

  static final ModelLoaderProvider instance = ModelLoaderProvider._();

  bool _isLoading = false;
  String? _error;
  DetectionService? _service;

  bool get isLoading => _isLoading;
  String? get error => _error;
  DetectionService? get service => _service;
  bool get isReady => _service?.isReady ?? false;

  /// Initialize the TFLite model. Call this once during app startup.
  Future<void> init() async {
    if (_isLoading || _service != null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _service = DetectionService.instance;
      await _service!.init();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('ModelLoaderProvider error: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset the provider (useful for debugging or app reload).
  void reset() {
    _service = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
