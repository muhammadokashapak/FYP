import 'package:flutter/foundation.dart';

import 'models/alert_item.dart';

/// Holds the list of alerts. Currently uses dummy data; later can be
/// replaced with real-time stream (Firebase, WebSocket, etc.).
class NotificationsProvider extends ChangeNotifier {
  final List<AlertItem> _items = [];
  List<AlertItem> get items => List.unmodifiable(_items);

  NotificationsProvider() {
    _loadDummyAlerts();
  }

  void _loadDummyAlerts() {
    final now = DateTime.now();
    _items.addAll([
      AlertItem(
        id: '1',
        type: AlertType.motion,
        title: 'Motion detected',
        message: 'Movement detected in camera view.',
        timestamp: now.subtract(const Duration(minutes: 2)),
      ),
      AlertItem(
        id: '2',
        type: AlertType.object,
        title: 'Object detected',
        message: 'Key object identified in frame.',
        timestamp: now.subtract(const Duration(minutes: 15)),
      ),
      AlertItem(
        id: '3',
        type: AlertType.person,
        title: 'Person detected',
        message: 'Face/person detected in view.',
        timestamp: now.subtract(const Duration(hours: 1)),
        read: true,
      ),
    ]);
  }

  void markAsRead(String id) {
    final index = _items.indexWhere((e) => e.id == id);
    if (index >= 0 && !_items[index].read) {
      _items[index] = AlertItem(
        id: _items[index].id,
        type: _items[index].type,
        title: _items[index].title,
        message: _items[index].message,
        timestamp: _items[index].timestamp,
        read: true,
      );
      notifyListeners();
    }
  }

  /// For future use: add alert from real-time source.
  void addAlert(AlertItem item) {
    _items.insert(0, item);
    notifyListeners();
  }
}
