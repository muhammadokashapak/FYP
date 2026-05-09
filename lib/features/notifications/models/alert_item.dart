/// Single alert entry for the notifications list.
/// Structure prepared for real-time alerts (e.g. from AI/ESP32) later.
enum AlertType {
  motion,
  object,
  person,
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.read = false,
  });

  final String id;
  final AlertType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool read;

  String get typeLabel {
    switch (type) {
      case AlertType.motion:
        return 'Motion';
      case AlertType.object:
        return 'Object';
      case AlertType.person:
        return 'Person';
    }
  }
}
