class ChassisDetail {
  const ChassisDetail({
    required this.id,
    required this.name,
    required this.chassisType,
    required this.manufacturer,
    required this.model,
    required this.serialNumber,
    required this.powerState,
    required this.indicatorLed,
    required this.health,
    required this.state,
    required this.thermalUri,
    required this.powerUri,
    required this.sensorsUri,
    required this.environmentMetricsUri,
    required this.computerSystemIds,
    required this.redfishUri,
    required this.assetTag,
    required this.heightMm,
    required this.widthMm,
    required this.depthMm,
    required this.weightKg,
    required this.rack,
    required this.row,
    required this.managedByUris,
    required this.managerUris,
  });

  final String id;
  final String? name;
  final String? chassisType;
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String? powerState;
  final String? indicatorLed;
  final String? health;
  final String? state;
  final String? thermalUri;
  final String? powerUri;
  final String? sensorsUri;
  final String? environmentMetricsUri;
  final List<String> computerSystemIds;
  final String? redfishUri;
  final String? assetTag;
  final double? heightMm;
  final double? widthMm;
  final double? depthMm;
  final double? weightKg;
  final String? rack;
  final String? row;
  final List<String> managedByUris;
  final List<String> managerUris;

  factory ChassisDetail.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as Map<String, dynamic>?) ?? const {};
    final computerSystemIds =
        json['computerSystemIds'] as List<dynamic>? ?? const [];
    final managedByUris = json['managedByUris'] as List<dynamic>? ?? const [];
    final managerUris = json['managerUris'] as List<dynamic>? ?? const [];

    return ChassisDetail(
      id: json['id'] as String,
      name: json['name'] as String?,
      chassisType: json['chassisType'] as String?,
      manufacturer: json['manufacturer'] as String?,
      model: json['model'] as String?,
      serialNumber: json['serialNumber'] as String?,
      powerState: json['powerState'] as String?,
      indicatorLed: json['indicatorLed'] as String?,
      health: status['health'] as String?,
      state: status['state'] as String?,
      thermalUri: json['thermalUri'] as String?,
      powerUri: json['powerUri'] as String?,
      sensorsUri: json['sensorsUri'] as String?,
      environmentMetricsUri: json['environmentMetricsUri'] as String?,
      computerSystemIds: computerSystemIds
          .map((item) => item as String)
          .toList(),
      redfishUri: json['redfishUri'] as String?,
      assetTag: json['assetTag'] as String?,
      heightMm: (json['heightMm'] as num?)?.toDouble(),
      widthMm: (json['widthMm'] as num?)?.toDouble(),
      depthMm: (json['depthMm'] as num?)?.toDouble(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      rack: json['rack'] as String?,
      row: json['row'] as String?,
      managedByUris: managedByUris.map((item) => item as String).toList(),
      managerUris: managerUris.map((item) => item as String).toList(),
    );
  }
}
