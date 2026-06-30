import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/alert_item.dart';
import 'models/alert_stream_event.dart';
import 'models/chassis_detail.dart';
import 'models/chassis_telemetry.dart';
import 'models/python_script_job.dart';
import 'models/system_detail.dart';
import 'models/system_reset_result.dart';
import 'models/system_summary.dart';
import 'services/systems_api.dart';

void main() {
  runApp(const RedfishMobileApp());
}

class RedfishMobileApp extends StatefulWidget {
  const RedfishMobileApp({super.key, this.systemsApi});

  final SystemsApi? systemsApi;

  @override
  State<RedfishMobileApp> createState() => _RedfishMobileAppState();
}

class _RedfishMobileAppState extends State<RedfishMobileApp> {
  static const Duration _alertReconnectDelay = Duration(seconds: 3);

  late final SystemsApi _systemsApi;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final Queue<AlertStreamEvent> _pendingAlertEvents = Queue<AlertStreamEvent>();
  final Set<String> _seenAlertEventKeys = <String>{};
  StreamSubscription<AlertStreamEvent>? _alertSubscription;
  Timer? _alertReconnectTimer;
  bool _showingAlertDialog = false;
  int? _openAlertCount;

  @override
  void initState() {
    super.initState();
    _systemsApi = widget.systemsApi ?? SystemsApi();
    _refreshOpenAlertCount();
    _connectAlertStream();
  }

  @override
  void dispose() {
    _alertReconnectTimer?.cancel();
    unawaited(_alertSubscription?.cancel());
    super.dispose();
  }

  void _connectAlertStream() {
    _alertReconnectTimer?.cancel();
    unawaited(_alertSubscription?.cancel());
    _refreshOpenAlertCount();

    final stream = _systemsApi.watchAlerts();
    if (stream == null) {
      return;
    }

    _alertSubscription = stream.listen(
      _handleAlertStreamEvent,
      onError: (Object error, StackTrace stackTrace) {
        _scheduleAlertReconnect();
      },
      onDone: _scheduleAlertReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleAlertReconnect() {
    if (!mounted) {
      return;
    }
    _alertReconnectTimer?.cancel();
    _alertReconnectTimer = Timer(_alertReconnectDelay, _connectAlertStream);
  }

  void _handleAlertStreamEvent(AlertStreamEvent event) {
    
    if (_systemsApi.alertController.suppressPopups) {
      return;
    }
    
    
    
    final eventKey =
        '${event.eventType}:${event.alert.id}:${event.alert.severity}:${event.alert.lastSeenAt}';
    if (!_seenAlertEventKeys.add(eventKey)) {
      return;
    }

    bool _muteAlerts = false;

    _applyOpenAlertCountEvent(event);

    if (event.eventType == 'resolved') {
      _showResolvedToast(event);
      return;
    }

    if (_muteAlerts) {
      return;
    }

    if (!event.shouldShowPopup) {
      return;
    }

    _pendingAlertEvents.add(event);
    _showNextAlertDialog();
  }

  Future<void> _refreshOpenAlertCount() async {
    try {
      final count = await _systemsApi.fetchOpenAlertCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _openAlertCount = count;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _openAlertCount = _openAlertCount;
      });
    }
  }

  void _applyOpenAlertCountEvent(AlertStreamEvent event) {
    if (_openAlertCount == null) {
      unawaited(_refreshOpenAlertCount());
      return;
    }

    switch (event.eventType) {
      case 'opened':
        setState(() {
          _openAlertCount = _openAlertCount! + 1;
        });
        break;
      case 'resolved':
        setState(() {
          _openAlertCount = math.max(0, _openAlertCount! - 1);
        });
        break;
      default:
        break;
    }
  }

  void _showResolvedToast(AlertStreamEvent event) {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
          content: Text(
            'Resolved: ${event.alert.title}',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'Alerts',
            textColor: const Color(0xFFE8F5E9),
            onPressed: () {
              _navigatorKey.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (context) => AlertsPage(systemsApi: _systemsApi),
                ),
              );
            },
          ),
        ),
      );
  }

  void _showNextAlertDialog() {
    if (_showingAlertDialog || _pendingAlertEvents.isEmpty) {
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNextAlertDialog();
        }
      });
      return;
    }

    _showingAlertDialog = true;
    final event = _pendingAlertEvents.removeFirst();

    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _AlertPopupDialog(event: event),
    ).then((action) {
      _showingAlertDialog = false;
      if (!mounted) {
        return;
      }

      final navigator = _navigatorKey.currentState;
      if (action == 'chassis') {
        navigator?.push(
          MaterialPageRoute<void>(
            builder: (context) => ChassisDetailPage.fromAlert(
              systemsApi: _systemsApi,
              chassisId: event.alert.chassisId,
            ),
          ),
        );
      } else if (action == 'alerts') {
        navigator?.push(
          MaterialPageRoute<void>(
            builder: (context) => AlertsPage(systemsApi: _systemsApi),
          ),
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNextAlertDialog();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB75A2A),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6EBDD),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
      ),
    );

    return MaterialApp(
      title: 'Redfish Mobile',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: theme,
      
      //home: SystemsHomePage(
      home: AppShell(
        systemsApi: _systemsApi,
        openAlertCount: _openAlertCount?? 0,
      ),
    );
  }
}


class AppShell extends StatefulWidget {
  final SystemsApi systemsApi;
  final int openAlertCount;

  const AppShell({
    super.key,
    required this.systemsApi,
    required this.openAlertCount,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool muted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Redfish Mobile'),

        actions: [
          // 🔔 Alert toggle button
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  muted
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                ),
                onPressed: () {
                  setState(() {
                    muted = !muted;
                  });

                  widget.systemsApi.alertController
                      .setSuppress(muted);
                },
              ),

              // 🔴 badge（可選）
              if (widget.openAlertCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${widget.openAlertCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      // 👇 你的原本首頁
      body: SystemsHomePage(
        systemsApi: widget.systemsApi,
        openAlertCount: widget.openAlertCount,
      ),
    );
  }
}


class SystemsHomePage extends StatefulWidget {
  const SystemsHomePage({super.key, this.systemsApi, this.openAlertCount});

  final SystemsApi? systemsApi;
  final int? openAlertCount;

  @override
  State<SystemsHomePage> createState() => _SystemsHomePageState();
}

class _SystemsHomePageState extends State<SystemsHomePage> {
  late final SystemsApi _systemsApi;
  late Future<List<SystemSummary>> _systemsFuture;

  @override
  void initState() {
    super.initState();
    _systemsApi = widget.systemsApi ?? SystemsApi();
    _systemsFuture = _systemsApi.fetchSystems();
  }

  Future<void> _refreshSystems() async {
    final future = _systemsApi.fetchSystems();
    setState(() {
      _systemsFuture = future;
    });
    await future;
  }

  void _retry() {
    setState(() {
      _systemsFuture = _systemsApi.fetchSystems();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE9D4BB), Color(0xFFF7F1E8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<SystemSummary>>(
            future: _systemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingView();
              }

              if (snapshot.hasError) {
                return _ErrorView(
                  title: 'Unable to load systems',
                  error: snapshot.error,
                  onRetry: _retry,
                );
              }

              final systems = snapshot.data ?? const [];
              return RefreshIndicator(
                onRefresh: _refreshSystems,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    _Header(
                      totalSystems: systems.length,
                      apiBaseUrl: defaultApiBaseUrl,
                      openAlertCount: widget.openAlertCount,
                      onAlertsTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                AlertsPage(systemsApi: _systemsApi),
                          ),
                        );
                      },
                      onPythonRunnerTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                PythonRunnerPage(systemsApi: _systemsApi),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    if (systems.isEmpty)
                      const _EmptyView()
                    else
                      ...systems.map(
                        (system) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _SystemCard(
                            system: system,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => SystemDetailPage(
                                    systemsApi: _systemsApi,
                                    system: system,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.totalSystems,
    required this.apiBaseUrl,
    required this.openAlertCount,
    required this.onAlertsTap,
    required this.onPythonRunnerTap,
  });

  final int totalSystems;
  final String apiBaseUrl;
  final int? openAlertCount;
  final VoidCallback onAlertsTap;
  final VoidCallback onPythonRunnerTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2E241F),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Redfish Systems',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: onAlertsTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A3A31),
                  foregroundColor: const Color(0xFFF3DDC7),
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Alerts'),
              ),
              FilledButton.tonalIcon(
                onPressed: onPythonRunnerTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5A3324),
                  foregroundColor: const Color(0xFFF6DFC7),
                ),
                icon: const Icon(Icons.terminal_rounded),
                label: const Text('Python Runner'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$totalSystems system${totalSystems == 1 ? '' : 's'} available',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF1DFCD),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAlertsTap,
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: openAlertCount == null
                      ? const Color(0xFF4A3A31)
                      : openAlertCount == 0
                      ? const Color(0xFF264A37)
                      : const Color(0xFF6A2D28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      openAlertCount == 0
                          ? Icons.verified_outlined
                          : Icons.notification_important_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      openAlertCount == null
                          ? 'Syncing open alerts...'
                          : '$openAlertCount open alert${openAlertCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            apiBaseUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD3B49B),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.system, required this.onTap});

  final SystemSummary system;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthColor = _healthColor(system.health);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          system.name ?? system.id,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2A231F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          system.hostName ?? system.id,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF6E5B4C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8A6C55),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(
                    label: system.health ?? 'Unknown',
                    color: healthColor,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricChip(
                    icon: Icons.memory_rounded,
                    label: system.model ?? 'Unknown model',
                  ),
                  _MetricChip(
                    icon: Icons.bolt_rounded,
                    label: 'Power ${system.powerState ?? 'Unknown'}',
                  ),
                  _MetricChip(
                    icon: Icons.dns_rounded,
                    label: '${system.processorCount ?? 0} CPU',
                  ),
                  _MetricChip(
                    icon: Icons.sd_storage_rounded,
                    label:
                        '${system.memoryGiB?.toStringAsFixed(0) ?? '-'} GiB RAM',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F1EA),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Snapshot',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF41352D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      label: 'Manufacturer',
                      value: system.manufacturer ?? '-',
                    ),
                    _DetailRow(label: 'Type', value: system.systemType ?? '-'),
                    _DetailRow(
                      label: 'Serial',
                      value: system.serialNumber ?? '-',
                    ),
                    _DetailRow(label: 'LED', value: system.indicatorLed ?? '-'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertPopupDialog extends StatelessWidget {
  const _AlertPopupDialog({required this.event});

  final AlertStreamEvent event;

  @override
  Widget build(BuildContext context) {
    final severityColor = _alertSeverityColor(event.alert.severity);
    final backgroundColor = Color.alphaBlend(
      severityColor.withValues(alpha: 0.14),
      Colors.white,
    );

    return AlertDialog(
      backgroundColor: backgroundColor,
      icon: Icon(Icons.warning_amber_rounded, color: severityColor, size: 34),
      title: Text(
        event.alert.severity.toUpperCase() == 'CRITICAL'
            ? 'Critical Hardware Alert'
            : 'Hardware Alert',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.alert.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2F2722),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            event.alert.message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF5A4638),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.dns_rounded,
                label: event.alert.chassisId,
              ),
              _MetricChip(
                icon: Icons.priority_high_rounded,
                label: event.alert.severity.toUpperCase(),
              ),
              _MetricChip(
                icon: Icons.schedule_rounded,
                label: _formatTimestamp(event.emittedAt),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop('alerts'),
          child: const Text('Open Alerts'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: severityColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop('chassis'),
          child: const Text('Open Chassis'),
        ),
      ],
    );
  }
}

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key, required this.systemsApi});

  final SystemsApi systemsApi;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  static const Duration _alertsRefreshInterval = Duration(seconds: 10);

  String? _statusFilter = 'open';
  late Future<List<AlertItem>> _alertsFuture;
  List<AlertItem>? _latestAlerts;
  Timer? _alertsTimer;
  String? _alertsRefreshError;

  @override
  void initState() {
    super.initState();
    _queueAlertsRefresh();
    _alertsTimer = Timer.periodic(
      _alertsRefreshInterval,
      (_) => _refreshAlertsSilently(),
    );
  }

  @override
  void dispose() {
    _alertsTimer?.cancel();
    super.dispose();
  }

  Future<List<AlertItem>> _loadAlerts() {
    return widget.systemsApi.fetchAlerts(status: _statusFilter);
  }

  void _queueAlertsRefresh() {
    final future = _loadAlerts();
    setState(() {
      _alertsFuture = future;
      _alertsRefreshError = null;
    });

    future
        .then((alerts) {
          if (!mounted) {
            return;
          }
          setState(() {
            _latestAlerts = alerts;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!mounted || _latestAlerts == null) {
            return;
          }
          setState(() {
            _alertsRefreshError = '$error';
          });
        });
  }

  Future<void> _refreshAlertsSilently() async {
    if (_latestAlerts == null) {
      return;
    }

    try {
      final alerts = await _loadAlerts();
      if (!mounted) {
        return;
      }
      setState(() {
        _latestAlerts = alerts;
        _alertsRefreshError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _alertsRefreshError = '$error';
      });
    }
  }

  Future<void> _refreshAlerts() async {
    _queueAlertsRefresh();
    await _alertsFuture;
  }

  void _retry() {
    _queueAlertsRefresh();
  }

  void _setStatusFilter(String? value) {
    if (_statusFilter == value) {
      return;
    }
    setState(() {
      _statusFilter = value;
    });
    _queueAlertsRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: const Color(0xFFF6EBDD),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4E2CF), Color(0xFFF9F5EF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<List<AlertItem>>(
            future: _alertsFuture,
            builder: (context, snapshot) {
              final alerts = snapshot.data ?? _latestAlerts;
              final isRefreshing =
                  snapshot.connectionState == ConnectionState.waiting &&
                  alerts != null;

              if (snapshot.connectionState == ConnectionState.waiting &&
                  alerts == null) {
                return const _LoadingView(message: 'Loading alerts...');
              }

              if (snapshot.hasError && alerts == null) {
                return _ErrorView(
                  title: 'Unable to load alerts',
                  error: snapshot.error,
                  onRetry: _retry,
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshAlerts,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (isRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    _AlertsHero(
                      count: alerts?.length ?? 0,
                      statusFilter: _statusFilter,
                      refreshError: _alertsRefreshError,
                    ),
                    const SizedBox(height: 16),
                    _AlertFilterBar(
                      statusFilter: _statusFilter,
                      onChanged: _setStatusFilter,
                    ),
                    const SizedBox(height: 16),
                    if ((alerts ?? const []).isEmpty)
                      _EmptyView(
                        title: _emptyAlertsTitle(_statusFilter),
                        subtitle:
                            'Pull to refresh after the backend monitor writes new alert records.',
                      )
                    else
                      ...(alerts ?? const <AlertItem>[]).map(
                        (alert) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AlertCard(
                            alert: alert,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      ChassisDetailPage.fromAlert(
                                        systemsApi: widget.systemsApi,
                                        chassisId: alert.chassisId,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class PythonRunnerPage extends StatefulWidget {
  const PythonRunnerPage({super.key, required this.systemsApi});

  final SystemsApi systemsApi;

  @override
  State<PythonRunnerPage> createState() => _PythonRunnerPageState();
}

class _PythonRunnerPageState extends State<PythonRunnerPage> {
  static const Duration _jobRefreshInterval = Duration(seconds: 1);

  late final TextEditingController _scriptNameController;
  late final TextEditingController _inputJsonController;
  late final TextEditingController _sourceCodeController;
  Timer? _jobRefreshTimer;
  PythonScriptJob? _currentJob;
  bool _submitting = false;
  String? _formError;
  String? _jobRefreshError;

  @override
  void initState() {
    super.initState();
    _scriptNameController = TextEditingController(text: 'energy_analysis.py');
    _inputJsonController = TextEditingController(
      text: _pythonRunnerExampleInput,
    );
    _sourceCodeController = TextEditingController(
      text: _pythonRunnerExampleCode,
    );
  }

  @override
  void dispose() {
    _jobRefreshTimer?.cancel();
    _scriptNameController.dispose();
    _inputJsonController.dispose();
    _sourceCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitJob() async {
    final scriptName = _scriptNameController.text.trim();
    final sourceCode = _sourceCodeController.text.trimRight();
    if (scriptName.isEmpty || sourceCode.isEmpty) {
      setState(() {
        _formError = 'Script name and Python source are required.';
      });
      return;
    }

    Object? inputJson;
    final inputText = _inputJsonController.text.trim();
    if (inputText.isNotEmpty) {
      try {
        inputJson = jsonDecode(inputText);
      } catch (_) {
        setState(() {
          _formError = 'Input JSON must be valid JSON before the job can run.';
        });
        return;
      }
    }

    setState(() {
      _submitting = true;
      _formError = null;
      _jobRefreshError = null;
    });

    try {
      final job = await widget.systemsApi.submitPythonJob(
        scriptName: scriptName,
        sourceCode: sourceCode,
        inputJson: inputJson,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentJob = job;
        _submitting = false;
      });
      _syncJobPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _formError = '$error';
      });
    }
  }

  Future<void> _refreshJob() async {
    final currentJob = _currentJob;
    if (currentJob == null) {
      return;
    }

    try {
      final job = await widget.systemsApi.fetchPythonJob(currentJob.jobId);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentJob = job;
        _jobRefreshError = null;
      });
      if (job.isTerminal) {
        _jobRefreshTimer?.cancel();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _jobRefreshError = '$error';
      });
    }
  }

  void _syncJobPolling() {
    _jobRefreshTimer?.cancel();
    final currentJob = _currentJob;
    if (currentJob == null || currentJob.isTerminal) {
      return;
    }

    _jobRefreshTimer = Timer.periodic(_jobRefreshInterval, (_) {
      unawaited(_refreshJob());
    });
  }

  void _loadExample() {
    setState(() {
      _scriptNameController.text = 'energy_analysis.py';
      _inputJsonController.text = _pythonRunnerExampleInput;
      _sourceCodeController.text = _pythonRunnerExampleCode;
      _formError = null;
    });
  }

  String _prettyResult(Object? value) {
    if (value == null) {
      return 'No structured output returned. Write JSON to JOB_OUTPUT_PATH to populate this section.';
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentJob = _currentJob;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Runner'),
        backgroundColor: const Color(0xFFF6EBDD),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4E2CF), Color(0xFFF9F5EF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E241F),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deliver PY Program',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Paste trusted Python code, send optional JSON input, then let FastAPI run the script in a background job and return stdout plus structured output.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFF1DFCD),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Inside the script, read JSON from stdin or JOB_INPUT_PATH, and write JSON results to JOB_OUTPUT_PATH.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD3B49B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _InfoSection(
                title: 'Script Delivery',
                children: [
                  TextField(
                    controller: _scriptNameController,
                    decoration: const InputDecoration(
                      labelText: 'Script name',
                      hintText: 'energy_analysis.py',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputJsonController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Input JSON',
                      hintText: '{"powerWatts":[320.0, 318.2]}',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sourceCodeController,
                    minLines: 14,
                    maxLines: 22,
                    decoration: const InputDecoration(
                      labelText: 'Python source',
                      alignLabelWithHint: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submitJob,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _submitting ? 'Submitting...' : 'Run Python Job',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadExample,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Load Example'),
                      ),
                      if (currentJob != null)
                        OutlinedButton.icon(
                          onPressed: _refreshJob,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Refresh Job'),
                        ),
                    ],
                  ),
                ],
              ),
              if (currentJob != null) ...[
                const SizedBox(height: 16),
                _InfoSection(
                  title: 'Execution Result',
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatusBadge(
                          label: currentJob.status.toUpperCase(),
                          color: _pythonJobStatusColor(currentJob.status),
                        ),
                        _MetricChip(
                          icon: Icons.tag_rounded,
                          label: currentJob.jobId,
                        ),
                        if (currentJob.durationMs != null)
                          _MetricChip(
                            icon: Icons.timer_outlined,
                            label: '${currentJob.durationMs} ms',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DetailRow(label: 'Script', value: currentJob.scriptName),
                    _DetailRow(
                      label: 'Created',
                      value: _formatTimestamp(currentJob.createdAt),
                    ),
                    if (currentJob.startedAt != null)
                      _DetailRow(
                        label: 'Started',
                        value: _formatTimestamp(currentJob.startedAt!),
                      ),
                    if (currentJob.completedAt != null)
                      _DetailRow(
                        label: 'Completed',
                        value: _formatTimestamp(currentJob.completedAt!),
                      ),
                    _DetailRow(
                      label: 'Exit Code',
                      value: currentJob.exitCode?.toString() ?? '-',
                    ),
                    if (currentJob.workingDirectory != null)
                      _DetailRow(
                        label: 'Working Dir',
                        value: currentJob.workingDirectory!,
                      ),
                    if (currentJob.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        currentJob.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_jobRefreshError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Refresh failed: $_jobRefreshError',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _InfoSection(
                  title: 'Structured Output',
                  children: [
                    _CodeBlock(
                      content: _prettyResult(currentJob.structuredOutput),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoSection(
                  title: 'Standard Output',
                  children: [
                    _CodeBlock(
                      content:
                          (currentJob.stdout == null ||
                              currentJob.stdout!.isEmpty)
                          ? 'No stdout output.'
                          : currentJob.stdout!,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoSection(
                  title: 'Standard Error',
                  children: [
                    _CodeBlock(
                      content:
                          (currentJob.stderr == null ||
                              currentJob.stderr!.isEmpty)
                          ? 'No stderr output.'
                          : currentJob.stderr!,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF201A16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SelectableText(
        content,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.45,
          color: Color(0xFFF6EBDD),
        ),
      ),
    );
  }
}

Color _pythonJobStatusColor(String status) {
  switch (status) {
    case 'completed':
      return const Color(0xFF2E7D32);
    case 'running':
      return const Color(0xFFEF6C00);
    case 'queued':
      return const Color(0xFF6D4C41);
    case 'timed_out':
    case 'failed':
    case 'cancelled':
      return const Color(0xFFB71C1C);
    default:
      return const Color(0xFF5C514A);
  }
}

const String _pythonRunnerExampleInput = '''
{
  "powerWatts": [312.5, 318.2, 305.9, 330.4, 321.0]
}
''';

const String _pythonRunnerExampleCode = '''
import json
import os
import sys

raw = sys.stdin.read().strip()
payload = json.loads(raw) if raw else {}
samples = payload.get("powerWatts", [])

average = sum(samples) / len(samples) if samples else 0
result = {
    "sampleCount": len(samples),
    "averageWatts": round(average, 2),
    "peakWatts": round(max(samples), 2) if samples else None,
    "minWatts": round(min(samples), 2) if samples else None,
    "estimatedKWhPerDay": round((average * 24) / 1000, 3),
}

print(f"Analyzed {len(samples)} power samples.")

with open(os.environ["JOB_OUTPUT_PATH"], "w", encoding="utf-8") as handle:
    json.dump(result, handle)
''';

class _AlertsHero extends StatelessWidget {
  const _AlertsHero({
    required this.count,
    required this.statusFilter,
    required this.refreshError,
  });

  final int count;
  final String? statusFilter;
  final String? refreshError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (statusFilter) {
      'open' => 'Open alerts from the backend monitor',
      'resolved' => 'Resolved alerts kept in SQLite history',
      _ => 'All alert records from the backend monitor',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2E241F),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alert Inbox',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$count alert${count == 1 ? '' : 's'}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF1DFCD),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD3B49B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: Color(0xFFE8C7AA),
              ),
              const SizedBox(width: 8),
              Text(
                'Auto refresh every 10 seconds',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFE8C7AA),
                ),
              ),
            ],
          ),
          if (refreshError != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last auto refresh failed. Showing cached alerts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFF2AF7A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertFilterBar extends StatelessWidget {
  const _AlertFilterBar({required this.statusFilter, required this.onChanged});

  final String? statusFilter;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ChoiceChip(
          label: const Text('Open'),
          selected: statusFilter == 'open',
          onSelected: (_) => onChanged('open'),
        ),
        ChoiceChip(
          label: const Text('Resolved'),
          selected: statusFilter == 'resolved',
          onSelected: (_) => onChanged('resolved'),
        ),
        ChoiceChip(
          label: const Text('All'),
          selected: statusFilter == null,
          onSelected: (_) => onChanged(null),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onTap});

  final AlertItem alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityColor = _alertSeverityColor(alert.severity);
    final statusColor = _alertStatusColor(alert.status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2F2722),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          alert.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF655548),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _StatusBadge(
                        label: alert.severity.toUpperCase(),
                        color: severityColor,
                      ),
                      const SizedBox(height: 8),
                      _StatusBadge(
                        label: alert.status.toUpperCase(),
                        color: statusColor,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricChip(icon: Icons.dns_rounded, label: alert.chassisId),
                  _MetricChip(
                    icon: Icons.category_outlined,
                    label: alert.category,
                  ),
                  _MetricChip(icon: Icons.tag_rounded, label: '#${alert.id}'),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Last Seen',
                value: _formatTimestamp(alert.lastSeenAt),
              ),
              _DetailRow(
                label: 'First Seen',
                value: _formatTimestamp(alert.firstSeenAt),
              ),
              _DetailRow(label: 'Source', value: alert.sourceKey),
              if (alert.resolvedAt != null)
                _DetailRow(
                  label: 'Resolved',
                  value: _formatTimestamp(alert.resolvedAt!),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: const Color(0xFF8A6C55),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Open chassis detail',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8A6C55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SystemDetailPage extends StatefulWidget {
  const SystemDetailPage({
    super.key,
    required this.systemsApi,
    required this.system,
  });

  final SystemsApi systemsApi;
  final SystemSummary system;

  @override
  State<SystemDetailPage> createState() => _SystemDetailPageState();
}

class _SystemDetailPageState extends State<SystemDetailPage> {
  late Future<_SystemDetailBundle> _detailFuture;
  _SystemDetailBundle? _latestBundle;
  String? _detailRefreshError;
  String? _pendingResetType;
  String? _powerActionMessage;
  String? _powerActionError;

  @override
  void initState() {
    super.initState();
    _queueDetailRefresh();
  }

  Future<void> _refreshDetail() async {
    _queueDetailRefresh();
    await _detailFuture;
  }

  void _queueDetailRefresh() {
    final future = _loadDetailBundle();
    setState(() {
      _detailFuture = future;
      _detailRefreshError = null;
    });

    future
        .then((bundle) {
          if (!mounted) {
            return;
          }
          setState(() {
            _latestBundle = bundle;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!mounted || _latestBundle == null) {
            return;
          }
          setState(() {
            _detailRefreshError = '$error';
          });
        });
  }

  void _retry() {
    _queueDetailRefresh();
  }

  Future<_SystemDetailBundle> _loadDetailBundle() async {
    final detail = await widget.systemsApi.fetchSystemDetail(widget.system.id);
    final chassis = await widget.systemsApi.fetchChassisDetailsFromUris(
      detail.links.chassisUris,
    );
    return _SystemDetailBundle(detail: detail, chassis: chassis);
  }

  Future<void> _confirmPowerAction(
    SystemDetail detail,
    String resetType,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_powerActionLabel(resetType)),
        content: Text(
          'Send ${_powerActionLabel(resetType)} to ${detail.name ?? detail.id}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send Action'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _runPowerAction(resetType);
  }

  Future<void> _runPowerAction(String resetType) async {
    if (_pendingResetType != null) {
      return;
    }

    setState(() {
      _pendingResetType = resetType;
      _powerActionMessage = null;
      _powerActionError = null;
    });

    try {
      final result = await widget.systemsApi.resetSystemPower(
        widget.system.id,
        resetType: resetType,
      );
      if (!mounted) {
        return;
      }

      await _refreshDetail();
      if (!mounted) {
        return;
      }

      final summary = _buildPowerActionSummary(result);
      setState(() {
        _pendingResetType = null;
        _powerActionMessage = summary;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(summary)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = 'Power action failed: $error';
      setState(() {
        _pendingResetType = null;
        _powerActionError = message;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.system.name ?? widget.system.id),
        backgroundColor: const Color(0xFFF6EBDD),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5E5D2), Color(0xFFF9F4ED)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<_SystemDetailBundle>(
            future: _detailFuture,
            builder: (context, snapshot) {
              final bundle = snapshot.data ?? _latestBundle;
              final isRefreshing =
                  snapshot.connectionState == ConnectionState.waiting &&
                  bundle != null;

              if (snapshot.connectionState == ConnectionState.waiting &&
                  bundle == null) {
                return const _LoadingView(message: 'Loading system details...');
              }

              if (snapshot.hasError && bundle == null) {
                return _ErrorView(
                  title: 'Unable to load system details',
                  error: snapshot.error,
                  onRetry: _retry,
                );
              }

              if (bundle == null) {
                return const _EmptyView(
                  title: 'No details returned for this system.',
                  subtitle: 'Check the backend response, then try again.',
                );
              }

              final detail = bundle.detail;
              final chassisList = bundle.chassis;

              return RefreshIndicator(
                onRefresh: _refreshDetail,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (isRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    _DetailHero(system: detail),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Identity',
                      children: [
                        _DetailRow(label: 'ID', value: detail.id),
                        _DetailRow(
                          label: 'Host',
                          value: detail.hostName ?? '-',
                        ),
                        _DetailRow(
                          label: 'Manufacturer',
                          value: detail.manufacturer ?? '-',
                        ),
                        _DetailRow(label: 'Model', value: detail.model ?? '-'),
                        _DetailRow(
                          label: 'Serial',
                          value: detail.serialNumber ?? '-',
                        ),
                        _DetailRow(
                          label: 'Asset Tag',
                          value: detail.assetTag ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'System State',
                      children: [
                        _DetailRow(
                          label: 'Power',
                          value: detail.powerState ?? '-',
                        ),
                        _DetailRow(
                          label: 'Health',
                          value: detail.health ?? '-',
                        ),
                        _DetailRow(label: 'State', value: detail.state ?? '-'),
                        _DetailRow(
                          label: 'BIOS',
                          value: detail.biosVersion ?? '-',
                        ),
                        _DetailRow(
                          label: 'Last Reset',
                          value: detail.lastResetTime ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Power Control',
                      children: [
                        Text(
                          'Send Redfish ComputerSystem.Reset actions through the FastAPI middleware.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        if (detail.actions.reset.allowableValues.isEmpty)
                          const Text(
                            'No reset actions were advertised by the backend.',
                          )
                        else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: detail.actions.reset.allowableValues.map((
                              resetType,
                            ) {
                              final isRunning = _pendingResetType == resetType;
                              return FilledButton.tonalIcon(
                                onPressed: _pendingResetType == null
                                    ? () =>
                                          _confirmPowerAction(detail, resetType)
                                    : null,
                                icon: isRunning
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(_powerActionIcon(resetType)),
                                label: Text(_powerActionLabel(resetType)),
                              );
                            }).toList(),
                          ),
                        if (_powerActionMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _powerActionMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: const Color(0xFF25633F),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                        if (_powerActionError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _powerActionError!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                        if (_detailRefreshError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Last detail refresh failed. Showing cached data.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: const Color(0xFF8A6C55),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Compute',
                      children: [
                        _DetailRow(
                          label: 'CPU Count',
                          value: '${detail.processorCount ?? 0}',
                        ),
                        _DetailRow(
                          label: 'CPU Model',
                          value: detail.processorModel ?? '-',
                        ),
                        _DetailRow(
                          label: 'Memory',
                          value:
                              '${detail.memoryGiB?.toStringAsFixed(0) ?? '-'} GiB',
                        ),
                        _DetailRow(
                          label: 'LED',
                          value: detail.indicatorLed ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Linked Chassis',
                      children: [
                        if (chassisList.isEmpty)
                          const Text('No chassis linked to this system.')
                        else
                          ...chassisList.map(
                            (chassis) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ChassisCard(
                                chassis: chassis,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => ChassisDetailPage(
                                        systemsApi: widget.systemsApi,
                                        chassis: chassis,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Boot',
                      children: [
                        _DetailRow(
                          label: 'Enabled',
                          value: detail.boot.overrideEnabled ?? '-',
                        ),
                        _DetailRow(
                          label: 'Target',
                          value: detail.boot.overrideTarget ?? '-',
                        ),
                        _DetailRow(
                          label: 'Mode',
                          value: detail.boot.overrideMode ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Description',
                      children: [
                        Text(
                          detail.description ?? 'No description provided.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Redfish Links',
                      children: [
                        _DetailRow(
                          label: 'System URI',
                          value: detail.redfishUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'BIOS URI',
                          value: detail.links.biosUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Processors',
                          value: detail.links.processorsUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Memory',
                          value: detail.links.memoryUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Ethernet',
                          value: detail.links.ethernetInterfacesUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Chassis',
                          value: detail.links.chassisUris.isEmpty
                              ? '-'
                              : detail.links.chassisUris.join(', '),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SystemDetailBundle {
  const _SystemDetailBundle({required this.detail, required this.chassis});

  final SystemDetail detail;
  final List<ChassisDetail> chassis;
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.system});

  final SystemDetail system;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthColor = _healthColor(system.health);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2E241F),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  system.name ?? system.id,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(
                label: system.health ?? 'Unknown',
                color: healthColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            system.hostName ?? system.id,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF1DFCD),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.bolt_rounded,
                label: 'Power ${system.powerState ?? 'Unknown'}',
              ),
              _MetricChip(
                icon: Icons.memory_rounded,
                label: system.model ?? 'Unknown model',
              ),
              _MetricChip(
                icon: Icons.sd_storage_rounded,
                label: '${system.memoryGiB?.toStringAsFixed(0) ?? '-'} GiB RAM',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2F2722),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ChassisCard extends StatelessWidget {
  const _ChassisCard({required this.chassis, required this.onTap});

  final ChassisDetail chassis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthColor = _healthColor(chassis.health);

    return Material(
      color: const Color(0xFFF8F1E7),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chassis.name ?? chassis.id,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2F2722),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8A6C55),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(
                    label: chassis.health ?? 'Unknown',
                    color: healthColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricChip(
                    icon: Icons.inventory_2_rounded,
                    label: chassis.chassisType ?? 'Unknown type',
                  ),
                  _MetricChip(
                    icon: Icons.bolt_rounded,
                    label: 'Power ${chassis.powerState ?? 'Unknown'}',
                  ),
                  _MetricChip(
                    icon: Icons.view_in_ar_rounded,
                    label: chassis.model ?? 'Unknown model',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailRow(label: 'Chassis ID', value: chassis.id),
              _DetailRow(label: 'Rack', value: chassis.rack ?? '-'),
              _DetailRow(label: 'Row', value: chassis.row ?? '-'),
              _DetailRow(label: 'Serial', value: chassis.serialNumber ?? '-'),
              _DetailRow(label: 'Asset Tag', value: chassis.assetTag ?? '-'),
              _DetailRow(
                label: 'Dimensions',
                value: _formatDimensions(chassis),
              ),
              _DetailRow(
                label: 'Managers',
                value: chassis.managerUris.isEmpty
                    ? '-'
                    : chassis.managerUris.join(', '),
              ),
              _DetailRow(label: 'Sensors', value: chassis.sensorsUri ?? '-'),
            ],
          ),
        ),
      ),
    );
  }
}

class ChassisDetailPage extends StatefulWidget {
  ChassisDetailPage({
    super.key,
    required this.systemsApi,
    required this.chassis,
  }) : _alertChassisId = null,
       initialTitle = null;

  ChassisDetailPage.fromAlert({
    super.key,
    required this.systemsApi,
    required String chassisId,
    this.initialTitle,
  }) : chassis = null,
       _alertChassisId = chassisId;

  final SystemsApi systemsApi;
  final ChassisDetail? chassis;
  final String? _alertChassisId;
  final String? initialTitle;

  String get chassisId => chassis?.id ?? _alertChassisId!;
  String get displayTitle => chassis?.name ?? initialTitle ?? chassisId;

  @override
  State<ChassisDetailPage> createState() => _ChassisDetailPageState();
}

class _ChassisDetailPageState extends State<ChassisDetailPage> {
  static const Duration _telemetryRefreshInterval = Duration(seconds: 5);
  static const Duration _telemetryReconnectInterval = Duration(seconds: 3);
  static const int _trendPointLimit = 30;

  late Future<_ChassisDetailBundle> _detailFuture;
  _ChassisDetailBundle? _latestBundle;
  Timer? _telemetryFallbackTimer;
  Timer? _telemetryReconnectTimer;
  StreamSubscription<ChassisTelemetryCurrent>? _telemetrySubscription;
  String? _telemetryRefreshError;
  String _telemetryTransportLabel = 'Connecting live stream...';
  String? _pendingTemperatureThresholdId;
  final List<_TrendPoint> _temperatureTrend = <_TrendPoint>[];
  final Map<String, List<_TrendPoint>> _fanTrendPoints =
      <String, List<_TrendPoint>>{};
  final Map<String, String> _fanTrendLabels = <String, String>{};
  String? _lastRecordedTelemetryTimestamp;

  @override
  void initState() {
    super.initState();
    _queueDetailRefresh();
    _connectTelemetryStream();
  }

  @override
  void dispose() {
    _telemetryFallbackTimer?.cancel();
    _telemetryReconnectTimer?.cancel();
    _telemetrySubscription?.cancel();
    super.dispose();
  }

  Future<_ChassisDetailBundle> _loadChassisBundle() async {
    final results = await Future.wait<dynamic>([
      widget.systemsApi.fetchChassisDetail(widget.chassisId),
      widget.systemsApi.fetchChassisTelemetryCurrent(widget.chassisId),
    ]);
    return _ChassisDetailBundle(
      detail: results[0] as ChassisDetail,
      telemetry: results[1] as ChassisTelemetryCurrent,
    );
  }

  void _queueDetailRefresh() {
    final future = _loadChassisBundle();
    setState(() {
      _detailFuture = future;
      _telemetryRefreshError = null;
    });

    future
        .then((bundle) {
          if (!mounted) {
            return;
          }
          setState(() {
            _recordTelemetry(bundle.telemetry, reset: _latestBundle == null);
            _latestBundle = bundle;
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!mounted || _latestBundle == null) {
            return;
          }
          setState(() {
            _telemetryRefreshError = '$error';
          });
        });
  }

  Future<void> _refreshTelemetrySilently() async {
    print("HTTP refresh triggered");
    final currentBundle = _latestBundle;
    if (currentBundle == null) {
      return;
    }

    try {
      final telemetry = await widget.systemsApi.fetchChassisTelemetryCurrent(
        widget.chassisId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _recordTelemetry(telemetry);
        _latestBundle = currentBundle.copyWith(telemetry: telemetry);
        _telemetryRefreshError = null;
        if (_telemetryFallbackTimer != null) {
          _telemetryTransportLabel = 'HTTP fallback every 5s';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _telemetryRefreshError = '$error';
      });
    }
  }

  void _connectTelemetryStream() {
    _telemetryReconnectTimer?.cancel();
    _telemetrySubscription?.cancel();

    final stream = widget.systemsApi.watchChassisTelemetry(widget.chassisId);
    if (stream == null) {
      _startTelemetryFallback(
        'WebSocket stream is unavailable. Falling back to HTTP refresh.',
      );
      return;
    }

    _telemetrySubscription = stream.listen(
      (telemetry) {
        print("WS TEMP = ${telemetry.temperatures.first.celsius}");
        if (!mounted) {
          return;
        }

        final currentBundle = _latestBundle;
        if (currentBundle == null) {
          return;
        }

        _telemetryFallbackTimer?.cancel();
        _telemetryFallbackTimer = null;
        setState(() {
          _recordTelemetry(telemetry);
          _latestBundle = currentBundle.copyWith(telemetry: telemetry);
          _telemetryRefreshError = null;
          _telemetryTransportLabel = 'Live via WebSocket';
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        _startTelemetryFallback(
          'WebSocket update failed. Falling back to HTTP refresh. $error',
        );
        _scheduleTelemetryReconnect();
      },
      onDone: () {
        _startTelemetryFallback(
          'WebSocket disconnected. Falling back to HTTP refresh.',
        );
        _scheduleTelemetryReconnect();
      },
      cancelOnError: true,
    );
  }

  void _scheduleTelemetryReconnect() {
    _telemetryReconnectTimer?.cancel();
    _telemetryReconnectTimer = Timer(_telemetryReconnectInterval, () {
      if (!mounted) {
        return;
      }
      _connectTelemetryStream();
    });
  }

  void _startTelemetryFallback(String message) {
    _telemetryFallbackTimer?.cancel();
    _telemetryFallbackTimer = Timer.periodic(
      _telemetryRefreshInterval,
      (_) => _refreshTelemetrySilently(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _telemetryRefreshError = message;
      _telemetryTransportLabel = 'HTTP fallback every 5s';
    });
  }

  Future<void> _refreshDetail() async {
    _queueDetailRefresh();
    await _detailFuture;
  }

  void _retry() {
    _queueDetailRefresh();
    _connectTelemetryStream();
  }

  Future<void> _editTemperatureThresholds(
    TemperatureReading temperature,
  ) async {
    final nextValues = await _promptTemperatureThresholds(temperature);
    if (nextValues == null) {
      return;
    }

    await _runTemperatureThresholdUpdate(
      temperature: temperature,
      upperCaution: nextValues['upperCaution']!,
      upperCritical: nextValues['upperCritical']!,
      upperFatal: nextValues['upperFatal']!,
    );
  }

  Future<Map<String, double>?> _promptTemperatureThresholds(
    TemperatureReading temperature,
  ) async {
    final cautionController = TextEditingController(
      text: temperature.upperCaution?.toStringAsFixed(1) ?? '',
    );
    final criticalController = TextEditingController(
      text: temperature.upperCritical?.toStringAsFixed(1) ?? '',
    );
    final fatalController = TextEditingController(
      text: temperature.upperFatal?.toStringAsFixed(1) ?? '',
    );
    String? cautionErrorText;
    String? criticalErrorText;
    String? fatalErrorText;
    String? dialogErrorText;

    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit Temperature Thresholds'),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temperature.name ?? temperature.id,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cautionController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Upper caution (°C)',
                      hintText: 'e.g. 38.0',
                      errorText: cautionErrorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: criticalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Upper critical (°C)',
                      hintText: 'e.g. 45.0',
                      errorText: criticalErrorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fatalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Upper fatal (°C)',
                      hintText: 'e.g. 48.0',
                      errorText: fatalErrorText,
                    ),
                  ),
                  if (dialogErrorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogErrorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final caution = double.tryParse(
                      cautionController.text.trim(),
                    );
                    final critical = double.tryParse(
                      criticalController.text.trim(),
                    );
                    final fatal = double.tryParse(fatalController.text.trim());

                    final nextCautionError = caution == null
                        ? 'Enter a valid temperature value.'
                        : null;
                    final nextCriticalError = critical == null
                        ? 'Enter a valid temperature value.'
                        : null;
                    final nextFatalError = fatal == null
                        ? 'Enter a valid temperature value.'
                        : null;

                    if (nextCautionError != null ||
                        nextCriticalError != null ||
                        nextFatalError != null) {
                      setStateDialog(() {
                        cautionErrorText = nextCautionError;
                        criticalErrorText = nextCriticalError;
                        fatalErrorText = nextFatalError;
                        dialogErrorText = null;
                      });
                      return;
                    }

                    if (caution! > critical!) {
                      setStateDialog(() {
                        cautionErrorText =
                            'Caution must be less than or equal to critical.';
                        criticalErrorText =
                            'Critical must be greater than or equal to caution.';
                        fatalErrorText = null;
                        dialogErrorText = null;
                      });
                      return;
                    }

                    if (critical > fatal!) {
                      setStateDialog(() {
                        cautionErrorText = null;
                        criticalErrorText =
                            'Critical must be less than or equal to fatal.';
                        fatalErrorText =
                            'Fatal must be greater than or equal to critical.';
                        dialogErrorText = null;
                      });
                      return;
                    }

                    Navigator.of(context).pop({
                      'upperCaution': caution,
                      'upperCritical': critical,
                      'upperFatal': fatal,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
        cautionController.dispose();
        criticalController.dispose();
        fatalController.dispose();
      }),
    );
    return result;
  }

  Future<void> _runTemperatureThresholdUpdate({
    required TemperatureReading temperature,
    required double upperCaution,
    required double upperCritical,
    required double upperFatal,
  }) async {
    if (_pendingTemperatureThresholdId != null) {
      return;
    }

    setState(() {
      _pendingTemperatureThresholdId = temperature.id;
    });

    try {
      final updatedTemperature = await widget.systemsApi
          .updateTemperatureThresholds(
            widget.chassisId,
            temperature.id,
            upperCaution: upperCaution,
            upperCritical: upperCritical,
            upperFatal: upperFatal,
          );
      if (!mounted) {
        return;
      }

      await _refreshTelemetrySilently();
      if (!mounted) {
        return;
      }

      final message =
          'Updated ${updatedTemperature.name ?? updatedTemperature.id} thresholds to '
          'Caution ${_formatTemperature(updatedTemperature.upperCaution)}, '
          'Critical ${_formatTemperature(updatedTemperature.upperCritical)}, '
          'Fatal ${_formatTemperature(updatedTemperature.upperFatal)}.';
      setState(() {
        _pendingTemperatureThresholdId = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingTemperatureThresholdId = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Threshold update failed: $error')),
        );
    }
  }

  void _recordTelemetry(
    ChassisTelemetryCurrent telemetry, {
    bool reset = false,
  }) {
    if (reset) {
      _temperatureTrend.clear();
      _fanTrendPoints.clear();
      _fanTrendLabels.clear();
      _lastRecordedTelemetryTimestamp = null;
    }

    if (_lastRecordedTelemetryTimestamp == telemetry.timestamp) {
      return;
    }

    final sampleTime =
        DateTime.tryParse(telemetry.timestamp)?.toLocal() ?? DateTime.now();
    final summaryTemperature = telemetry.summary.temperatureCelsius;
    if (summaryTemperature != null) {
      _appendTrendPoint(
        _temperatureTrend,
        _TrendPoint(timestamp: sampleTime, value: summaryTemperature),
      );
    }

    for (final fan in telemetry.fans) {
      final rpm = fan.rpm;
      if (rpm == null) {
        continue;
      }

      _fanTrendLabels[fan.id] = fan.name ?? fan.id;
      final points = _fanTrendPoints.putIfAbsent(fan.id, () => <_TrendPoint>[]);
      _appendTrendPoint(points, _TrendPoint(timestamp: sampleTime, value: rpm));
    }

    _lastRecordedTelemetryTimestamp = telemetry.timestamp;
  }

  void _appendTrendPoint(List<_TrendPoint> points, _TrendPoint point) {
    if (points.isNotEmpty &&
        points.last.timestamp.isAtSameMomentAs(point.timestamp)) {
      return;
    }

    points.add(point);
    if (points.length > _trendPointLimit) {
      points.removeRange(0, points.length - _trendPointLimit);
    }
  }

  List<_TrendSeries> _buildFanTrendSeries() {
    final entries = _fanTrendPoints.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));

    return entries.indexed
        .map((entry) {
          final index = entry.$1;
          final fanEntry = entry.$2;
          return _TrendSeries(
            label: _fanTrendLabels[fanEntry.key] ?? fanEntry.key,
            color: _trendPalette[index % _trendPalette.length],
            points: List<_TrendPoint>.unmodifiable(fanEntry.value),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_latestBundle?.detail.name ?? widget.displayTitle),
        backgroundColor: const Color(0xFFF6EBDD),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF3E2CF), Color(0xFFF9F5EF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<_ChassisDetailBundle>(
            future: _detailFuture,
            builder: (context, snapshot) {
              //final bundle = snapshot.data ?? _latestBundle;
              final bundle = _latestBundle ?? snapshot.data;
              final isRefreshing =
                  snapshot.connectionState == ConnectionState.waiting &&
                  bundle != null;

              if (snapshot.connectionState == ConnectionState.waiting &&
                  bundle == null) {
                return const _LoadingView(
                  message: 'Loading chassis details...',
                );
              }

              if (snapshot.hasError && bundle == null) {
                return _ErrorView(
                  title: 'Unable to load chassis details',
                  error: snapshot.error,
                  onRetry: _retry,
                );
              }

              if (bundle == null) {
                return const _EmptyView(
                  title: 'No details returned for this chassis.',
                  subtitle: 'Check the backend response, then try again.',
                );
              }

              final chassis = bundle.detail;
              final telemetry =  _latestBundle!.telemetry;

              return RefreshIndicator(
                onRefresh: _refreshDetail,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (isRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    _ChassisHero(chassis: chassis),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Chassis Identity',
                      children: [
                        _DetailRow(label: 'ID', value: chassis.id),
                        _DetailRow(label: 'Name', value: chassis.name ?? '-'),
                        _DetailRow(
                          label: 'Manufacturer',
                          value: chassis.manufacturer ?? '-',
                        ),
                        _DetailRow(label: 'Model', value: chassis.model ?? '-'),
                        _DetailRow(
                          label: 'Serial',
                          value: chassis.serialNumber ?? '-',
                        ),
                        _DetailRow(
                          label: 'Asset Tag',
                          value: chassis.assetTag ?? '-',
                        ),
                        _DetailRow(
                          label: 'URI',
                          value: chassis.redfishUri ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Chassis Status',
                      children: [
                        _DetailRow(
                          label: 'Type',
                          value: chassis.chassisType ?? '-',
                        ),
                        _DetailRow(
                          label: 'Power',
                          value: chassis.powerState ?? '-',
                        ),
                        _DetailRow(
                          label: 'Health',
                          value: chassis.health ?? '-',
                        ),
                        _DetailRow(label: 'State', value: chassis.state ?? '-'),
                        _DetailRow(
                          label: 'Indicator',
                          value: chassis.indicatorLed ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _TelemetrySummarySection(
                      telemetry: telemetry,
                      refreshError: _telemetryRefreshError,
                      transportLabel: _telemetryTransportLabel,
                    ),
                    const SizedBox(height: 16),
                    _TelemetryTrendSection(
                      title: 'Temperature Trend',
                      subtitle: 'Recent chassis temperature updates',
                      emptyMessage: 'Waiting for live temperature samples.',
                      series: [
                        _TrendSeries(
                          label: 'System Temp',
                          color: const Color(0xFFFF8F5A),
                          points: List<_TrendPoint>.unmodifiable(
                            _temperatureTrend,
                          ),
                        ),
                      ],
                      valueFormatter: _formatTemperatureValue,
                    ),
                    const SizedBox(height: 16),
                    _TelemetryTrendSection(
                      title: 'Fan RPM Trend',
                      subtitle: 'Recent fan speed updates',
                      emptyMessage: 'Waiting for live RPM samples.',
                      series: _buildFanTrendSeries(),
                      valueFormatter: _formatRpmValue,
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Temperatures',
                      children: [
                        if (telemetry.temperatures.isEmpty)
                          const Text('No temperature readings returned.')
                        else
                          ...telemetry.temperatures.map(
                            (temperature) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TelemetryCard(
                                title: temperature.name ?? temperature.id,
                                subtitle: temperature.physicalContext,
                                health: temperature.health,
                                
                                footer: Row(
                                  children: [

                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            _pendingTemperatureThresholdId == null
                                            ? () => _editTemperatureThresholds(
                                                temperature,
                                              )
                                            : null,
                                        icon:
                                            _pendingTemperatureThresholdId ==
                                                    temperature.id
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.thermostat_auto_rounded,
                                                  ),
                                        label: Text(
                                          _pendingTemperatureThresholdId ==
                                                  temperature.id
                                              ? 'Saving...'
                                              : 'Edit thresholds',
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    FilledButton.icon(
                                      onPressed: () async {
                                        print("Edit Current clicked");

                                        final controller = TextEditingController(
                                          text: temperature.celsius?.toString() ?? '',
                                        );

                                        final result = await showDialog<double>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: const Text("Edit Temperature"),
                                              content: TextField(
                                                controller: controller,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: const InputDecoration(
                                                  labelText: "CPU Temp",
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context),
                                                  child: const Text("Cancel"),
                                                ),
                                                FilledButton(
                                                  onPressed: () {
                                                    final value = double.tryParse(controller.text);
                                                    Navigator.pop(context, value);
                                                  },
                                                  child: const Text("Save"),
                                                ),
                                              ],
                                            );
                                          },
                                        );

                                        if (result == null) return;

                                        final api = SystemsApi();

                                        

                                        if (temperature.id == "0") {
                                          await api.updateTelemetryOverride(
                                            chassisId: widget.chassisId,
                                            cpu1Temp: result,
                                          );
                                        } else if (temperature.id == "1") {
                                          await api.updateTelemetryOverride(
                                            chassisId: widget.chassisId,
                                            cpu2Temp: result,
                                          );
                                        } else if (temperature.id == "2") {
                                          await api.updateTelemetryOverride(
                                            chassisId: widget.chassisId,
                                            intakeTemp: result,
                                          );
                                        }



                                        print("API called");

                                        final newData =
                                            await api.fetchChassisTelemetryCurrent(widget.chassisId);

                                        setState(() {
                                          _latestBundle = _latestBundle!.copyWith(
                                            telemetry: newData,
                                          );
                                        });
                                      },















                                      icon: const Icon(Icons.edit),
                                      label: const Text("Edit Current"),
                                    ),



                                    FilledButton(
                                      onPressed: () async {
                                        final api = SystemsApi();

                                        await api.clearTelemetryOverride(
                                          chassisId: widget.chassisId,
                                        );

                                        final newData =
                                            await api.fetchChassisTelemetryCurrent(widget.chassisId);

                                        setState(() {
                                          _latestBundle = _latestBundle!.copyWith(
                                            telemetry: newData,
                                          );
                                        });
                                      },
                                      child: const Text("Clear Override"),
                                    ),























                                  ],
                                ),                                







                                
                                rows: [
                                  _DetailRow(
                                    label: 'Current',
                                    value: _formatTemperature(
                                      temperature.celsius,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'State',
                                    value: temperature.state ?? '-',
                                  ),
                                  _DetailRow(
                                    label: 'Caution',
                                    value: _formatTemperature(
                                      temperature.upperCaution,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Critical',
                                    value: _formatTemperature(
                                      temperature.upperCritical,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Fatal',
                                    value: _formatTemperature(
                                      temperature.upperFatal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Fans',
                      children: [
                        if (telemetry.fans.isEmpty)
                          const Text('No fan readings returned.')
                        else
                          ...telemetry.fans.map(
                            (fan) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TelemetryCard(
                                title: fan.name ?? fan.id,
                                subtitle: fan.physicalContext,
                                health: fan.health,
                                rows: [
                                  _DetailRow(
                                    label: 'Speed',
                                    value: _formatRpm(fan.rpm),
                                    
                                  ),
                                  _DetailRow(
                                    label: 'State',
                                    value: fan.state ?? '-',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Power Controls',
                      children: [
                        if (telemetry.powerControls.isEmpty)
                          const Text('No power control readings returned.')
                        else
                          ...telemetry.powerControls.map(
                            (powerControl) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TelemetryCard(
                                title: powerControl.name ?? powerControl.id,
                                health: powerControl.health,
                                rows: [
                                  _DetailRow(
                                    label: 'Consumed',
                                    value: _formatWatts(
                                      powerControl.consumedWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Average',
                                    value: _formatWatts(
                                      powerControl.averageWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Peak',
                                    value: _formatWatts(powerControl.peakWatts),
                                  ),
                                  _DetailRow(
                                    label: 'Capacity',
                                    value: _formatWatts(
                                      powerControl.capacityWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Allocated',
                                    value: _formatWatts(
                                      powerControl.allocatedWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'State',
                                    value: powerControl.state ?? '-',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Power Supplies',
                      children: [
                        if (telemetry.powerSupplies.isEmpty)
                          const Text('No power supply readings returned.')
                        else
                          ...telemetry.powerSupplies.map(
                            (powerSupply) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TelemetryCard(
                                title: powerSupply.name ?? powerSupply.id,
                                health: powerSupply.health,
                                rows: [
                                  _DetailRow(
                                    label: 'Output',
                                    value: _formatWatts(
                                      powerSupply.lastOutputWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'Capacity',
                                    value: _formatWatts(
                                      powerSupply.capacityWatts,
                                    ),
                                  ),
                                  _DetailRow(
                                    label: 'State',
                                    value: powerSupply.state ?? '-',
                                  ),
                                  _DetailRow(
                                    label: 'Model',
                                    value: powerSupply.model ?? '-',
                                  ),
                                  _DetailRow(
                                    label: 'Firmware',
                                    value: powerSupply.firmwareVersion ?? '-',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Chassis Layout',
                      children: [
                        _DetailRow(label: 'Rack', value: chassis.rack ?? '-'),
                        _DetailRow(label: 'Row', value: chassis.row ?? '-'),
                        _DetailRow(
                          label: 'Dimensions',
                          value: _formatDimensions(chassis),
                        ),
                        _DetailRow(
                          label: 'Weight',
                          value: chassis.weightKg == null
                              ? '-'
                              : '${chassis.weightKg!.toStringAsFixed(2)} kg',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Telemetry Links',
                      children: [
                        _DetailRow(
                          label: 'Thermal',
                          value: chassis.thermalUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Power',
                          value: chassis.powerUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Sensors',
                          value: chassis.sensorsUri ?? '-',
                        ),
                        _DetailRow(
                          label: 'Environment',
                          value: chassis.environmentMetricsUri ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: 'Relationships',
                      children: [
                        _DetailRow(
                          label: 'Systems',
                          value: chassis.computerSystemIds.isEmpty
                              ? '-'
                              : chassis.computerSystemIds.join(', '),
                        ),
                        _DetailRow(
                          label: 'Managed By',
                          value: chassis.managedByUris.isEmpty
                              ? '-'
                              : chassis.managedByUris.join(', '),
                        ),
                        _DetailRow(
                          label: 'Managers',
                          value: chassis.managerUris.isEmpty
                              ? '-'
                              : chassis.managerUris.join(', '),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChassisDetailBundle {
  _ChassisDetailBundle({required this.detail, required this.telemetry});

  final ChassisDetail detail;
  late ChassisTelemetryCurrent telemetry;
  bool loading = true;

  _ChassisDetailBundle copyWith({
    ChassisDetail? detail,
    ChassisTelemetryCurrent? telemetry,
  }) {
    return _ChassisDetailBundle(
      detail: detail ?? this.detail,
      telemetry: telemetry ?? this.telemetry,
    );
  }
}

class _ChassisHero extends StatelessWidget {
  const _ChassisHero({required this.chassis});

  final ChassisDetail chassis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthColor = _healthColor(chassis.health);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2E241F),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  chassis.name ?? chassis.id,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(
                label: chassis.health ?? 'Unknown',
                color: healthColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            chassis.chassisType ?? chassis.id,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF1DFCD),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.bolt_rounded,
                label: 'Power ${chassis.powerState ?? 'Unknown'}',
              ),
              _MetricChip(
                icon: Icons.view_in_ar_rounded,
                label: chassis.model ?? 'Unknown model',
              ),
              _MetricChip(
                icon: Icons.grid_view_rounded,
                label: chassis.rack ?? 'Unknown rack',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetrySummarySection extends StatelessWidget {
  const _TelemetrySummarySection({
    required this.telemetry,
    required this.refreshError,
    required this.transportLabel,
  });

  final ChassisTelemetryCurrent telemetry;
  final String? refreshError;
  final String transportLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthColor = _healthColor(telemetry.summary.health);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2B3024),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Live Telemetry',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(
                label: telemetry.summary.health ?? 'Unknown',
                color: healthColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.thermostat_rounded,
                label: _formatTemperature(telemetry.summary.temperatureCelsius),
              ),
              _MetricChip(
                icon: Icons.electric_bolt_rounded,
                label: _formatWatts(telemetry.summary.powerWatts),
              ),
              _MetricChip(
                icon: Icons.monitor_heart_rounded,
                label: telemetry.summary.health ?? 'Unknown health',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TelemetryMetaRow(
            label: 'Updated',
            value: _formatTimestamp(telemetry.timestamp),
          ),
          const SizedBox(height: 6),
          _TelemetryMetaRow(label: 'Transport', value: transportLabel),
          if (refreshError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last live update failed: $refreshError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFF0C7A3),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TelemetryTrendSection extends StatelessWidget {
  const _TelemetryTrendSection({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.series,
    required this.valueFormatter,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<_TrendSeries> series;
  final String Function(double value) valueFormatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = series.expand((item) => item.points).toList(growable: false);
    final metrics = _TrendMetrics.fromPoints(points);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF242A27),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD7C8BA),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (series.isEmpty || points.isEmpty)
            Text(
              emptyMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFE7D8CA),
              ),
            )
          else ...[
            Row(
              children: [
                _TrendMetricChip(
                  label: 'Peak',
                  value: valueFormatter(metrics.max),
                ),
                const SizedBox(width: 10),
                _TrendMetricChip(
                  label: 'Floor',
                  value: valueFormatter(metrics.min),
                ),
                const SizedBox(width: 10),
                _TrendMetricChip(
                  label: 'Window',
                  value: '${metrics.sampleCount} pts',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendChartPainter(
                  series: series,
                  minValue: metrics.min,
                  maxValue: metrics.max,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatTrendClock(metrics.startTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD7C8BA),
                    ),
                  ),
                ),
                Text(
                  _formatTrendClock(metrics.endTime),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFD7C8BA),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: series
                  .where((item) => item.points.isNotEmpty)
                  .map(
                    (item) => _TrendLegendChip(
                      color: item.color,
                      label: item.label,
                      value: valueFormatter(item.points.last.value),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendMetricChip extends StatelessWidget {
  const _TrendMetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF343C37),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD7C8BA),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLegendChip extends StatelessWidget {
  const _TrendLegendChip({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF343C37),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD7C8BA),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.series,
    required this.minValue,
    required this.maxValue,
  });

  final List<_TrendSeries> series;
  final double minValue;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    const chartPadding = EdgeInsets.fromLTRB(8, 10, 8, 16);
    final chartRect = Rect.fromLTWH(
      chartPadding.left,
      chartPadding.top,
      size.width - chartPadding.horizontal,
      size.height - chartPadding.vertical,
    );
    if (chartRect.width <= 0 || chartRect.height <= 0) {
      return;
    }

    final gridPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var step = 0; step < 4; step += 1) {
      final y = chartRect.top + (chartRect.height / 3) * step;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final range = (maxValue - minValue).abs() < 0.01
        ? 1.0
        : maxValue - minValue;

    for (final trendSeries in series) {
      if (trendSeries.points.isEmpty) {
        continue;
      }

      final path = Path();
      for (final indexedPoint in trendSeries.points.indexed) {
        final index = indexedPoint.$1;
        final point = indexedPoint.$2;
        final dx = trendSeries.points.length == 1
            ? chartRect.center.dx
            : chartRect.left +
                  (chartRect.width * index / (trendSeries.points.length - 1));
        final normalizedY = (point.value - minValue) / range;
        final dy = chartRect.bottom - normalizedY * chartRect.height;
        if (index == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }

      final linePaint = Paint()
        ..color = trendSeries.color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, linePaint);

      final lastPoint = trendSeries.points.last;
      final lastDx = trendSeries.points.length == 1
          ? chartRect.center.dx
          : chartRect.right;
      final lastDy =
          chartRect.bottom -
          ((lastPoint.value - minValue) / range) * chartRect.height;
      canvas.drawCircle(
        Offset(lastDx, lastDy),
        4,
        Paint()..color = trendSeries.color,
      );
      canvas.drawCircle(
        Offset(lastDx, lastDy),
        7,
        Paint()..color = trendSeries.color.withAlpha(70),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    if (minValue != oldDelegate.minValue || maxValue != oldDelegate.maxValue) {
      return true;
    }
    if (series.length != oldDelegate.series.length) {
      return true;
    }

    for (var index = 0; index < series.length; index += 1) {
      final current = series[index];
      final previous = oldDelegate.series[index];
      if (current.label != previous.label ||
          current.color != previous.color ||
          current.points.length != previous.points.length) {
        return true;
      }
      if (current.points.isNotEmpty &&
          previous.points.isNotEmpty &&
          current.points.last != previous.points.last) {
        return true;
      }
    }
    return false;
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.title,
    required this.rows,
    this.subtitle,
    this.health,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final String? health;
  final List<Widget> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: const Color(0xFFF8F1E7),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2F2722),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF7A6657),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (health != null)
                  _StatusBadge(label: health!, color: _healthColor(health)),
              ],
            ),
            const SizedBox(height: 12),
            ...rows,
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }
}

class _TelemetryMetaRow extends StatelessWidget {
  const _TelemetryMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD0B7A1),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2E7DA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF7D5632)),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF826953),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2D2621),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.message = 'Loading systems...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.portable_wifi_off_rounded,
              size: 44,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Use --dart-define=API_BASE_URL=http://<your-ip>:8000 when running on a device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6C5B4F),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    this.title = 'No systems returned by the backend.',
    this.subtitle =
        'Check that FastAPI can reach the Redfish service, then pull to refresh.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storage_rounded,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TrendPoint {
  const _TrendPoint({required this.timestamp, required this.value});

  final DateTime timestamp;
  final double value;

  @override
  bool operator ==(Object other) {
    return other is _TrendPoint &&
        other.timestamp == timestamp &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(timestamp, value);
}

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.points,
  });

  final String label;
  final Color color;
  final List<_TrendPoint> points;
}

class _TrendMetrics {
  const _TrendMetrics({
    required this.min,
    required this.max,
    required this.startTime,
    required this.endTime,
    required this.sampleCount,
  });

  final double min;
  final double max;
  final DateTime startTime;
  final DateTime endTime;
  final int sampleCount;

  factory _TrendMetrics.fromPoints(List<_TrendPoint> points) {
    if (points.isEmpty) {
      final now = DateTime.now();
      return _TrendMetrics(
        min: 0,
        max: 0,
        startTime: now,
        endTime: now,
        sampleCount: 0,
      );
    }

    var minValue = points.first.value;
    var maxValue = points.first.value;
    for (final point in points.skip(1)) {
      minValue = math.min(minValue, point.value);
      maxValue = math.max(maxValue, point.value);
    }

    final range = (maxValue - minValue).abs();
    if (range < 0.01) {
      minValue -= 1;
      maxValue += 1;
    } else {
      final padding = range * 0.12;
      minValue -= padding;
      maxValue += padding;
    }

    return _TrendMetrics(
      min: minValue,
      max: maxValue,
      startTime: points.first.timestamp,
      endTime: points.last.timestamp,
      sampleCount: points.length,
    );
  }
}

const List<Color> _trendPalette = [
  Color(0xFFFF8F5A),
  Color(0xFF5FBF8F),
  Color(0xFFF7C65C),
  Color(0xFF74B5FF),
];

Color _healthColor(String? health) {
  switch (health?.toUpperCase()) {
    case 'OK':
      return const Color(0xFF256A3D);
    case 'WARNING':
      return const Color(0xFFBA6E13);
    case 'CRITICAL':
      return const Color(0xFFB43B2D);
    default:
      return const Color(0xFF66574C);
  }
}

Color _alertSeverityColor(String? severity) {
  switch (severity?.toLowerCase()) {
    case 'warning':
      return const Color(0xFFBA6E13);
    case 'critical':
      return const Color(0xFFB43B2D);
    default:
      return const Color(0xFF66574C);
  }
}

Color _alertStatusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'open':
      return const Color(0xFF8A4E1C);
    case 'resolved':
      return const Color(0xFF3F6F4D);
    default:
      return const Color(0xFF66574C);
  }
}

String _emptyAlertsTitle(String? statusFilter) {
  switch (statusFilter) {
    case 'open':
      return 'No open alerts right now.';
    case 'resolved':
      return 'No resolved alerts in history yet.';
    default:
      return 'No alerts returned by the backend.';
  }
}

String _formatTemperatureValue(double value) =>
    '${value.toStringAsFixed(1)} °C';

String _formatRpmValue(double value) => '${value.toStringAsFixed(0)} RPM';

String _powerActionLabel(String resetType) {
  switch (resetType) {
    case 'GracefulRestart':
      return 'Graceful Restart';
    case 'ForceRestart':
      return 'Force Restart';
    case 'GracefulShutdown':
      return 'Graceful Shutdown';
    case 'ForceOff':
      return 'Force Off';
    case 'ForceOn':
      return 'Force On';
    case 'PushPowerButton':
      return 'Push Power Button';
    case 'Nmi':
      return 'Send NMI';
    default:
      return resetType;
  }
}

IconData _powerActionIcon(String resetType) {
  switch (resetType) {
    case 'GracefulRestart':
    case 'ForceRestart':
      return Icons.restart_alt_rounded;
    case 'GracefulShutdown':
    case 'ForceOff':
      return Icons.power_settings_new_rounded;
    case 'ForceOn':
    case 'On':
      return Icons.power_rounded;
    case 'PushPowerButton':
      return Icons.touch_app_rounded;
    case 'Nmi':
      return Icons.warning_amber_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

String _buildPowerActionSummary(SystemResetResult result) {
  final base = result.message ?? _powerActionLabel(result.resetType);
  if (result.powerState == null || result.powerState!.isEmpty) {
    return base;
  }
  return '$base Power is now ${result.powerState}.';
}

String _formatDimensions(ChassisDetail chassis) {
  final parts = <String>[];
  if (chassis.widthMm != null) {
    parts.add('${chassis.widthMm!.toStringAsFixed(1)}w');
  }
  if (chassis.heightMm != null) {
    parts.add('${chassis.heightMm!.toStringAsFixed(1)}h');
  }
  if (chassis.depthMm != null) {
    parts.add('${chassis.depthMm!.toStringAsFixed(1)}d');
  }
  if (parts.isEmpty) {
    return '-';
  }
  return '${parts.join(' / ')} mm';
}

String _formatTemperature(double? value) {
  if (value == null) {
    return '-';
  }
  return _formatTemperatureValue(value);
}

String _formatWatts(double? value) {
  if (value == null) {
    return '-';
  }
  return '${value.toStringAsFixed(1)} W';
}

String _formatRpm(double? value) {
  if (value == null) {
    return '-';
  }
  return _formatRpmValue(value);
}

String _formatTrendClock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  final local = parsed.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}
