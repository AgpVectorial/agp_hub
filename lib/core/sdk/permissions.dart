import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Returnează true doar dacă permisiunile necesare BLE sunt ok
/// - Android 12+ (API 31+): cerem DOAR BLUETOOTH_SCAN & BLUETOOTH_CONNECT (NU cerem Location)
/// - Android <= 30: cerem Location (și verificăm ca Location Service să fie ON)
Future<bool> ensureBlePermissions(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;

  if (Platform.isIOS) {
    final bt = await Permission.bluetooth.request();
    if (!bt.isGranted) {
      _snack(context, 'Bluetooth permission required on iOS.');
      return false;
    }
    return true;
  }

  // ANDROID
  final deviceInfo = await DeviceInfoPlugin().androidInfo;
  final sdkInt = deviceInfo.version.sdkInt ?? 30;

  if (sdkInt >= 31) {
    // Android 12+ — nu mai cerem locație
    final req = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final missing = req.entries.where((e) => !e.value.isGranted).toList();
    if (missing.isNotEmpty) {
      _snack(context, 'Permisiunile BLE nu sunt acordate (Android 12+). Deschide Settings și acordă permisiunile.');
      await openAppSettings();
      // Re-check
      final re = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (re.values.any((s) => !s.isGranted)) {
        _snack(context, 'Permisiunile încă nu sunt acordate.');
        return false;
      }
    }
    // NU verificăm Location Service pe Android 12+
    return true;
  } else {
    // Android 11 și mai jos — trebuie Location + Location Service ON
    final req = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,     // permission_handler mapează corect în jos
      Permission.bluetoothConnect,  // idem
    ].request();

    final missing = req.entries.where((e) => !e.value.isGranted).toList();
    if (missing.isNotEmpty) {
      _snack(context, 'Permisiunile (Location/BLE) nu sunt acordate. Deschide Settings și acordă permisiunile.');
      await openAppSettings();
      final re = await [
        Permission.locationWhenInUse,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (re.values.any((s) => !s.isGranted)) {
        _snack(context, 'Permisiunile încă nu sunt acordate.');
        return false;
      }
    }

    final service = await Permission.location.serviceStatus;
    if (service != ServiceStatus.enabled) {
      _snack(context, 'Activează Location Service (GPS) în setările telefonului pentru scan BLE pe Android ≤ 11.');
      return false;
    }
    return true;
  }
}

/// Utilitar pentru debug: raportează statusul permisiunilor și al Location Service
Future<Map<String, String>> debugBlePermissionStatus() async {
  final Map<String, String> info = {};

  if (Platform.isAndroid) {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt ?? 30;
    info['android_sdk'] = '$sdkInt';

    final sScan = await Permission.bluetoothScan.status;
    final sConn = await Permission.bluetoothConnect.status;
    info['bluetoothScan'] = sScan.toString();
    info['bluetoothConnect'] = sConn.toString();

    if (sdkInt <= 30) {
      final sLoc = await Permission.locationWhenInUse.status;
      final svc = await Permission.location.serviceStatus;
      info['locationWhenInUse'] = sLoc.toString();
      info['locationService'] = svc.toString();
    } else {
      info['locationWhenInUse'] = 'not_required_on_api_31_plus';
      info['locationService'] = 'not_required_on_api_31_plus';
    }
  } else if (Platform.isIOS) {
    final sBt = await Permission.bluetooth.status;
    info['ios_bluetooth'] = sBt.toString();
  } else {
    info['platform'] = 'unsupported';
  }

  return info;
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
