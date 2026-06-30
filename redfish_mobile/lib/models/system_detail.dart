import 'system_summary.dart';

class SystemDetail extends SystemSummary {
  const SystemDetail({
    required super.id,
    required super.name,
    required super.hostName,
    required super.manufacturer,
    required super.model,
    required super.systemType,
    required super.serialNumber,
    required super.powerState,
    required super.indicatorLed,
    required super.health,
    required super.state,
    required super.processorCount,
    required super.processorModel,
    required super.memoryGiB,
    required super.redfishUri,
    required this.assetTag,
    required this.description,
    required this.biosVersion,
    required this.lastResetTime,
    required this.boot,
    required this.links,
    required this.actions,
  });

  final String? assetTag;
  final String? description;
  final String? biosVersion;
  final String? lastResetTime;
  final SystemBootInfo boot;
  final SystemLinks links;
  final SystemActions actions;

  factory SystemDetail.fromJson(Map<String, dynamic> json) {
    final summary = SystemSummary.fromJson(json);
    return SystemDetail(
      id: summary.id,
      name: summary.name,
      hostName: summary.hostName,
      manufacturer: summary.manufacturer,
      model: summary.model,
      systemType: summary.systemType,
      serialNumber: summary.serialNumber,
      powerState: summary.powerState,
      indicatorLed: summary.indicatorLed,
      health: summary.health,
      state: summary.state,
      processorCount: summary.processorCount,
      processorModel: summary.processorModel,
      memoryGiB: summary.memoryGiB,
      redfishUri: summary.redfishUri,
      assetTag: json['assetTag'] as String?,
      description: json['description'] as String?,
      biosVersion: json['biosVersion'] as String?,
      lastResetTime: json['lastResetTime'] as String?,
      boot: SystemBootInfo.fromJson(
        (json['boot'] as Map<String, dynamic>?) ?? const {},
      ),
      links: SystemLinks.fromJson(
        (json['links'] as Map<String, dynamic>?) ?? const {},
      ),
      actions: SystemActions.fromJson(
        (json['actions'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

class SystemActions {
  const SystemActions({required this.reset});

  final SystemResetAction reset;

  factory SystemActions.fromJson(Map<String, dynamic> json) {
    return SystemActions(
      reset: SystemResetAction.fromJson(
        (json['reset'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

class SystemResetAction {
  const SystemResetAction({
    required this.target,
    required this.allowableValues,
  });

  final String? target;
  final List<String> allowableValues;

  factory SystemResetAction.fromJson(Map<String, dynamic> json) {
    final allowableValues =
        json['allowableValues'] as List<dynamic>? ?? const [];
    return SystemResetAction(
      target: json['target'] as String?,
      allowableValues: allowableValues.whereType<String>().toList(
        growable: false,
      ),
    );
  }
}

class SystemBootInfo {
  const SystemBootInfo({
    required this.overrideEnabled,
    required this.overrideTarget,
    required this.overrideMode,
  });

  final String? overrideEnabled;
  final String? overrideTarget;
  final String? overrideMode;

  factory SystemBootInfo.fromJson(Map<String, dynamic> json) {
    return SystemBootInfo(
      overrideEnabled: json['overrideEnabled'] as String?,
      overrideTarget: json['overrideTarget'] as String?,
      overrideMode: json['overrideMode'] as String?,
    );
  }
}

class SystemLinks {
  const SystemLinks({
    required this.biosUri,
    required this.processorsUri,
    required this.memoryUri,
    required this.ethernetInterfacesUri,
    required this.chassisUris,
  });

  final String? biosUri;
  final String? processorsUri;
  final String? memoryUri;
  final String? ethernetInterfacesUri;
  final List<String> chassisUris;

  factory SystemLinks.fromJson(Map<String, dynamic> json) {
    final chassis = json['chassisUris'] as List<dynamic>? ?? const [];
    return SystemLinks(
      biosUri: json['biosUri'] as String?,
      processorsUri: json['processorsUri'] as String?,
      memoryUri: json['memoryUri'] as String?,
      ethernetInterfacesUri: json['ethernetInterfacesUri'] as String?,
      chassisUris: chassis.map((item) => item as String).toList(),
    );
  }
}
