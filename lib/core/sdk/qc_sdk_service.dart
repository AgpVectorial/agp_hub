import 'dart:async';
import 'package:flutter/services.dart';
import '../models/vitals.dart';
import 'sdk_provider.dart';

/// Implementare reală a SdkService care comunică cu QC Wireless SDK
/// prin MethodChannel/EventChannel.
///
/// Folosește aceleași canale ca MethodChannelWearSdk ('agp_sdk') dar
/// expune interfața SdkService (cu stream-uri VitalSample) utilizată
/// de device_details_page și restul UI-ului.
class QcSdkService implements SdkService {
  // Singleton – mereu aceeași instanță, stream controllers partajate
  static final QcSdkService _instance = QcSdkService._();
  factory QcSdkService() => _instance;
  QcSdkService._();

  static const MethodChannel _ch = MethodChannel('agp_sdk');

  final Map<String, Map<String, StreamController<dynamic>>> _controllers = {};

  StreamController<VitalSample<T>> _ctrl<T>(String id, String key) {
    _controllers[id] ??= {};
    if (!_controllers[id]!.containsKey(key) ||
        (_controllers[id]![key] as StreamController).isClosed) {
      _controllers[id]![key] = StreamController<VitalSample<T>>.broadcast();
    }
    return _controllers[id]![key] as StreamController<VitalSample<T>>;
  }

  // ── Heart Rate ──

  @override
  Future<void> startHeartRateNotifications(String deviceId) async {
    await _ch.invokeMethod('startHeartRateNotifications', {'id': deviceId});
  }

  @override
  Future<void> stopHeartRateNotifications(String deviceId) async {
    await _ch.invokeMethod('stopHeartRateNotifications', {'id': deviceId});
  }

  @override
  Stream<VitalSample<int>> heartRateStream(String deviceId) =>
      _ctrl<int>(deviceId, 'hr').stream;

  // ── SpO2 ──

  @override
  Future<void> startSpO2Notifications(String deviceId) async {
    await _ch.invokeMethod('startSpO2', {'id': deviceId});
  }

  @override
  Future<void> stopSpO2Notifications(String deviceId) async {
    await _ch.invokeMethod('stopSpO2', {'id': deviceId});
  }

  @override
  Stream<VitalSample<int>> spO2Stream(String deviceId) =>
      _ctrl<int>(deviceId, 'spo2').stream;

  // ── Temperature ──

  @override
  Future<void> startTemperatureNotifications(String deviceId) async {
    await _ch.invokeMethod('startTemperature', {'id': deviceId});
  }

  @override
  Future<void> stopTemperatureNotifications(String deviceId) async {
    await _ch.invokeMethod('stopTemperature', {'id': deviceId});
  }

  @override
  Stream<VitalSample<double>> temperatureStream(String deviceId) =>
      _ctrl<double>(deviceId, 'temp').stream;

  // ── Steps (periodic poll via CMD_GET_STEP_TODAY) ──

  Timer? _stepsTimer;

  @override
  Future<void> startStepsNotifications(String deviceId) async {
    _stepsTimer?.cancel();
    _stepsTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _pollStepsOnce(deviceId);
    });
  }

  Future<void> _pollStepsOnce(String deviceId) async {
    try {
      final res = await _ch.invokeMethod('readMetrics', {'id': deviceId});
      final map = Map<String, dynamic>.from(res as Map);
      final steps = (map['steps'] as num?)?.toInt() ?? 0;
      if (steps > 0) {
        _ctrl<int>(deviceId, 'steps').add(
          VitalSample(deviceId: deviceId, value: steps, ts: DateTime.now()),
        );
      }
    } catch (_) {}
  }

  @override
  Future<void> stopStepsNotifications(String deviceId) async {
    _stepsTimer?.cancel();
    _stepsTimer = null;
  }

  @override
  Stream<VitalSample<int>> stepsStream(String deviceId) =>
      _ctrl<int>(deviceId, 'steps').stream;

  // ── Battery (periodic poll) ──

  Timer? _battTimer;

  @override
  Future<void> startBatteryNotifications(String deviceId) async {
    _battTimer?.cancel();
    // Poll battery every 60s — first poll after 5s to let connection stabilize
    _battTimer = Timer(const Duration(seconds: 5), () async {
      await _pollBatteryOnce(deviceId);
      _battTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        await _pollBatteryOnce(deviceId);
      });
    });
  }

  Future<void> _pollBatteryOnce(String deviceId) async {
    try {
      final batt = await _ch.invokeMethod('getBattery');
      if (batt is int && batt > 0) {
        _ctrl<int>(
          deviceId,
          'batt',
        ).add(VitalSample(deviceId: deviceId, value: batt, ts: DateTime.now()));
      }
    } catch (_) {}
  }

  @override
  Future<void> stopBatteryNotifications(String deviceId) async {
    _battTimer?.cancel();
    _battTimer = null;
  }

  @override
  Stream<VitalSample<int>> batteryStream(String deviceId) =>
      _ctrl<int>(deviceId, 'batt').stream;

  // ── HRV ──

  @override
  Future<void> startHrvNotifications(String deviceId) async {
    await _ch.invokeMethod('startHrv', {'id': deviceId});
  }

  @override
  Future<void> stopHrvNotifications(String deviceId) async {
    await _ch.invokeMethod('stopHrv', {'id': deviceId});
  }

  @override
  Stream<VitalSample<int>> hrvStream(String deviceId) =>
      _ctrl<int>(deviceId, 'hrv').stream;

  // ── Blood Pressure ──

  @override
  Future<void> startBloodPressureNotifications(String deviceId) async {
    await _ch.invokeMethod('startBloodPressure', {'id': deviceId});
  }

  @override
  Future<void> stopBloodPressureNotifications(String deviceId) async {
    await _ch.invokeMethod('stopBloodPressure', {'id': deviceId});
  }

  @override
  Stream<VitalSample<BloodPressure>> bloodPressureStream(String deviceId) =>
      _ctrl<BloodPressure>(deviceId, 'bp').stream;

  // ── Action features ──

  /// Sets the bracelet's automatic HR monitoring interval.
  Future<bool> setHeartRateInterval({
    required bool enable,
    required int interval,
  }) async {
    try {
      final res = await _ch.invokeMethod('setHeartRateInterval', {
        'enable': enable,
        'interval': interval,
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      // Stop all active polling & rotation
      _battTimer?.cancel();
      _battTimer = null;
      _stepsTimer?.cancel();
      _stepsTimer = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      if (_rotationDeviceId != null) {
        await stopVitalRotation(_rotationDeviceId!);
      }
      // Reset polled value tracking
      _lastPolledHr = 0;
      _lastPolledSpo2 = 0;
      _lastPolledSbp = 0;
      _lastPolledDbp = 0;
      _lastPolledTemp = 0;
      _lastPolledHrv = 0;
      _lastPolledStress = 0;
      await _ch.invokeMethod('disconnect');
    } catch (_) {}
  }

  @override
  Future<bool> findDevice() async {
    try {
      final res = await _ch.invokeMethod('findDevice');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> enterCamera() async {
    try {
      final res = await _ch.invokeMethod('enterCamera');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> exitCamera() async {
    try {
      final res = await _ch.invokeMethod('exitCamera');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setCallReminder(bool enable) async {
    try {
      final res = await _ch.invokeMethod('setCallReminder', {'enable': enable});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isNotificationAccessEnabled() async {
    try {
      final res = await _ch.invokeMethod('isNotificationAccessEnabled');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openNotificationAccessSettings() async {
    try {
      await _ch.invokeMethod('openNotificationAccessSettings');
    } catch (_) {}
  }

  @override
  Future<bool> setSedentaryReminder({
    required bool enable,
    int interval = 60,
    int startHour = 9,
    int startMinute = 0,
    int endHour = 18,
    int endMinute = 0,
  }) async {
    try {
      final res = await _ch.invokeMethod('setSedentaryReminder', {
        'enable': enable,
        'interval': interval,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setDnd({
    required bool enable,
    int startHour = 22,
    int startMinute = 0,
    int endHour = 7,
    int endMinute = 0,
  }) async {
    try {
      final res = await _ch.invokeMethod('setDnd', {
        'enable': enable,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setAlarm({
    required int index,
    required bool enable,
    required int hour,
    required int minute,
    int weekMask = 0x7F,
  }) async {
    try {
      final res = await _ch.invokeMethod('setAlarm', {
        'index': index,
        'enable': enable,
        'hour': hour,
        'minute': minute,
        'weekMask': weekMask,
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // ── Stress ──

  @override
  Stream<VitalSample<int>> stressStream(String deviceId) =>
      _ctrl<int>(deviceId, 'stress').stream;

  // ── Vital Rotation Scheduler ──
  // The bracelet only supports ONE manual mode at a time.
  // This scheduler cycles through enabled vitals sequentially.

  Timer? _rotationTimer;
  Timer? _pollTimer;
  bool _rotating = false;
  int _rotationIndex = 0;
  String? _rotationDeviceId;
  List<String> _rotationVitals = [];
  Map<String, int> _rotationIntervals = {};
  // Track last polled values to avoid duplicate events
  int _lastPolledHr = 0;
  int _lastPolledSpo2 = 0;
  int _lastPolledSbp = 0;
  int _lastPolledDbp = 0;
  int _lastPolledTemp = 0;
  int _lastPolledHrv = 0;
  int _lastPolledStress = 0;
  final StreamController<String> _activeVitalCtrl =
      StreamController<String>.broadcast();

  @override
  Stream<String> get activeVitalStream => _activeVitalCtrl.stream;

  @override
  bool get isRotating => _rotating;

  @override
  String? get rotationDeviceId => _rotationDeviceId;

  @override
  Future<void> startVitalRotation(
    String deviceId,
    List<String> vitals,
    Map<String, int> intervals,
  ) async {
    await stopVitalRotation(deviceId);
    if (vitals.isEmpty) return;

    _rotationDeviceId = deviceId;
    _rotationVitals = List.from(vitals);
    _rotationIntervals = Map.from(intervals);
    _rotating = true;
    _rotationIndex = 0;
    print('[VitalRotation] Starting continuous measurement for deviceId=$deviceId vitals=$vitals');

    // Reset polled values so fresh data is picked up
    _lastPolledHr = 0;
    _lastPolledSpo2 = 0;
    _lastPolledSbp = 0;
    _lastPolledDbp = 0;
    _lastPolledTemp = 0;
    _lastPolledHrv = 0;
    _lastPolledStress = 0;

    // Start continuous oneClick measurement on the bracelet
    try {
      await _ch.invokeMethod('startContinuousMeasurement');
      print('[VitalRotation] Continuous measurement started');
    } catch (e) {
      print('[VitalRotation] startContinuousMeasurement error: $e');
    }

    // Start polling for values every 2 seconds
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollLastVitalValues(deviceId);
    });

    // Also poll steps periodically
    if (vitals.contains('steps')) {
      _stepsTimer?.cancel();
      _stepsTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _pollStepsOnce(deviceId);
      });
    }

    _activeVitalCtrl.add('continuous');
  }

  /// Polls native cached vital values and injects any new data into streams.
  Future<void> _pollLastVitalValues(String deviceId) async {
    try {
      final res = await _ch.invokeMethod('getLastVitalValues');
      if (res is! Map) return;
      final map = Map<String, dynamic>.from(res);
      print('[VitalRotation] poll: hr=${map['hr']} spo2=${map['spo2']} sbp=${map['sbp']} temp=${map['temp']} hrv=${map['hrv']} stress=${map['stress']}');

      final hr = (map['hr'] as num?)?.toInt() ?? 0;
      if (hr > 0 && hr != _lastPolledHr) {
        _lastPolledHr = hr;
        _ctrl<int>(deviceId, 'hr').add(
          VitalSample(deviceId: deviceId, value: hr, ts: DateTime.now()),
        );
      }

      final spo2 = (map['spo2'] as num?)?.toInt() ?? 0;
      if (spo2 > 0) {
        _lastPolledSpo2 = spo2;
        _ctrl<int>(deviceId, 'spo2').add(
          VitalSample(deviceId: deviceId, value: spo2, ts: DateTime.now()),
        );
      }

      final sbp = (map['sbp'] as num?)?.toInt() ?? 0;
      final dbp = (map['dbp'] as num?)?.toInt() ?? 0;
      if (sbp > 0 && dbp > 0 && (sbp != _lastPolledSbp || dbp != _lastPolledDbp)) {
        _lastPolledSbp = sbp;
        _lastPolledDbp = dbp;
        _ctrl<BloodPressure>(deviceId, 'bp').add(
          VitalSample(
            deviceId: deviceId,
            value: BloodPressure(sbp, dbp),
            ts: DateTime.now(),
          ),
        );
      }

      final tempRaw = (map['temp'] as num?)?.toInt() ?? 0;
      if (tempRaw > 0) {
        _lastPolledTemp = tempRaw;
        final temp = tempRaw / 10.0;
        _ctrl<double>(deviceId, 'temp').add(
          VitalSample(deviceId: deviceId, value: temp, ts: DateTime.now()),
        );
      }

      final hrv = (map['hrv'] as num?)?.toInt() ?? 0;
      if (hrv > 0 && hrv != _lastPolledHrv) {
        _lastPolledHrv = hrv;
        _ctrl<int>(deviceId, 'hrv').add(
          VitalSample(deviceId: deviceId, value: hrv, ts: DateTime.now()),
        );
      }

      final stress = (map['stress'] as num?)?.toInt() ?? 0;
      if (stress > 0 && stress != _lastPolledStress) {
        _lastPolledStress = stress;
        _ctrl<int>(deviceId, 'stress').add(
          VitalSample(deviceId: deviceId, value: stress, ts: DateTime.now()),
        );
      }
    } catch (e) {
      print('[VitalRotation] pollLastVitalValues error: $e');
    }
  }

  @override
  Future<void> stopVitalRotation(String deviceId) async {
    _rotating = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _stepsTimer?.cancel();
    _stepsTimer = null;
    // Stop continuous measurement on the bracelet
    try {
      await _ch.invokeMethod('stopContinuousMeasurement');
      print('[VitalRotation] Continuous measurement stopped');
    } catch (e) {
      print('[VitalRotation] stopContinuousMeasurement error: $e');
    }
    _activeVitalCtrl.add('');
  }

  @override
  Future<Map<String, dynamic>?> syncSleep() async {
    try {
      final res = await _ch
          .invokeMethod('syncSleep')
          .timeout(const Duration(seconds: 25));
      if (res is Map) {
        final data = Map<String, dynamic>.from(res);
        // If old protocol returned zeros but we have segments, calculate from segments
        final total = (data['totalSleep'] as num?)?.toInt() ?? 0;
        if (total == 0 && data['segments'] is List) {
          final segments = data['segments'] as List;
          int deep = 0, light = 0, rem = 0, awake = 0;
          for (final seg in segments) {
            if (seg is Map) {
              final duration = (seg['duration'] as num?)?.toInt() ?? 0;
              final type = (seg['type'] as num?)?.toInt() ?? 0;
              switch (type) {
                case 1:
                  deep += duration;
                  break;
                case 2:
                  light += duration;
                  break;
                case 3:
                  rem += duration;
                  break;
                case 4:
                  awake += duration;
                  break;
              }
            }
          }
          final totalCalc = deep + light + rem;
          if (totalCalc > 0) {
            data['totalSleep'] = totalCalc;
            data['deepSleep'] = deep;
            data['lightSleep'] = light;
            data['remSleep'] = rem;
            data['awake'] = awake;
          }
        }
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
