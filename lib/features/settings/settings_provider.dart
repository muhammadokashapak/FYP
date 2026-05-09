import 'package:flutter/foundation.dart';

import '../../services/settings_service.dart';

/// Exposes settings state and persists changes via SettingsService.
/// Notifies listeners so UI (including root theme) updates.
class SettingsProvider extends ChangeNotifier {
  bool _isDarkTheme = false;
  bool _notificationsEnabled = true;
  int _cameraResolutionIndex = 1;

  SettingsProvider() {
    _load();
  }

  void _load() {
    _isDarkTheme = SettingsService.isDarkTheme;
    _notificationsEnabled = SettingsService.notificationsEnabled;
    _cameraResolutionIndex = SettingsService.cameraResolutionIndex;
  }

  bool get isDarkTheme => _isDarkTheme;
  bool get notificationsEnabled => _notificationsEnabled;
  int get cameraResolutionIndex => _cameraResolutionIndex;

  Future<void> setDarkTheme(bool value) async {
    if (_isDarkTheme == value) return;
    _isDarkTheme = value;
    await SettingsService.setDarkTheme(value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    await SettingsService.setNotificationsEnabled(value);
    notifyListeners();
  }

  Future<void> setCameraResolutionIndex(int index) async {
    if (_cameraResolutionIndex == index) return;
    _cameraResolutionIndex = index;
    await SettingsService.setCameraResolutionIndex(index);
    notifyListeners();
  }
}
