import 'dart:async';
import 'package:flutter/services.dart';

import 'models.dart';

abstract class WearSdk {
  Future<List<WearDevice>> scan();
  Future<bool> connect(String deviceId, {bool autoReconnect = true});
  Future<WearMetrics> readMetrics(String deviceId);

  Future<void> startHeartRateNotifications(String deviceId);
  Future<void> stopHeartRateNotifications(String deviceId);
  Stream<int> heartRateStream(String deviceId);

  Stream<ConnectionUpdate> connectionUpdates(String deviceId);
}

class ConnectionUpdate {
  final String deviceId;
  final bool connected;
  ConnectionUpdate(this.deviceId, this.connected);
}

class MethodChannelWearSdk implements WearSdk {
  static const MethodChannel _ch = MethodChannel('agp_sdk');
  static const EventChannel _hrEvent = EventChannel('agp_sdk/hr_stream');

  String? _activeHrDeviceId;
  Stream<int>? _sharedHrStream;
  StreamSubscription<dynamic>? _sharedSub;
  final Map<String, StreamController<int>> _perDeviceCtrls = {};

  @override
  Future<List<WearDevice>> scan() async {
    final res = await _ch.invokeMethod('scan');
    final List list = (res is List) ? res : [];
    return list.map((e) => WearDevice.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<bool> connect(String deviceId, {bool autoReconnect = true}) async {
    final ok = await _ch.invokeMethod('connect', {'id': deviceId});
    return ok == true;
  }

  @override
  Future<WearMetrics> readMetrics(String deviceId) async {
    final res = await _ch.invokeMethod('readMetrics', {'id': deviceId});
    final map = Map<String, dynamic>.from(res as Map);
    // asigurăm cheile opționale
    map.putIfAbsent('spo2', () => null);
    map.putIfAbsent('calories', () => null);
    return WearMetrics.fromMap(map);
  }

  @override
  Future<void> startHeartRateNotifications(String deviceId) async {
    _activeHrDeviceId = deviceId;
    await _ensureHrStream();
    await _ch.invokeMethod('startHeartRateNotifications', {'id': deviceId});
  }

  @override
  Future<void> stopHeartRateNotifications(String deviceId) async {
    if (_activeHrDeviceId == deviceId) _activeHrDeviceId = null;
    await _ch.invokeMethod('stopHeartRateNotifications', {'id': deviceId});
  }

  @override
  Stream<int> heartRateStream(String deviceId) {
    _perDeviceCtrls.putIfAbsent(deviceId, () => StreamController<int>.broadcast());
    _ensureHrStream();
    return _perDeviceCtrls[deviceId]!.stream;
  }

  @override
  Stream<ConnectionUpdate> connectionUpdates(String deviceId) async* {
    // momentan nu avem event channel pentru connection; BLE adapter îl acoperă
    yield* const Stream<ConnectionUpdate>.empty();
  }

  Future<void> _ensureHrStream() async {
    if (_sharedHrStream != null) return;
    _sharedHrStream = _hrEvent.receiveBroadcastStream().map<int>((dynamic e) {
      if (e is int) return e;
      if (e is num) return e.toInt();
      return 0;
    });
    _sharedSub = _sharedHrStream!.listen((bpm) {
      final id = _activeHrDeviceId;
      if (id == null) return;
      _perDeviceCtrls[id]?.add(bpm);
    });
  }

  void dispose() {
    _sharedSub?.cancel();
    for (final c in _perDeviceCtrls.values) {
      c.close();
    }
    _perDeviceCtrls.clear();
    _activeHrDeviceId = null;
  }
}
