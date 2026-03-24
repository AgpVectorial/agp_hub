import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starea conexiunii BLE, inclusiv reconectare.
enum BleConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Informații expuse de managerul de reconectare.
@immutable
class BleConnectionState {
  final BleConnectionStatus status;
  final String? deviceId;
  final int retryCount;
  final String? lastError;

  const BleConnectionState({
    this.status = BleConnectionStatus.disconnected,
    this.deviceId,
    this.retryCount = 0,
    this.lastError,
  });

  BleConnectionState copyWith({
    BleConnectionStatus? status,
    String? deviceId,
    int? retryCount,
    String? lastError,
  }) =>
      BleConnectionState(
        status: status ?? this.status,
        deviceId: deviceId ?? this.deviceId,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
      );

  bool get isConnected => status == BleConnectionStatus.connected;
  bool get isReconnecting => status == BleConnectionStatus.reconnecting;
}

/// Manager de reconectare automată BLE cu backoff exponențial.
class BleReconnectManager extends StateNotifier<BleConnectionState> {
  BleReconnectManager() : super(const BleConnectionState());

  static const _maxRetries = 10;
  static const _baseDelaySeconds = 2;
  static const _maxDelaySeconds = 60;

  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _retryTimer;
  bool _autoReconnectEnabled = true;
  bool _disposed = false;

  /// Activează/dezactivează reconectarea automată.
  void setAutoReconnect(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Conectare la un device.
  Future<bool> connect(String deviceId) async {
    _retryTimer?.cancel();
    state = state.copyWith(
      status: BleConnectionStatus.connecting,
      deviceId: deviceId,
      retryCount: 0,
      lastError: null,
    );

    try {
      final device = BluetoothDevice.fromId(deviceId);

      // Ascultă schimbări de stare
      _connSub?.cancel();
      _connSub = device.connectionState.listen(_onConnectionStateChanged);

      final currentState = await device.connectionState.first;
      if (currentState == BluetoothConnectionState.connected) {
        state = state.copyWith(status: BleConnectionStatus.connected, retryCount: 0);
        return true;
      }

      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
      state = state.copyWith(status: BleConnectionStatus.connected, retryCount: 0);
      return true;
    } catch (e) {
      state = state.copyWith(
        status: BleConnectionStatus.disconnected,
        lastError: e.toString(),
      );
      if (_autoReconnectEnabled) {
        _scheduleRetry();
      }
      return false;
    }
  }

  /// Deconectare manuală (oprește reconectarea automată).
  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _connSub?.cancel();
    final id = state.deviceId;
    if (id != null) {
      try {
        final device = BluetoothDevice.fromId(id);
        await device.disconnect();
      } catch (_) {}
    }
    state = const BleConnectionState();
  }

  void _onConnectionStateChanged(BluetoothConnectionState bleState) {
    if (_disposed) return;
    if (bleState == BluetoothConnectionState.connected) {
      state = state.copyWith(
        status: BleConnectionStatus.connected,
        retryCount: 0,
        lastError: null,
      );
    } else if (bleState == BluetoothConnectionState.disconnected) {
      if (state.status == BleConnectionStatus.connected ||
          state.status == BleConnectionStatus.reconnecting) {
        state = state.copyWith(status: BleConnectionStatus.disconnected);
        if (_autoReconnectEnabled) {
          _scheduleRetry();
        }
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    final id = state.deviceId;
    if (id == null) return;
    if (state.retryCount >= _maxRetries) {
      state = state.copyWith(
        lastError: 'Max retries ($_maxRetries) reached',
      );
      return;
    }

    // Backoff exponențial: 2, 4, 8, 16 ... max 60s
    final delay = (_baseDelaySeconds * (1 << state.retryCount))
        .clamp(0, _maxDelaySeconds);

    state = state.copyWith(
      status: BleConnectionStatus.reconnecting,
      retryCount: state.retryCount + 1,
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delay), () async {
      if (_disposed || !_autoReconnectEnabled) return;
      try {
        final device = BluetoothDevice.fromId(id);
        await device.connect(timeout: const Duration(seconds: 8), autoConnect: false);
        // listener-ul va seta starea pe connected
      } catch (e) {
        if (_disposed) return;
        state = state.copyWith(
          status: BleConnectionStatus.disconnected,
          lastError: e.toString(),
        );
        if (_autoReconnectEnabled && state.retryCount < _maxRetries) {
          _scheduleRetry();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

/// Provider global pentru managerul de reconectare.
final bleReconnectProvider =
    StateNotifierProvider<BleReconnectManager, BleConnectionState>(
  (ref) => BleReconnectManager(),
);
