import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme.dart';
import '../../sdk/sdk_provider.dart';
import '../../models/vitals.dart';
import 'widgets/vital_tile.dart';
import '../../i18n/locale.dart';

class DeviceDetailsPage extends ConsumerStatefulWidget {
  final String deviceId;
  final String? initialDisplayName;

  const DeviceDetailsPage({super.key, required this.deviceId, this.initialDisplayName});

  @override
  ConsumerState<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends ConsumerState<DeviceDetailsPage> {
  final Map<String, bool> _on = {
    'hr': false,
    'spo2': false,
    'temp': false,
    'steps': false,
    'resp': false,
    'hrv': false,
    'bp': false,
    'batt': false,
  };

  bool _loadedPrefs = false;

  String _key(String vital) => 'vitals.${widget.deviceId}.$vital.on';

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _on.updateAll((k, v) => p.getBool(_key(k)) ?? false);
      _loadedPrefs = true;
    });
  }

  Future<void> _savePref(String vital, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key(vital), value);
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ref.watch(sdkProvider);
    final lang = ref.watch(localeProvider);
    final t = T(lang);
    final theme = Theme.of(context);

    final title = widget.initialDisplayName == null
        ? '${t.device} ${widget.deviceId}'
        : '${widget.initialDisplayName!}';

    if (!_loadedPrefs) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(title),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (widget.initialDisplayName != null)
              Text(
                widget.deviceId,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          _ConnectionBanner(deviceId: widget.deviceId),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                  final aspectRatio = constraints.maxWidth > 600 ? 1.3 : 1.1;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: aspectRatio,
                    children: [
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.hr,
                        unit: t.bpm,
                        icon: Icons.favorite_rounded,
                        color: Colors.red,
                        start: sdk.startHeartRateNotifications,
                        stop: sdk.stopHeartRateNotifications,
                        stream: sdk.heartRateStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['hr'] ?? false,
                        onChanged: (v) {
                          _on['hr'] = v;
                          _savePref('hr', v);
                        },
                      ),
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.spo2,
                        unit: t.percent,
                        icon: Icons.bloodtype_rounded,
                        color: Colors.blue,
                        start: sdk.startSpO2Notifications,
                        stop: sdk.stopSpO2Notifications,
                        stream: sdk.spO2Stream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['spo2'] ?? false,
                        onChanged: (v) {
                          _on['spo2'] = v;
                          _savePref('spo2', v);
                        },
                      ),
                      _CompactVitalTile<double>(
                        deviceId: widget.deviceId,
                        title: t.temperature,
                        unit: t.degC,
                        icon: Icons.thermostat_rounded,
                        color: Colors.orange,
                        start: sdk.startTemperatureNotifications,
                        stop: sdk.stopTemperatureNotifications,
                        stream: sdk.temperatureStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => v.toStringAsFixed(1),
                        autoStart: _on['temp'] ?? false,
                        onChanged: (v) {
                          _on['temp'] = v;
                          _savePref('temp', v);
                        },
                      ),
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.steps,
                        unit: '',
                        icon: Icons.directions_walk_rounded,
                        color: Colors.green,
                        start: sdk.startStepsNotifications,
                        stop: sdk.stopStepsNotifications,
                        stream: sdk.stepsStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['steps'] ?? false,
                        onChanged: (v) {
                          _on['steps'] = v;
                          _savePref('steps', v);
                        },
                      ),
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.respiration,
                        unit: t.rpm,
                        icon: Icons.air_rounded,
                        color: Colors.teal,
                        start: sdk.startRespirationNotifications,
                        stop: sdk.stopRespirationNotifications,
                        stream: sdk.respirationStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['resp'] ?? false,
                        onChanged: (v) {
                          _on['resp'] = v;
                          _savePref('resp', v);
                        },
                      ),
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.hrv,
                        unit: t.ms,
                        icon: Icons.insights_rounded,
                        color: Colors.purple,
                        start: sdk.startHrvNotifications,
                        stop: sdk.stopHrvNotifications,
                        stream: sdk.hrvStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['hrv'] ?? false,
                        onChanged: (v) {
                          _on['hrv'] = v;
                          _savePref('hrv', v);
                        },
                      ),
                      _CompactVitalTile<BloodPressure>(
                        deviceId: widget.deviceId,
                        title: t.bloodPressure,
                        unit: t.mmHg,
                        icon: Icons.monitor_heart_rounded,
                        color: Colors.indigo,
                        start: sdk.startBloodPressureNotifications,
                        stop: sdk.stopBloodPressureNotifications,
                        stream: sdk.bloodPressureStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => v.toString(),
                        autoStart: _on['bp'] ?? false,
                        onChanged: (v) {
                          _on['bp'] = v;
                          _savePref('bp', v);
                        },
                      ),
                      _CompactVitalTile<int>(
                        deviceId: widget.deviceId,
                        title: t.battery,
                        unit: t.percent,
                        icon: Icons.battery_std_rounded,
                        color: Colors.amber,
                        start: sdk.startBatteryNotifications,
                        stop: sdk.stopBatteryNotifications,
                        stream: sdk.batteryStream(widget.deviceId).map((sample) => sample.value),
                        format: (v) => '$v',
                        autoStart: _on['batt'] ?? false,
                        onChanged: (v) {
                          _on['batt'] = v;
                          _savePref('batt', v);
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = T(ref.watch(localeProvider));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.bluetooth_connected_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.connectedActive,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                  ),
                ),
                Text(
                  t.realtimeMonitoring,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactVitalTile<T> extends StatefulWidget {
  const _CompactVitalTile({
    required this.deviceId,
    required this.title,
    required this.unit,
    required this.icon,
    required this.color,
    required this.start,
    required this.stop,
    required this.stream,
    required this.format,
    required this.autoStart,
    required this.onChanged,
  });

  final String deviceId;
  final String title;
  final String unit;
  final IconData icon;
  final Color color;
  final Function(String) start;
  final Function(String) stop;
  final Stream<T> stream;
  final String Function(T) format;
  final bool autoStart;
  final Function(bool) onChanged;

  @override
  State<_CompactVitalTile<T>> createState() => _CompactVitalTileState<T>();
}

class _CompactVitalTileState<T> extends State<_CompactVitalTile<T>> {
  T? _currentValue;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.autoStart;
    if (_isActive) {
      _startMonitoring();
    }
  }

  void _startMonitoring() {
    widget.start(widget.deviceId);
    widget.stream.listen((value) {
      if (mounted) {
        setState(() => _currentValue = value);
      }
    });
  }

  void _stopMonitoring() {
    widget.stop(widget.deviceId);
    setState(() => _currentValue = null);
  }

  void _toggle(bool value) {
    setState(() => _isActive = value);
    widget.onChanged(value);

    if (value) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: _isActive
            ? widget.color.withOpacity(0.1)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isActive
              ? widget.color.withOpacity(0.3)
              : theme.colorScheme.outline.withOpacity(0.2),
          width: _isActive ? 2 : 1,
        ),
        boxShadow: _isActive
            ? [
                BoxShadow(
                  color: widget.color.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _isActive ? widget.color : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 16,
                    color: _isActive ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const Spacer(),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _isActive,
                    onChanged: _toggle,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: widget.color,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              widget.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _isActive ? widget.color : theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            if (_currentValue != null) ...[
              Text(
                widget.format(_currentValue!),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _isActive ? widget.color : theme.colorScheme.onSurface,
                ),
              ),
              if (widget.unit.isNotEmpty)
                Text(
                  widget.unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isActive
                        ? widget.color.withOpacity(0.8)
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
            ] else ...[
              Text(
                _isActive ? '...' : '--',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
              if (widget.unit.isNotEmpty)
                Text(
                  widget.unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
