import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../models/vitals.dart';

abstract class SdkService {
  Future<void> startHeartRateNotifications(String deviceId);
  Future<void> stopHeartRateNotifications(String deviceId);
  Stream<VitalSample<int>> heartRateStream(String deviceId);

  Future<void> startSpO2Notifications(String deviceId);
  Future<void> stopSpO2Notifications(String deviceId);
  Stream<VitalSample<int>> spO2Stream(String deviceId);

  Future<void> startTemperatureNotifications(String deviceId);
  Future<void> stopTemperatureNotifications(String deviceId);
  Stream<VitalSample<double>> temperatureStream(String deviceId);

  Future<void> startStepsNotifications(String deviceId);
  Future<void> stopStepsNotifications(String deviceId);
  Stream<VitalSample<int>> stepsStream(String deviceId);

  Future<void> startBatteryNotifications(String deviceId);
  Future<void> stopBatteryNotifications(String deviceId);
  Stream<VitalSample<int>> batteryStream(String deviceId);

  Future<void> startRespirationNotifications(String deviceId);
  Future<void> stopRespirationNotifications(String deviceId);
  Stream<VitalSample<int>> respirationStream(String deviceId);

  Future<void> startHrvNotifications(String deviceId);
  Future<void> stopHrvNotifications(String deviceId);
  Stream<VitalSample<int>> hrvStream(String deviceId);

  Future<void> startBloodPressureNotifications(String deviceId);
  Future<void> stopBloodPressureNotifications(String deviceId);
  Stream<VitalSample<BloodPressure>> bloodPressureStream(String deviceId);
}

class GreenOrangeSdkService implements SdkService {
  static const MethodChannel _channel = MethodChannel('green_orange_scan');

  // Exemplu: scanare filtrată pentru device-uri Green Orange
  Future<List<Map<String, dynamic>>> scanDevices({
    String? uuid,
    String? mac,
  }) async {
    final devices = await _channel.invokeMethod('scanDevices', {
      'uuid': uuid,
      'mac': mac,
    });
    return List<Map<String, dynamic>>.from(devices);
  }

  // TODO: Implementare reală pentru notificări și stream-uri folosind platform channel
  @override
  Future<void> startHeartRateNotifications(String deviceId) async {}
  @override
  Future<void> stopHeartRateNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> heartRateStream(String deviceId) =>
      const Stream.empty();

  @override
  Future<void> startSpO2Notifications(String deviceId) async {}
  @override
  Future<void> stopSpO2Notifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> spO2Stream(String deviceId) => const Stream.empty();

  @override
  Future<void> startTemperatureNotifications(String deviceId) async {}
  @override
  Future<void> stopTemperatureNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<double>> temperatureStream(String deviceId) =>
      const Stream.empty();

  @override
  Future<void> startStepsNotifications(String deviceId) async {}
  @override
  Future<void> stopStepsNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> stepsStream(String deviceId) => const Stream.empty();

  @override
  Future<void> startBatteryNotifications(String deviceId) async {}
  @override
  Future<void> stopBatteryNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> batteryStream(String deviceId) =>
      const Stream.empty();

  @override
  Future<void> startRespirationNotifications(String deviceId) async {}
  @override
  Future<void> stopRespirationNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> respirationStream(String deviceId) =>
      const Stream.empty();

  @override
  Future<void> startHrvNotifications(String deviceId) async {}
  @override
  Future<void> stopHrvNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<int>> hrvStream(String deviceId) => const Stream.empty();

  @override
  Future<void> startBloodPressureNotifications(String deviceId) async {}
  @override
  Future<void> stopBloodPressureNotifications(String deviceId) async {}
  @override
  Stream<VitalSample<BloodPressure>> bloodPressureStream(String deviceId) =>
      const Stream.empty();
}

class MockSdkService implements SdkService {
  final _rnd = Random();
  final Map<String, Map<String, StreamController<dynamic>>> _controllers = {};
  final Set<String> _running = {}; // track-uiește tick-urile active

  StreamController<VitalSample<T>> _ctrl<T>(
    String id,
    String key,
    StreamController<VitalSample<T>> Function() create,
  ) {
    _controllers[id] ??= {};
    if (!_controllers[id]!.containsKey(key)) {
      _controllers[id]![key] = create();
    }
    return _controllers[id]![key] as StreamController<VitalSample<T>>;
  }

  String _runKey(String id, String key) => '$id::$key';

  void _tick<T>(
    String id,
    StreamController<VitalSample<T>> c,
    T Function() gen, [
    int ms = 1000,
  ]) async {
    if (c.isClosed) return;
    c.add(VitalSample(deviceId: id, value: gen(), ts: DateTime.now()));
    await Future.delayed(Duration(milliseconds: ms));
    if (!c.isClosed) _tick(id, c, gen, ms);
  }

  @override
  Future<void> startHeartRateNotifications(String id) async {
    final c = _ctrl<int>(
      id,
      'hr',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'hr')))
      _tick<int>(id, c, () => 60 + _rnd.nextInt(40));
  }

  @override
  Future<void> stopHeartRateNotifications(String id) async =>
      (_controllers[id]?['hr'])?.close();
  @override
  Stream<VitalSample<int>> heartRateStream(String id) => _ctrl<int>(
    id,
    'hr',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startSpO2Notifications(String id) async {
    final c = _ctrl<int>(
      id,
      'spo2',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'spo2')))
      _tick<int>(id, c, () => 95 + _rnd.nextInt(5));
  }

  @override
  Future<void> stopSpO2Notifications(String id) async =>
      (_controllers[id]?['spo2'])?.close();
  @override
  Stream<VitalSample<int>> spO2Stream(String id) => _ctrl<int>(
    id,
    'spo2',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startTemperatureNotifications(String id) async {
    final c = _ctrl<double>(
      id,
      'temp',
      () => StreamController<VitalSample<double>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'temp')))
      _tick<double>(id, c, () => 36.3 + _rnd.nextDouble() * 0.8);
  }

  @override
  Future<void> stopTemperatureNotifications(String id) async =>
      (_controllers[id]?['temp'])?.close();
  @override
  Stream<VitalSample<double>> temperatureStream(String id) => _ctrl<double>(
    id,
    'temp',
    () => StreamController<VitalSample<double>>.broadcast(),
  ).stream;

  @override
  Future<void> startStepsNotifications(String id) async {
    final c = _ctrl<int>(
      id,
      'steps',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'steps'))) {
      var steps = 1000;
      void loop() {
        if (c.isClosed) return;
        steps += _rnd.nextInt(5);
        c.add(VitalSample(deviceId: id, value: steps, ts: DateTime.now()));
        Future.delayed(const Duration(seconds: 2)).then((_) => loop());
      }

      loop();
    }
  }

  @override
  Future<void> stopStepsNotifications(String id) async =>
      (_controllers[id]?['steps'])?.close();
  @override
  Stream<VitalSample<int>> stepsStream(String id) => _ctrl<int>(
    id,
    'steps',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startBatteryNotifications(String id) async {
    final c = _ctrl<int>(
      id,
      'batt',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'batt'))) {
      var b = 80;
      void loop() {
        if (c.isClosed) return;
        b = b - _rnd.nextInt(2);
        if (b < 0) b = 0;
        c.add(VitalSample(deviceId: id, value: b, ts: DateTime.now()));
        Future.delayed(const Duration(seconds: 30)).then((_) => loop());
      }

      loop();
    }
  }

  @override
  Future<void> stopBatteryNotifications(String id) async =>
      (_controllers[id]?['batt'])?.close();
  @override
  Stream<VitalSample<int>> batteryStream(String id) => _ctrl<int>(
    id,
    'batt',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startRespirationNotifications(String id) async {
    final c = _ctrl<int>(
      id,
      'resp',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'resp')))
      _tick<int>(id, c, () => 12 + _rnd.nextInt(8));
  }

  @override
  Future<void> stopRespirationNotifications(String id) async =>
      (_controllers[id]?['resp'])?.close();
  @override
  Stream<VitalSample<int>> respirationStream(String id) => _ctrl<int>(
    id,
    'resp',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startHrvNotifications(String id) async {
    final c = _ctrl<int>(
      id,
      'hrv',
      () => StreamController<VitalSample<int>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'hrv')))
      _tick<int>(id, c, () => 20 + _rnd.nextInt(60));
  }

  @override
  Future<void> stopHrvNotifications(String id) async =>
      (_controllers[id]?['hrv'])?.close();
  @override
  Stream<VitalSample<int>> hrvStream(String id) => _ctrl<int>(
    id,
    'hrv',
    () => StreamController<VitalSample<int>>.broadcast(),
  ).stream;

  @override
  Future<void> startBloodPressureNotifications(String id) async {
    final c = _ctrl<BloodPressure>(
      id,
      'bp',
      () => StreamController<VitalSample<BloodPressure>>.broadcast(),
    );
    if (_running.add(_runKey(id, 'bp'))) {
      _tick<BloodPressure>(id, c, () {
        final s = 110 + _rnd.nextInt(25);
        final d = 70 + _rnd.nextInt(15);
        return BloodPressure(s, d);
      });
    }
  }

  @override
  Future<void> stopBloodPressureNotifications(String id) async =>
      (_controllers[id]?['bp'])?.close();
  @override
  Stream<VitalSample<BloodPressure>> bloodPressureStream(String id) =>
      _ctrl<BloodPressure>(
        id,
        'bp',
        () => StreamController<VitalSample<BloodPressure>>.broadcast(),
      ).stream;
}

final sdkProvider = Provider<SdkService>((ref) => MockSdkService());
