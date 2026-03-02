import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agp_wear_hub/core/i18n/locale.dart';

import '../../sdk/sdk_adapter.dart';
import '../../sdk/models.dart';
import '../../sdk/flutter_blue_adapter.dart';
import '../../storage/prefs.dart';
import '../../../theme.dart';
import '../device/device_details_page.dart';
import '../settings/settings_page.dart';
import '../diagnostics/diagnostics_page.dart';

enum AdapterKind { ble, sdk }

final adapterKindProvider = StateProvider<AdapterKind>((_) => AdapterKind.ble);

final sdkProvider = Provider<WearSdk>((ref) {
  final kind = ref.watch(adapterKindProvider);
  switch (kind) {
    case AdapterKind.sdk:
      return MethodChannelWearSdk();
    case AdapterKind.ble:
    default:
      return FlutterBlueWearSdk();
  }
});

final devicesProvider = StateProvider<List<WearDevice>>((ref) => []);
final selectedIdProvider = StateProvider<String?>((ref) => null);
final isScanningProvider = StateProvider<bool>((ref) => false);
final connectedProvider = StateProvider<bool>((ref) => false);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Future<void> _callEmergency() async {
    final t = T(ref.read(localeProvider));
    String? number = await Prefs.getString('user.emergency_phone');
    number = (number == null || number.trim().isEmpty) ? '112' : number.trim();

    final uri = Uri(scheme: 'tel', path: number);

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.cannotOpenDialer(number)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _restorePrefsAndReconnect();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _restorePrefsAndReconnect() async {
    final adapter = await Prefs.getAdapter();
    if (mounted) {
      ref.read(adapterKindProvider.notifier).state =
          (adapter == 'sdk') ? AdapterKind.sdk : AdapterKind.ble;
    }
    final last = await Prefs.getLastDevice();
    if (last != null && mounted) {
      ref.read(selectedIdProvider.notifier).state = last;
      try {
        final ok = await ref.read(sdkProvider).connect(last, autoReconnect: true);
        if (mounted) ref.read(connectedProvider.notifier).state = ok;
      } catch (_) {
        if (mounted) ref.read(connectedProvider.notifier).state = false;
      }
    }
  }

  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final selectedId = ref.watch(selectedIdProvider);
    final isScanning = ref.watch(isScanningProvider);
    final isConnected = ref.watch(connectedProvider);

    final t = T(ref.watch(localeProvider));
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          t.homeTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          _CompactIconButton(
            icon: Icons.info_outline_rounded,
            tooltip: t.diagnosticsTitle,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
            ),
          ),
          _CompactIconButton(
            icon: Icons.settings_rounded,
            tooltip: t.settingsTitle,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (isConnected || selectedId != null)
                _CompactStatusCard(
                  isConnected: isConnected,
                  selectedId: selectedId,
                  devices: devices,
                ),

              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: _CompactEmergencyButton(
                    onPressed: _callEmergency,
                    text: t.sosButton,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _CompactAdapterSelector(
                      onChanged: (k) async {
                        ref.read(adapterKindProvider.notifier).state = k;
                        await Prefs.saveAdapter(k == AdapterKind.sdk ? 'sdk' : 'ble');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompactScanButton(
                    scanning: isScanning,
                    scanText: t.startScan,
                    scanningText: t.scanning,
                    onScan: () async {
                      ref.read(isScanningProvider.notifier).state = true;
                      try {
                        final list = await ref.read(sdkProvider).scan();
                        ref.read(devicesProvider.notifier).state = list;
                        if (list.isEmpty) _snack(context, t.noDevices);
                      } catch (e) {
                        _snack(context, t.errorScan);
                      } finally {
                        ref.read(isScanningProvider.notifier).state = false;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: _CompactDeviceList(
                  devices: devices,
                  selectedId: selectedId,
                  noDevicesText: t.noDevices,
                  onDeviceSelected: (deviceId) async {
                    ref.read(selectedIdProvider.notifier).state = deviceId;
                    await Prefs.saveLastDevice(deviceId);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: selectedId != null
          ? _CompactConnectFAB(
              connectText: t.connect,
              onConnect: () async {
                final id = ref.read(selectedIdProvider);
                if (id == null) return;
                try {
                  final ok = await ref
                      .read(sdkProvider)
                      .connect(id, autoReconnect: true);
                  ref.read(connectedProvider.notifier).state = ok;
                  _snack(context, ok ? '${t.connectedTo} $id' : t.couldNotConnect);
                  await Prefs.saveLastDevice(id);

                  if (ok && context.mounted) {
                    final dev = ref.read(devicesProvider).firstWhere(
                          (e) => e.id == id,
                          orElse: () => WearDevice(id: id, name: t.device),
                        );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeviceDetailsPage(
                          deviceId: id,
                          initialDisplayName: dev.name,
                        ),
                      ),
                    );
                  }
                } catch (_) {
                  _snack(context, t.errorConnect);
                }
              },
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _CompactStatusCard extends StatelessWidget {
  const _CompactStatusCard({
    required this.isConnected,
    required this.selectedId,
    required this.devices,
  });

  final bool isConnected;
  final String? selectedId;
  final List<WearDevice> devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = T(ProviderScope.containerOf(context, listen: false).read(localeProvider));
    final deviceName = selectedId != null
        ? devices.firstWhere(
            (d) => d.id == selectedId,
            orElse: () => WearDevice(id: selectedId!, name: t.device),
          ).name
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [Colors.green.shade50, Colors.green.shade100]
              : [Colors.blue.shade50, Colors.blue.shade100],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isConnected ? Colors.green : Colors.blue).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isConnected ? t.connected : t.selected,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: (isConnected ? Colors.green : Colors.blue).shade800,
                  ),
                ),
                if (deviceName != null)
                  Text(
                    deviceName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (isConnected ? Colors.green : Colors.blue).shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isConnected)
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

class _CompactEmergencyButton extends StatelessWidget {
  const _CompactEmergencyButton({
    required this.onPressed,
    required this.text,
  });

  final VoidCallback onPressed;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF3B30), Color(0xFFFF1744)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emergency, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAdapterSelector extends ConsumerWidget {
  const _CompactAdapterSelector({this.onChanged});
  final void Function(AdapterKind)? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(adapterKindProvider);
    final theme = Theme.of(context);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AdapterOption(
              title: 'BLE',
              isSelected: kind == AdapterKind.ble,
              onTap: () {
                ref.read(adapterKindProvider.notifier).state = AdapterKind.ble;
                onChanged?.call(AdapterKind.ble);
              },
            ),
          ),
          Container(width: 1, height: 24, color: theme.colorScheme.outline.withOpacity(0.2)),
          Expanded(
            child: _AdapterOption(
              title: 'SDK',
              isSelected: kind == AdapterKind.sdk,
              onTap: () {
                ref.read(adapterKindProvider.notifier).state = AdapterKind.sdk;
                onChanged?.call(AdapterKind.sdk);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdapterOption extends StatelessWidget {
  const _AdapterOption({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactScanButton extends StatelessWidget {
  const _CompactScanButton({
    required this.scanning,
    required this.scanText,
    required this.scanningText,
    required this.onScan,
  });

  final bool scanning;
  final String scanText;
  final String scanningText;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 120,
      height: 48,
      child: FilledButton.icon(
        onPressed: scanning ? null : onScan,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: scanning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              )
            : const Icon(Icons.radar, size: 18),
        label: Text(
          scanning ? scanningText : scanText,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CompactDeviceList extends StatelessWidget {
  const _CompactDeviceList({
    required this.devices,
    required this.selectedId,
    required this.noDevicesText,
    required this.onDeviceSelected,
  });

  final List<WearDevice> devices;
  final String? selectedId;
  final String noDevicesText;
  final Function(String) onDeviceSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = T(ProviderScope.containerOf(context, listen: false).read(localeProvider));

    if (devices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              noDevicesText,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: devices.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: theme.colorScheme.outline.withOpacity(0.1),
        ),
        itemBuilder: (context, index) {
          final device = devices[index];
          final isSelected = selectedId == device.id;

          return Material(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onDeviceSelected(device.id),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.watch,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name.isEmpty ? t.device : device.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            device.id,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedScale(
                      scale: isSelected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompactConnectFAB extends StatelessWidget {
  const _CompactConnectFAB({
    required this.connectText,
    required this.onConnect,
  });

  final String connectText;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: MediaQuery.of(context).size.width - 32,
      height: 56,
      child: FloatingActionButton.extended(
        onPressed: onConnect,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 6,
        icon: const Icon(Icons.link, size: 20),
        label: Text(
          connectText,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
