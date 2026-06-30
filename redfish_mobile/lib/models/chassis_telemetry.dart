class ChassisTelemetryCurrent {
  const ChassisTelemetryCurrent({
    required this.chassisId,
    required this.timestamp,
    required this.summary,
    required this.temperatures,
    required this.fans,
    required this.powerControls,
    required this.powerSupplies,
  });

  final String chassisId;
  final String timestamp;
  final TelemetrySummary summary;
  final List<TemperatureReading> temperatures;
  final List<FanReading> fans;
  final List<PowerControlReading> powerControls;
  final List<PowerSupplyReading> powerSupplies;

  factory ChassisTelemetryCurrent.fromJson(Map<String, dynamic> json) {
    final temperatures = json['temperatures'] as List<dynamic>? ?? const [];
    final fans = json['fans'] as List<dynamic>? ?? const [];
    final powerControls = json['powerControls'] as List<dynamic>? ?? const [];
    final powerSupplies = json['powerSupplies'] as List<dynamic>? ?? const [];

    return ChassisTelemetryCurrent(
      chassisId: json['chassisId'] as String,
      timestamp: json['timestamp'] as String,
      summary: TelemetrySummary.fromJson(
        (json['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      temperatures: temperatures
          .map(
            (item) => TemperatureReading.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      fans: fans
          .map((item) => FanReading.fromJson(item as Map<String, dynamic>))
          .toList(),
      powerControls: powerControls
          .map(
            (item) =>
                PowerControlReading.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      powerSupplies: powerSupplies
          .map(
            (item) => PowerSupplyReading.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class TelemetrySummary {
  const TelemetrySummary({
    required this.temperatureCelsius,
    required this.powerWatts,
    required this.health,
  });

  final double? temperatureCelsius;
  final double? powerWatts;
  final String? health;

  factory TelemetrySummary.fromJson(Map<String, dynamic> json) {
    return TelemetrySummary(
      temperatureCelsius: (json['temperatureCelsius'] as num?)?.toDouble(),
      powerWatts: (json['powerWatts'] as num?)?.toDouble(),
      health: json['health'] as String?,
    );
  }
}

class TemperatureReading {
  const TemperatureReading({
    required this.id,
    required this.name,
    required this.celsius,
    required this.health,
    required this.state,
    required this.physicalContext,
    required this.upperCaution,
    required this.upperCritical,
    required this.upperFatal,
  });

  final String id;
  final String? name;
  final double? celsius;
  final String? health;
  final String? state;
  final String? physicalContext;
  final double? upperCaution;
  final double? upperCritical;
  final double? upperFatal;

  factory TemperatureReading.fromJson(Map<String, dynamic> json) {
    return TemperatureReading(
      id: json['id'] as String,
      name: json['name'] as String?,
      celsius: (json['celsius'] as num?)?.toDouble(),
      health: json['health'] as String?,
      state: json['state'] as String?,
      physicalContext: json['physicalContext'] as String?,
      upperCaution: (json['upperCaution'] as num?)?.toDouble(),
      upperCritical: (json['upperCritical'] as num?)?.toDouble(),
      upperFatal: (json['upperFatal'] as num?)?.toDouble(),
    );
  }
}

class FanReading {
  const FanReading({
    required this.id,
    required this.name,
    required this.rpm,
    required this.health,
    required this.state,
    required this.physicalContext,
  });

  final String id;
  final String? name;
  final double? rpm;
  final String? health;
  final String? state;
  final String? physicalContext;

  factory FanReading.fromJson(Map<String, dynamic> json) {
    return FanReading(
      id: json['id'] as String,
      name: json['name'] as String?,
      rpm: (json['rpm'] as num?)?.toDouble(),
      health: json['health'] as String?,
      state: json['state'] as String?,
      physicalContext: json['physicalContext'] as String?,
    );
  }
}

class PowerControlReading {
  const PowerControlReading({
    required this.id,
    required this.name,
    required this.consumedWatts,
    required this.averageWatts,
    required this.peakWatts,
    required this.capacityWatts,
    required this.allocatedWatts,
    required this.health,
    required this.state,
  });

  final String id;
  final String? name;
  final double? consumedWatts;
  final double? averageWatts;
  final double? peakWatts;
  final double? capacityWatts;
  final double? allocatedWatts;
  final String? health;
  final String? state;

  factory PowerControlReading.fromJson(Map<String, dynamic> json) {
    return PowerControlReading(
      id: json['id'] as String,
      name: json['name'] as String?,
      consumedWatts: (json['consumedWatts'] as num?)?.toDouble(),
      averageWatts: (json['averageWatts'] as num?)?.toDouble(),
      peakWatts: (json['peakWatts'] as num?)?.toDouble(),
      capacityWatts: (json['capacityWatts'] as num?)?.toDouble(),
      allocatedWatts: (json['allocatedWatts'] as num?)?.toDouble(),
      health: json['health'] as String?,
      state: json['state'] as String?,
    );
  }
}

class PowerSupplyReading {
  const PowerSupplyReading({
    required this.id,
    required this.name,
    required this.lastOutputWatts,
    required this.capacityWatts,
    required this.health,
    required this.state,
    required this.model,
    required this.firmwareVersion,
  });

  final String id;
  final String? name;
  final double? lastOutputWatts;
  final double? capacityWatts;
  final String? health;
  final String? state;
  final String? model;
  final String? firmwareVersion;

  factory PowerSupplyReading.fromJson(Map<String, dynamic> json) {
    return PowerSupplyReading(
      id: json['id'] as String,
      name: json['name'] as String?,
      lastOutputWatts: (json['lastOutputWatts'] as num?)?.toDouble(),
      capacityWatts: (json['capacityWatts'] as num?)?.toDouble(),
      health: json['health'] as String?,
      state: json['state'] as String?,
      model: json['model'] as String?,
      firmwareVersion: json['firmwareVersion'] as String?,
    );
  }
}
