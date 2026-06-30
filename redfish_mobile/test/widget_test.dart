import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:redfish_mobile/main.dart';
import 'package:redfish_mobile/models/alert_item.dart';
import 'package:redfish_mobile/models/alert_stream_event.dart';
import 'package:redfish_mobile/models/chassis_detail.dart';
import 'package:redfish_mobile/models/chassis_telemetry.dart';
import 'package:redfish_mobile/models/python_script_job.dart';
import 'package:redfish_mobile/models/system_detail.dart';
import 'package:redfish_mobile/models/system_reset_result.dart';
import 'package:redfish_mobile/models/system_summary.dart';
import 'package:redfish_mobile/services/systems_api.dart';

void main() {
  testWidgets('shows a live alert popup from websocket events', (
    WidgetTester tester,
  ) async {
    final fakeApi = _FakeSystemsApi();
    final controller = StreamController<AlertStreamEvent>();
    fakeApi.alertEvents = controller.stream;

    await tester.pumpWidget(RedfishMobileApp(systemsApi: fakeApi));
    await tester.pumpAndSettle();

    controller.add(
      AlertStreamEvent(
        eventType: 'opened',
        emittedAt: '2026-06-27T10:05:00+08:00',
        alert: const AlertItem(
          id: 91,
          sourceKey: 'temperature:1U:0',
          chassisId: '1U',
          severity: 'critical',
          category: 'temperature',
          title: 'Temperature alert: CPU1 Temp',
          message: 'CPU1 Temp is 88.1 C on 1U.',
          status: 'open',
          firstSeenAt: '2026-06-27T10:05:00+08:00',
          lastSeenAt: '2026-06-27T10:05:00+08:00',
          resolvedAt: null,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Critical Hardware Alert'), findsOneWidget);
    expect(find.text('Temperature alert: CPU1 Temp'), findsOneWidget);
    expect(find.text('CPU1 Temp is 88.1 C on 1U.'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
  });

  testWidgets('shows a green toast for resolved alert events', (
    WidgetTester tester,
  ) async {
    final fakeApi = _FakeSystemsApi();
    final controller = StreamController<AlertStreamEvent>();
    fakeApi.alertEvents = controller.stream;

    await tester.pumpWidget(RedfishMobileApp(systemsApi: fakeApi));
    await tester.pumpAndSettle();

    controller.add(
      AlertStreamEvent(
        eventType: 'resolved',
        emittedAt: '2026-06-27T10:08:00+08:00',
        alert: const AlertItem(
          id: 92,
          sourceKey: 'temperature:1U:0',
          chassisId: '1U',
          severity: 'warning',
          category: 'temperature',
          title: 'Temperature alert: CPU1 Temp',
          message: 'CPU1 Temp is back to 40.2 C on 1U.',
          status: 'resolved',
          firstSeenAt: '2026-06-27T10:05:00+08:00',
          lastSeenAt: '2026-06-27T10:08:00+08:00',
          resolvedAt: '2026-06-27T10:08:00+08:00',
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Resolved: Temperature alert: CPU1 Temp'), findsOneWidget);
  });

  testWidgets('opens alerts page when tapping the open alert badge', (
    WidgetTester tester,
  ) async {
    final fakeApi = _FakeSystemsApi();
    await tester.pumpWidget(RedfishMobileApp(systemsApi: fakeApi));

    await tester.pumpAndSettle();

    await tester.tap(find.text('2 open alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Alert Inbox'), findsOneWidget);
    expect(fakeApi.fetchAlertsCalls, 1);
  });

  testWidgets('runs a python job from the python runner page', (
    WidgetTester tester,
  ) async {
    final fakeApi = _FakeSystemsApi();
    await tester.pumpWidget(RedfishMobileApp(systemsApi: fakeApi));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Python Runner'));
    await tester.pumpAndSettle();

    expect(find.text('Deliver PY Program'), findsOneWidget);
    expect(find.text('Run Python Job'), findsOneWidget);

    await tester.ensureVisible(find.text('Run Python Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Python Job'));
    await tester.pumpAndSettle();

    expect(fakeApi.lastPythonScriptName, 'energy_analysis.py');
    expect(find.text('Refresh Job'), findsOneWidget);
  });

  testWidgets('renders systems from backend response', (
    WidgetTester tester,
  ) async {
    final fakeApi = _FakeSystemsApi();
    await tester.pumpWidget(RedfishMobileApp(systemsApi: fakeApi));

    await tester.pumpAndSettle();

    expect(find.text('Redfish Systems'), findsOneWidget);
    expect(find.text('WebFrontEnd483'), findsOneWidget);
    expect(find.text('web483'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('1 system available'), findsOneWidget);
    expect(find.text('2 open alerts'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Alert Inbox'), findsOneWidget);
    expect(find.text('Temperature alert: CPU1 Temp'), findsOneWidget);
    expect(find.text('OPEN'), findsAtLeastNWidgets(1));
    expect(fakeApi.fetchAlertsCalls, 1);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchAlertsCalls, greaterThanOrEqualTo(2));

    await tester.tap(find.text('Temperature alert: CPU1 Temp'));
    await tester.pumpAndSettle();

    expect(find.text('Chassis Identity'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Live Telemetry'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Live Telemetry'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Power supply alert: Power Supply Bay 1'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Power supply alert: Power Supply Bay 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebFrontEnd483'));
    await tester.pumpAndSettle();

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('System State'), findsOneWidget);
    expect(find.text('P79 v1.45 (12/06/2017)'), findsOneWidget);
    expect(find.text('Last Reset'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Linked Chassis'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Linked Chassis'), findsOneWidget);
    expect(find.text('Computer System Chassis'), findsOneWidget);
    expect(find.text('RackMount'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Power Control'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Power Control'), findsOneWidget);
    expect(find.text('Graceful Restart'), findsOneWidget);

    await tester.tap(find.text('Graceful Restart'));
    await tester.pumpAndSettle();
    expect(find.text('Send Action'), findsOneWidget);

    await tester.tap(find.text('Send Action'));
    await tester.pumpAndSettle();

    expect(fakeApi.lastResetSystemId, '437XR1138R2');
    expect(fakeApi.lastResetType, 'GracefulRestart');
    expect(find.textContaining('Power is now On.'), findsAtLeastNWidgets(1));

    await tester.scrollUntilVisible(
      find.text('Computer System Chassis').last,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Computer System Chassis').last);
    await tester.pumpAndSettle();

    expect(find.text('Chassis Identity'), findsOneWidget);
    expect(find.text('Chassis Status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Live Telemetry'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Live Telemetry'), findsOneWidget);
    expect(find.text('40.4 °C'), findsOneWidget);
    expect(find.text('371.8 W'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Temperature Trend'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Temperature Trend'), findsOneWidget);
    expect(find.text('Fan RPM Trend'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Temperatures'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Temperatures'), findsOneWidget);
    expect(find.text('CPU1 Temp'), findsOneWidget);
    final thresholdButton = find.widgetWithText(
      OutlinedButton,
      'Edit thresholds',
    );
    await tester.ensureVisible(thresholdButton);
    await tester.pumpAndSettle();
    expect(thresholdButton, findsOneWidget);

    await tester.tap(thresholdButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit Temperature Thresholds'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '38.0');
    await tester.enterText(find.byType(TextField).at(1), '45.0');
    await tester.enterText(find.byType(TextField).at(2), '48.0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeApi.lastThresholdChassisId, '1U');
    expect(fakeApi.lastThresholdTemperatureId, '0');
    expect(fakeApi.lastThresholdUpperCaution, 38.0);
    expect(fakeApi.lastThresholdUpperCritical, 45.0);
    expect(fakeApi.lastThresholdUpperFatal, 48.0);
    expect(
      find.textContaining('Updated CPU1 Temp thresholds'),
      findsAtLeastNWidgets(1),
    );
    await tester.scrollUntilVisible(
      find.text('Fans'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('BaseBoard System Fan'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Power Supplies'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Power Supplies'), findsOneWidget);
    expect(find.text('Power Supply Bay 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Chassis Layout'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Chassis Layout'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Telemetry Links'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Telemetry Links'), findsOneWidget);
    expect(find.text('Relationships'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('WEB43'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('WEB43'), findsOneWidget);
  });
}

class _FakeSystemsApi extends SystemsApi {
  _FakeSystemsApi()
    : super(baseUrl: 'http://example.com', client: _NoopHttpClient());

  int fetchAlertsCalls = 0;
  String? lastResetSystemId;
  String? lastResetType;
  String? lastThresholdChassisId;
  String? lastThresholdTemperatureId;
  double? lastThresholdUpperCaution;
  double? lastThresholdUpperCritical;
  double? lastThresholdUpperFatal;
  String? lastPythonScriptName;
  String? lastPythonSourceCode;
  Object? lastPythonInputJson;
  Stream<AlertStreamEvent>? alertEvents;

  @override
  Future<List<SystemSummary>> fetchSystems() async {
    return const [
      SystemSummary(
        id: '437XR1138R2',
        name: 'WebFrontEnd483',
        hostName: 'web483',
        manufacturer: 'Contoso',
        model: '3500',
        systemType: 'Physical',
        serialNumber: '437XR1138R2',
        powerState: 'On',
        indicatorLed: 'Off',
        health: 'OK',
        state: 'Enabled',
        processorCount: 2,
        processorModel: 'Xeon',
        memoryGiB: 96,
        redfishUri: '/redfish/v1/Systems/437XR1138R2',
      ),
    ];
  }

  @override
  Future<SystemDetail> fetchSystemDetail(String systemId) async {
    return const SystemDetail(
      id: '437XR1138R2',
      name: 'WebFrontEnd483',
      hostName: 'web483',
      manufacturer: 'Contoso',
      model: '3500',
      systemType: 'Physical',
      serialNumber: '437XR1138R2',
      powerState: 'On',
      indicatorLed: 'Off',
      health: 'OK',
      state: 'Enabled',
      processorCount: 2,
      processorModel: 'Xeon',
      memoryGiB: 96,
      redfishUri: '/redfish/v1/Systems/437XR1138R2',
      assetTag: 'Chicago-45Z-2381',
      description: 'Web Front End node',
      biosVersion: 'P79 v1.45 (12/06/2017)',
      lastResetTime: '2021-03-13T04:02:57+06:00',
      boot: SystemBootInfo(
        overrideEnabled: 'Once',
        overrideTarget: 'Pxe',
        overrideMode: 'UEFI',
      ),
      links: SystemLinks(
        biosUri: '/redfish/v1/Systems/437XR1138R2/Bios',
        processorsUri: '/redfish/v1/Systems/437XR1138R2/Processors',
        memoryUri: '/redfish/v1/Systems/437XR1138R2/Memory',
        ethernetInterfacesUri:
            '/redfish/v1/Systems/437XR1138R2/EthernetInterfaces',
        chassisUris: ['/redfish/v1/Chassis/1U'],
      ),
      actions: SystemActions(
        reset: SystemResetAction(
          target:
              '/redfish/v1/Systems/437XR1138R2/Actions/ComputerSystem.Reset',
          allowableValues: [
            'On',
            'ForceOff',
            'GracefulShutdown',
            'GracefulRestart',
            'ForceRestart',
            'Nmi',
            'ForceOn',
            'PushPowerButton',
          ],
        ),
      ),
    );
  }

  @override
  Future<SystemResetResult> resetSystemPower(
    String systemId, {
    required String resetType,
  }) async {
    lastResetSystemId = systemId;
    lastResetType = resetType;
    return SystemResetResult(
      systemId: systemId,
      resetType: resetType,
      powerState: 'On',
      message: '$systemId reset with $resetType',
    );
  }

  @override
  Future<List<ChassisDetail>> fetchChassisDetailsFromUris(
    List<String> chassisUris,
  ) async {
    return const [_fakeChassis];
  }

  @override
  Future<ChassisDetail> fetchChassisDetail(String chassisId) async {
    return _fakeChassis;
  }

  @override
  Future<ChassisTelemetryCurrent> fetchChassisTelemetryCurrent(
    String chassisId,
  ) async {
    return _fakeTelemetry;
  }

  @override
  Future<TemperatureReading> updateTemperatureThresholds(
    String chassisId,
    String temperatureId, {
    double? upperCaution,
    double? upperCritical,
    double? upperFatal,
  }) async {
    lastThresholdChassisId = chassisId;
    lastThresholdTemperatureId = temperatureId;
    lastThresholdUpperCaution = upperCaution;
    lastThresholdUpperCritical = upperCritical;
    lastThresholdUpperFatal = upperFatal;
    return TemperatureReading(
      id: temperatureId,
      name: 'CPU1 Temp',
      celsius: 40.4,
      health: 'OK',
      state: 'Enabled',
      physicalContext: 'CPU',
      upperCaution: upperCaution,
      upperCritical: upperCritical,
      upperFatal: upperFatal,
    );
  }

  @override
  Stream<ChassisTelemetryCurrent>? watchChassisTelemetry(String chassisId) {
    return null;
  }

  @override
  Stream<AlertStreamEvent>? watchAlerts() {
    return alertEvents;
  }

  @override
  Future<List<AlertItem>> fetchAlerts({String? status, int limit = 100}) async {
    fetchAlertsCalls += 1;
    final alerts = _fakeAlerts
        .where((alert) => status == null || alert.status == status)
        .take(limit)
        .toList();
    return alerts;
  }

  @override
  Future<int> fetchOpenAlertCount() async {
    return _fakeAlerts.where((alert) => alert.status == 'open').length;
  }

  @override
  Future<PythonScriptJob> submitPythonJob({
    required String scriptName,
    required String sourceCode,
    Object? inputJson,
  }) async {
    lastPythonScriptName = scriptName;
    lastPythonSourceCode = sourceCode;
    lastPythonInputJson = inputJson;
    return const PythonScriptJob(
      jobId: 'job-001',
      scriptName: 'energy_analysis.py',
      status: 'completed',
      createdAt: '2026-06-27T10:20:00+08:00',
      startedAt: '2026-06-27T10:20:01+08:00',
      completedAt: '2026-06-27T10:20:02+08:00',
      durationMs: 1200,
      exitCode: 0,
      stdout: 'Analyzed 5 power samples.',
      stderr: '',
      structuredOutput: {
        'sampleCount': 5,
        'averageWatts': 317.6,
        'peakWatts': 330.4,
        'minWatts': 305.9,
        'estimatedKWhPerDay': 7.622,
      },
      error: null,
      workingDirectory: '/tmp/script_jobs/job-001',
      inputJson: {
        'powerWatts': [312.5, 318.2, 305.9, 330.4, 321.0],
      },
    );
  }

  @override
  Future<PythonScriptJob> fetchPythonJob(String jobId) async {
    return const PythonScriptJob(
      jobId: 'job-001',
      scriptName: 'energy_analysis.py',
      status: 'completed',
      createdAt: '2026-06-27T10:20:00+08:00',
      startedAt: '2026-06-27T10:20:01+08:00',
      completedAt: '2026-06-27T10:20:02+08:00',
      durationMs: 1200,
      exitCode: 0,
      stdout: 'Analyzed 5 power samples.',
      stderr: '',
      structuredOutput: {
        'sampleCount': 5,
        'averageWatts': 317.6,
        'peakWatts': 330.4,
        'minWatts': 305.9,
        'estimatedKWhPerDay': 7.622,
      },
      error: null,
      workingDirectory: '/tmp/script_jobs/job-001',
      inputJson: {
        'powerWatts': [312.5, 318.2, 305.9, 330.4, 321.0],
      },
    );
  }
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network should not be used in widget tests.');
  }
}

const ChassisDetail _fakeChassis = ChassisDetail(
  id: '1U',
  name: 'Computer System Chassis',
  chassisType: 'RackMount',
  manufacturer: 'Contoso',
  model: '3500RX',
  serialNumber: '437XR1138R2',
  powerState: 'On',
  indicatorLed: 'Lit',
  health: 'OK',
  state: 'Enabled',
  thermalUri: '/redfish/v1/Chassis/1U/ThermalSubsystem',
  powerUri: '/redfish/v1/Chassis/1U/PowerSubsystem',
  sensorsUri: '/redfish/v1/Chassis/1U/Sensors',
  environmentMetricsUri: '/redfish/v1/Chassis/1U/EnvironmentMetrics',
  computerSystemIds: ['437XR1138R2'],
  redfishUri: '/redfish/v1/Chassis/1U',
  assetTag: 'Chicago-45Z-2381',
  heightMm: 44.45,
  widthMm: 431.8,
  depthMm: 711,
  weightKg: 15.31,
  rack: 'WEB43',
  row: 'North',
  managedByUris: ['/redfish/v1/Managers/BMC'],
  managerUris: ['/redfish/v1/Managers/BMC'],
);

const ChassisTelemetryCurrent _fakeTelemetry = ChassisTelemetryCurrent(
  chassisId: '1U',
  timestamp: '2026-06-27T09:12:00+08:00',
  summary: TelemetrySummary(
    temperatureCelsius: 40.4,
    powerWatts: 371.8,
    health: 'Warning',
  ),
  temperatures: [
    TemperatureReading(
      id: '0',
      name: 'CPU1 Temp',
      celsius: 40.4,
      health: 'OK',
      state: 'Enabled',
      physicalContext: 'CPU',
      upperCaution: 42,
      upperCritical: 45,
      upperFatal: 48,
    ),
  ],
  fans: [
    FanReading(
      id: '0',
      name: 'BaseBoard System Fan',
      rpm: 2486,
      health: 'OK',
      state: 'Enabled',
      physicalContext: 'Backplane',
    ),
  ],
  powerControls: [
    PowerControlReading(
      id: '0',
      name: 'System Input Power',
      consumedWatts: 371.8,
      averageWatts: 349.5,
      peakWatts: 401.6,
      capacityWatts: 800,
      allocatedWatts: 800,
      health: 'OK',
      state: 'Enabled',
    ),
  ],
  powerSupplies: [
    PowerSupplyReading(
      id: '0',
      name: 'Power Supply Bay 1',
      lastOutputWatts: 353.2,
      capacityWatts: 400,
      health: 'OK',
      state: 'Enabled',
      model: '499253-B21',
      firmwareVersion: '1.00',
    ),
  ],
);

const List<AlertItem> _fakeAlerts = [
  AlertItem(
    id: 1,
    sourceKey: 'temperature:1U:0',
    chassisId: '1U',
    severity: 'warning',
    category: 'temperature',
    title: 'Temperature alert: CPU1 Temp',
    message: 'CPU1 Temp is 44.2 C on 1U.',
    status: 'open',
    firstSeenAt: '2026-06-27T10:00:00+08:00',
    lastSeenAt: '2026-06-27T10:02:00+08:00',
    resolvedAt: null,
  ),
  AlertItem(
    id: 2,
    sourceKey: 'power-supply:1U:0',
    chassisId: '1U',
    severity: 'critical',
    category: 'power-supply',
    title: 'Power supply alert: Power Supply Bay 1',
    message: 'Power Supply Bay 1 output is 353.2 W on 1U.',
    status: 'open',
    firstSeenAt: '2026-06-27T10:01:00+08:00',
    lastSeenAt: '2026-06-27T10:03:00+08:00',
    resolvedAt: null,
  ),
  AlertItem(
    id: 3,
    sourceKey: 'fan:1U:0',
    chassisId: '1U',
    severity: 'warning',
    category: 'fan',
    title: 'Fan alert: BaseBoard System Fan',
    message: 'BaseBoard System Fan is at 1500 RPM on 1U.',
    status: 'resolved',
    firstSeenAt: '2026-06-27T09:50:00+08:00',
    lastSeenAt: '2026-06-27T09:55:00+08:00',
    resolvedAt: '2026-06-27T09:55:00+08:00',
  ),
];
