import 'package:camera/camera.dart';

/// Thin helper around `CameraController` for future expansion.
/// For now this just centralizes a couple of camera-related utilities.
class CameraService {
  CameraService._();

  static final CameraService instance = CameraService._();

  /// Returns true if the given controller looks like a back camera with flash.
  bool hasFlash(CameraController? controller) {
    if (controller == null) return false;
    return controller.description.lensDirection == CameraLensDirection.back;
  }
}

