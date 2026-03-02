import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'sdk_adapter.dart';
import 'uuids.dart';

class FlutterBlueWearSdk implements WearSdk {
  Future<void> _ensurePermissions() async {
    if (Platform.isIOS) {
      final bt = await Permission.bluetooth.request();
      if (!bt.isGranted) throw Exception('BLE permissions denied');
      return;
    }
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final sdkInt = info.version.sdkInt ?? 30;
      if (sdkInt >= 31) {
        final req = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
        if (req.values.any((s) => !s.isGranted)) throw Exception('BLE permissions denied');
      } else {
        final req = await [Permission.locationWhenInUse].request();
        if (req.values.any((s) => !s.isGranted)) throw Exception('BLE permissions denied');
        final svc = await Permission.location.serviceStatus;
        if (svc != ServiceStatus.enabled) throw Exception('Location service disabled');
      }
      return;
    }
    throw Exception('Unsupported platform');
  }

  final Map<String, StreamController<int>> _hrCtrls = {};
  final Map<String, StreamSubscription<List<int>>> _hrSubs = {};
  final Map<String, BluetoothCharacteristic> _hrChars = {};
  final Map<String, StreamSubscription<BluetoothConnectionState>> _connSubs = {};
  final Map<String, bool> _autoReconnect = {};

  BluetoothCharacteristic? _findChar(List<BluetoothService> services, {String? serviceLike, String? charLike}) {
    for (final s in services) {
      final su = s.uuid.str.toLowerCase();
      if (serviceLike != null && !su.contains(serviceLike)) continue;
      for (final c in s.characteristics) {
        final cu = c.uuid.str.toLowerCase();
        if (charLike == null || cu.contains(charLike)) return c;
      }
    }
    return null;
  }

  BluetoothCharacteristic? _findHrMeasurement(List<BluetoothService> services) {
    // Preferăm Service 0x180D + Char 0x2A37; dacă nu găsim, căutăm orice char care conține 2a37.
    final exact = _findChar(services, serviceLike: UuidsCfg.hrService, charLike: UuidsCfg.hrMeasurement);
    if (exact != null) return exact;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid.str.toLowerCase().contains(UuidsCfg.hrMeasurement)) return c;
      }
    }
    return null;
  }

  int _parseHr(List<int> v) {
    if (v.isEmpty) return 0;
    final flags = v[0];
    final hr8 = (flags & 0x01) == 0;
    if (hr8 && v.length > 1) return v[1];
    if (!hr8 && v.length > 2) return v[1] | (v[2] << 8);
    return 0;
  }

  int? _parseHrEnergyExpendedIfPresent(List<int> v) {
    if (v.isEmpty) return null;
    final flags = v[0];
    final energyPresent = (flags & 0x08) != 0; // bit 3
    if (!energyPresent) return null;
    // Structura când energy expended e prezent:
    // HR (1 sau 2 bytes) + EnergyExpended (2 bytes little-endian) + [RR intervals...]
    final hr8 = (flags & 0x01) == 0;
    int offset = 1 + (hr8 ? 1 : 2);
    if (v.length >= offset + 2) {
      final energyKJ = v[offset] | (v[offset + 1] << 8); // unitatea e kiloJouli conform spec
      // Estimăm calorii (kcal) ~ kJ * 0.239006
      final kcal = (energyKJ * 0.239006).round();
      return kcal;
    }
    return null;
  }

  int? _parseSteps(List<int> v) {
    if (v.isEmpty) return null;
    // 0x2ACD e de obicei uint32 LE; ne adaptăm și pentru 16-bit dacă e cazul.
    if (v.length >= 4) {
      return v[0] | (v[1] << 8) | (v[2] << 16) | (v[3] << 24);
    }
    if (v.length >= 2) {
      return v[0] | (v[1] << 8);
    }
    return null;
  }

  int? _parseSpo2(List<int> v) {
    if (v.isEmpty) return null;
    // În practică, multe device-uri pun SpO2 ca procent întreg (0..100) în primul byte.
    final x = v.first;
    if (x >= 50 && x <= 100) return x;
    return null;
  }

  @override
  Future<List<WearDevice>> scan() async {
    await _ensurePermissions();
    final Map<String, WearDevice> found = {};
    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final d = r.device;
        final advName = r.advertisementData.advName;
        final name = d.platformName.isNotEmpty ? d.platformName : (advName.isNotEmpty ? advName : 'Unknown');
        found[d.remoteId.str] = WearDevice(id: d.remoteId.str, name: name, rssi: r.rssi);
      }
    });
    await Future<void>.delayed(const Duration(seconds: 5));
    await FlutterBluePlus.stopScan();
    await sub.cancel();
    return found.values.toList();
  }

  @override
  Future<bool> connect(String deviceId, {bool autoReconnect = true}) async {
    await _ensurePermissions();
    final device = BluetoothDevice.fromId(deviceId);
    _autoReconnect[deviceId] = autoReconnect;
    try {
      final st = await device.connectionState.first;
      if (st == BluetoothConnectionState.connected) return true;
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
      _connSubs[deviceId]?.cancel();
      _connSubs[deviceId] = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected && (_autoReconnect[deviceId] ?? false)) {
          for (final delay in [1, 2, 4]) {
            try {
              await Future.delayed(Duration(seconds: delay));
              await device.connect(timeout: const Duration(seconds: 8), autoConnect: false);
              break;
            } catch (_) {}
          }
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WearMetrics> readMetrics(String deviceId) async {
    await _ensurePermissions();
    final device = BluetoothDevice.fromId(deviceId);
    final state = await device.connectionState.first;
    if (state != BluetoothConnectionState.connected) {
      throw Exception('Device not connected');
    }

    int heartRate = 0;
    int steps = 0;
    int battery = 0;
    int? spo2;
    int? calories;

    try {
      final services = await device.discoverServices();

      // Battery 0x180F / 0x2A19
      for (final s in services) {
        final su = s.uuid.str.toLowerCase();
        if (su.contains(UuidsCfg.batteryService)) {
          for (final c in s.characteristics) {
            if (c.uuid.str.toLowerCase().contains(UuidsCfg.batteryLevel)) {
              final val = await c.read();
              if (val.isNotEmpty) battery = val.first.clamp(0, 100);
            }
          }
        }
      }

      // Heart Rate
      final hrC = _findHrMeasurement(services);
      if (hrC != null) {
        try {
          final v = await hrC.read();
          heartRate = _parseHr(v);
          calories ??= _parseHrEnergyExpendedIfPresent(v);
        } catch (_) {}
      }

      // Steps (0x2ACD, oriunde ar fi)
      for (final s in services) {
        for (final c in s.characteristics) {
          final cu = c.uuid.str.toLowerCase();
          if (cu.contains(UuidsCfg.stepsChar)) {
            try {
              final v = await c.read();
              final st = _parseSteps(v);
              if (st != null) steps = st;
            } catch (_) {}
          }
        }
      }

      // SpO2 – 0x1822 service (preferat) sau direct 0x2A5F/0x2A60
      final spo2Pref = _findChar(services, serviceLike: UuidsCfg.spo2Service);
      if (spo2Pref != null) {
        try {
          final v = await spo2Pref.read();
          spo2 = _parseSpo2(v) ?? spo2;
        } catch (_) {}
      }
      // fallback pe caracteristicile cunoscute
      for (final s in services) {
        for (final c in s.characteristics) {
          final cu = c.uuid.str.toLowerCase();
          if (cu.contains(UuidsCfg.spo2Continuous) || cu.contains(UuidsCfg.spo2Spot)) {
            try {
              final v = await c.read();
              spo2 = _parseSpo2(v) ?? spo2;
            } catch (_) {}
          }
        }
      }

      // Calories – UUID-uri custom (dacă știm ceva de la OEM)
      if (calories == null && UuidsCfg.caloriesCustomChars.isNotEmpty) {
        for (final s in services) {
          for (final c in s.characteristics) {
            final cu = c.uuid.str.toLowerCase();
            if (UuidsCfg.caloriesCustomChars.any((id) => cu.contains(id))) {
              try {
                final v = await c.read();
                // adesea uint16/uint32 LE
                int kc = 0;
                if (v.length >= 4) {
                  kc = v[0] | (v[1] << 8) | (v[2] << 16) | (v[3] << 24);
                } else if (v.length >= 2) {
                  kc = v[0] | (v[1] << 8);
                } else if (v.isNotEmpty) {
                  kc = v[0];
                }
                calories = kc;
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    return WearMetrics(
      heartRate: heartRate,
      steps: steps,
      battery: battery,
      spo2: spo2,
      calories: calories,
    );
  }

  @override
  Future<void> startHeartRateNotifications(String deviceId) async {
    await _ensurePermissions();
    final device = BluetoothDevice.fromId(deviceId);
    final state = await device.connectionState.first;
    if (state != BluetoothConnectionState.connected) {
      throw Exception('Device not connected');
    }
    final services = await device.discoverServices();
    final hrC = _findHrMeasurement(services);
    if (hrC == null) throw Exception('HR char not found');

    await hrC.setNotifyValue(true);
    _hrChars[deviceId] = hrC;
    _hrCtrls.putIfAbsent(deviceId, () => StreamController<int>.broadcast());
    _hrSubs[deviceId]?.cancel();
    _hrSubs[deviceId] = hrC.onValueReceived.listen((v) {
      final bpm = _parseHr(v);
      _hrCtrls[deviceId]!.add(bpm);
    });
  }

  @override
  Future<void> stopHeartRateNotifications(String deviceId) async {
    try {
      await _hrSubs[deviceId]?.cancel();
      _hrSubs.remove(deviceId);
      final ch = _hrChars[deviceId];
      if (ch != null) await ch.setNotifyValue(false);
      _hrChars.remove(deviceId);
    } catch (_) {}
    await _hrCtrls[deviceId]?.close();
    _hrCtrls.remove(deviceId);
  }

  @override
  Stream<int> heartRateStream(String deviceId) {
    _hrCtrls.putIfAbsent(deviceId, () => StreamController<int>.broadcast());
    return _hrCtrls[deviceId]!.stream;
  }

  @override
  Stream<ConnectionUpdate> connectionUpdates(String deviceId) async* {
    final device = BluetoothDevice.fromId(deviceId);
    yield* device.connectionState.map((s) => ConnectionUpdate(deviceId, s == BluetoothConnectionState.connected));
  }
}
