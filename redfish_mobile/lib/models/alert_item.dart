class AlertItem {
  const AlertItem({
    required this.id,
    required this.sourceKey,
    required this.chassisId,
    required this.severity,
    required this.category,
    required this.title,
    required this.message,
    required this.status,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.resolvedAt,
  });

  final int id;
  final String sourceKey;
  final String chassisId;
  final String severity;
  final String category;
  final String title;
  final String message;
  final String status;
  final String firstSeenAt;
  final String lastSeenAt;
  final String? resolvedAt;

  bool get isOpen => status.toLowerCase() == 'open';

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: json['id'] as int,
      sourceKey: json['sourceKey'] as String,
      chassisId: json['chassisId'] as String,
      severity: json['severity'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      status: json['status'] as String,
      firstSeenAt: json['firstSeenAt'] as String,
      lastSeenAt: json['lastSeenAt'] as String,
      resolvedAt: json['resolvedAt'] as String?,
    );
  }
}
