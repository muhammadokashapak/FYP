import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';

/// Handles persisting and loading app settings (theme, notifications, resolution).
/// Uses SharedPreferences; can be extended for Firebase/remote config later.
class SettingsService {
  SettingsService._();
  static late final SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get isDarkTheme =>
      _prefs.getBool(PrefsKeys.isDarkTheme) ?? false;

  static Future<void> setDarkTheme(bool value) async {
    await _prefs.setBool(PrefsKeys.isDarkTheme, value);
  }

  static bool get notificationsEnabled =>
      _prefs.getBool(PrefsKeys.notificationsEnabled) ?? true;

  static Future<void> setNotificationsEnabled(bool value) async {
    await _prefs.setBool(PrefsKeys.notificationsEnabled, value);
  }

  /// Index into CameraResolutions.labels (0 = Low, 1 = Medium, 2 = High).
  static int get cameraResolutionIndex =>
      _prefs.getInt(PrefsKeys.cameraResolutionIndex) ?? 1;

  static Future<void> setCameraResolutionIndex(int index) async {
    await _prefs.setInt(PrefsKeys.cameraResolutionIndex, index);
  }
}
