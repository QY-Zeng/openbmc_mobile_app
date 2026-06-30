import 'alert_item.dart';

class AlertStreamEvent {
  const AlertStreamEvent({
    required this.eventType,
    required this.alert,
    required this.emittedAt,
  });

  final String eventType;
  final AlertItem alert;
  final String emittedAt;

  bool get shouldShowPopup =>
      alert.isOpen &&
      (eventType == 'opened' || eventType == 'severity_changed');

  factory AlertStreamEvent.fromJson(Map<String, dynamic> json) {
    return AlertStreamEvent(
      eventType: json['eventType'] as String,
      alert: AlertItem.fromJson(json['alert'] as Map<String, dynamic>),
      emittedAt: json['emittedAt'] as String,
    );
  }
}
