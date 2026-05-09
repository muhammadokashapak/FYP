/// Application-wide constants for Chasham AI.
/// Central place for strings, keys, and config used across features.
library;

/// Keys used with SharedPreferences (settings persistence).
class PrefsKeys {
  PrefsKeys._();
  static const String isDarkTheme = 'is_dark_theme';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String cameraResolutionIndex = 'camera_resolution_index';
}

/// Supported camera resolution labels (for UI dropdown).
/// Actual resolution values are mapped in camera feature.
class CameraResolutions {
  CameraResolutions._();
  static const List<String> labels = [
    'Low (320p)',
    'Medium (720p)',
    'High (1080p)',
  ];
}

/// App display name and version for About section.
class AppInfo {
  AppInfo._();
  static const String name = 'Chasham AI';
  static const String version = '1.0.0';
}

/// ESP32-CAM stream configuration.
class ESP32Config {
  ESP32Config._();
  static const String ip = '192.168.137.176';
  /// Active MJPEG stream URL for ESP32-CAM (centralized).
  static const String streamUrl = 'http://192.168.137.176:81/stream';
  static const String baseUrl = 'http://192.168.137.176';
  static const String captureUrl = 'http://192.168.137.176/capture';
}
