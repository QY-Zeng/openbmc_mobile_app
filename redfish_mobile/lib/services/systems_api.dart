import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/alert_item.dart';
import '../models/alert_stream_event.dart';
import '../models/chassis_detail.dart';
import '../models/chassis_telemetry.dart';
import '../models/python_script_job.dart';
import '../models/system_detail.dart';
import '../models/system_reset_result.dart';
import '../models/system_summary.dart';

class AlertController {
  bool suppressPopups = false;

  void setSuppress(bool value) {
    suppressPopups = value;
  }
}


class SystemsApi {
  SystemsApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? defaultApiBaseUrl).replaceAll(RegExp(r'/$'), '');


  final AlertController alertController = AlertController();
  final http.Client _client;
  final String _baseUrl;

  Future<List<SystemSummary>> fetchSystems() async {
    final body = await _getJson('/api/systems');
    final items = body['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => SystemSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SystemDetail> fetchSystemDetail(String systemId) async {
    final body = await _getJson('/api/systems/$systemId');
    return SystemDetail.fromJson(body);
  }

  Future<SystemResetResult> resetSystemPower(
    String systemId, {
    required String resetType,
  }) async {
    final body = await _postJson('/api/systems/$systemId/power/reset', {
      'resetType': resetType,
    });
    return SystemResetResult.fromJson(body);
  }

  Future<ChassisDetail> fetchChassisDetail(String chassisId) async {
    final body = await _getJson('/api/chassis/$chassisId');
    return ChassisDetail.fromJson(body);
  }

  Future<ChassisTelemetryCurrent> fetchChassisTelemetryCurrent(
    String chassisId,
  ) async {
    final body = await _getJson('/api/chassis/$chassisId/telemetry/current');
    return ChassisTelemetryCurrent.fromJson(body);
  }

  Future<TemperatureReading> updateTemperatureThresholds(
    String chassisId,
    String temperatureId, {
    double? upperCaution,
    double? upperCritical,
    double? upperFatal,
  }) async {
    final payload = <String, dynamic>{};
    if (upperCaution != null) {
      payload['upperCaution'] = upperCaution;
    }
    if (upperCritical != null) {
      payload['upperCritical'] = upperCritical;
    }
    if (upperFatal != null) {
      payload['upperFatal'] = upperFatal;
    }

    final body = await _patchJson(
      '/api/chassis/$chassisId/temperatures/$temperatureId/thresholds',
      payload,
    );
    return TemperatureReading.fromJson(body);
  }

  Future<TemperatureReading> updateTemperatureWarningThreshold(
    String chassisId,
    String temperatureId, {
    required double upperCaution,
  }) {
    return updateTemperatureThresholds(
      chassisId,
      temperatureId,
      upperCaution: upperCaution,
    );
  }

  Stream<ChassisTelemetryCurrent>? watchChassisTelemetry(
    String chassisId,
  ) async* {
    final socket = await WebSocket.connect(
      telemetryWebSocketUri(chassisId).toString(),
    );
    socket.pingInterval = const Duration(seconds: 10);

    try {
      await for (final message in socket) {
        if (message is! String) {
          continue;
        }

        final payload = jsonDecode(message);
        if (payload is! Map<String, dynamic>) {
          continue;
        }

        yield ChassisTelemetryCurrent.fromJson(payload);
      }
    } finally {
      await socket.close();
    }
  }

  Stream<AlertStreamEvent>? watchAlerts() async* {
    final socket = await WebSocket.connect(alertsWebSocketUri().toString());
    socket.pingInterval = const Duration(seconds: 10);

    try {
      await for (final message in socket) {
        if (message is! String) {
          continue;
        }

        final payload = jsonDecode(message);
        if (payload is! Map<String, dynamic>) {
          continue;
        }

        yield AlertStreamEvent.fromJson(payload);
      }
    } finally {
      await socket.close();
    }
  }

  Future<List<AlertItem>> fetchAlerts({String? status, int limit = 100}) async {
    final queryParameters = <String, String>{'limit': '$limit'};
    if (status != null) {
      queryParameters['status'] = status;
    }

    final body = await _getJson(
      '/api/alerts',
      queryParameters: queryParameters,
    );
    final items = body['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AlertItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchOpenAlertCount() async {
    final body = await _getJson(
      '/api/alerts',
      queryParameters: const {'status': 'open', 'limit': '500'},
    );
    final count = body['count'];
    if (count is int) {
      return count;
    }
    final items = body['items'] as List<dynamic>? ?? const [];
    return items.length;
  }

  Future<PythonScriptJob> submitPythonJob({
    required String scriptName,
    required String sourceCode,
    Object? inputJson,
  }) async {
    final body = await _postJson('/api/python-jobs', {
      'scriptName': scriptName,
      'sourceCode': sourceCode,
      'inputJson': inputJson,
    });
    return PythonScriptJob.fromJson(body);
  }

  Future<PythonScriptJob> fetchPythonJob(String jobId) async {
    final body = await _getJson('/api/python-jobs/$jobId');
    return PythonScriptJob.fromJson(body);
  }

  Future<List<ChassisDetail>> fetchChassisDetailsFromUris(
    List<String> chassisUris,
  ) async {
    final chassisIds = chassisUris
        .map(_extractResourceId)
        .whereType<String>()
        .toSet()
        .toList();

    if (chassisIds.isEmpty) {
      return const [];
    }

    return Future.wait(chassisIds.map(fetchChassisDetail));
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final baseUri = Uri.parse('$_baseUrl$path');
    final uri = queryParameters == null || queryParameters.isEmpty
        ? baseUri
        : baseUri.replace(queryParameters: queryParameters);
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw SystemsApiException(
        'Backend returned ${response.statusCode}: ${response.reasonPhrase ?? 'unknown error'}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw SystemsApiException(
        'Backend returned ${response.statusCode}: ${response.reasonPhrase ?? 'unknown error'}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patchJson(

    String path,
    Map<String, dynamic> payload,
    
  ) async {
    print("PATCH: $_baseUrl$path");
    print("BODY: $payload");
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw SystemsApiException(
        'Backend returned ${response.statusCode}: ${response.reasonPhrase ?? 'unknown error'}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uri telemetryWebSocketUri(String chassisId) {
    final httpUri = Uri.parse('$_baseUrl/ws/chassis/$chassisId/telemetry');
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }

  Uri alertsWebSocketUri() {
    final httpUri = Uri.parse('$_baseUrl/ws/alerts');
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }

  Future<void> updateTelemetryOverride({
    required String chassisId,
    double? cpu1Temp,
    double? cpu2Temp,
    double? intakeTemp,
    int? fan1Rpm,
    int? fan2Rpm,
    double? powerWatts,
  }) async {
    final body = <String, dynamic>{};

    if (cpu1Temp != null) body["cpu1Temp"] = cpu1Temp;
    if (cpu2Temp != null) body["cpu2Temp"] = cpu2Temp;
    if (intakeTemp != null) body["intakeTemp"] = intakeTemp;
    if (fan1Rpm != null) body["fan1Rpm"] = fan1Rpm;
    if (fan2Rpm != null) body["fan2Rpm"] = fan2Rpm;
    if (powerWatts != null) body["powerWatts"] = powerWatts;

    final uri = Uri.parse('$_baseUrl/api/chassis/$chassisId/override');

    final response = await _client.patch(
      uri,
      headers: const {
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw SystemsApiException(response.body);
    }
  }

  Future<void> clearTelemetryOverride({
    required String chassisId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/chassis/$chassisId/override');

    final response = await _client.delete(uri);

    if (response.statusCode != 200) {
      throw SystemsApiException(response.body);
    }
  }









}

String? _extractResourceId(String? uri) {
  if (uri == null || uri.isEmpty) {
    return null;
  }

  final segments = uri.split('/').where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) {
    return null;
  }

  return segments.last;
}

class SystemsApiException implements Exception {
  const SystemsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);


