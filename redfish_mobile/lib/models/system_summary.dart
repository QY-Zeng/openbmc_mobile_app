class SystemSummary {
  const SystemSummary({
    required this.id,
    required this.name,
    required this.hostName,
    required this.manufacturer,
    required this.model,
    required this.systemType,
    required this.serialNumber,
    required this.powerState,
    required this.indicatorLed,
    required this.health,
    required this.state,
    required this.processorCount,
    required this.processorModel,
    required this.memoryGiB,
    required this.redfishUri,
  });

  final String id;
  final String? name;
  final String? hostName;
  final String? manufacturer;
  final String? model;
  final String? systemType;
  final String? serialNumber;
  final String? powerState;
  final String? indicatorLed;
  final String? health;
  final String? state;
  final int? processorCount;
  final String? processorModel;
  final double? memoryGiB;
  final String? redfishUri;

  factory SystemSummary.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as Map<String, dynamic>?) ?? {};
    return SystemSummary(
      id: json['id'] as String,
      name: json['name'] as String?,
      hostName: json['hostName'] as String?,
      manufacturer: json['manufacturer'] as String?,
      model: json['model'] as String?,
      systemType: json['systemType'] as String?,
      serialNumber: json['serialNumber'] as String?,
      powerState: json['powerState'] as String?,
      indicatorLed: json['indicatorLed'] as String?,
      health: status['health'] as String?,
      state: status['state'] as String?,
      processorCount: (json['processorCount'] as num?)?.toInt(),
      processorModel: json['processorModel'] as String?,
      memoryGiB: (json['memoryGiB'] as num?)?.toDouble(),
      redfishUri: json['redfishUri'] as String?,
    );
  }
}
