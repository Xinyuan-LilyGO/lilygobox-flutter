/*
 * @Description: 在主页内容区自动发现设备，展示连接反馈、重试和连接帮助。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 09:52:14
 * @LastEditTime: 2026-10-06 14:21:20
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../app/shell/state/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../data/lan_discovery.dart';
import '../../domain/discovery_service.dart';
import '../../state/discovery_controller.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';
import '../widgets/device_connection_help.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key, this.discoveryService});

  final DeviceDiscoveryService? discoveryService;

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  late final DiscoveryController _discovery;
  late final DeviceDiscoveryService _service;
  late final DeviceManagerProvider? _deviceManager;
  String? _lastConnectedDeviceId;

  @override
  void initState() {
    super.initState();
    _service =
        widget.discoveryService ??
        context.read<LanConnection?>() ??
        const UnavailableDeviceDiscoveryService();
    _deviceManager = context.read<DeviceManagerProvider?>();
    _discovery = _createDiscovery();
    _discovery.addListener(_connectionChanged);
    _deviceManager?.addListener(_discovery.refreshDevices);
    if (_service is LanConnection) {
      // 已连接时仍允许进入添加页查找其他设备，不能被旧会话的心跳抢走页面。
      _lastConnectedDeviceId = _service.connected ? _service.device?.id : null;
      _service.addListener(_sessionChanged);
    }
    unawaited(_discovery.search());
    // ready 可能早于本页初始化；恢复本轮添加结果，不能再次搜索后显示空列表。
    if (_service is LanConnection &&
        _service.connected &&
        context.read<AppNavigationProvider?>()?.addedDeviceId ==
            _service.device?.id &&
        _service.device != null) {
      _discovery.reportConnectionEstablished(_service.device!);
    }
  }

  @override
  void dispose() {
    _discovery.removeListener(_connectionChanged);
    _deviceManager?.removeListener(_discovery.refreshDevices);
    if (_service is LanConnection) {
      _service.removeListener(_sessionChanged);
    }
    _discovery.dispose();
    super.dispose();
  }

  void _goBack() {
    context.read<AppShellProvider>().updateSelectedIndex(0);
    context.read<AppNavigationProvider>().goHome();
  }

  DiscoveryController _createDiscovery() => DiscoveryController(
    service: _service,
    // 使用持久化设备 ID 排除已添加项，离线或名称/IP 变化不影响判断。
    includeDevice: (device) =>
        !(_deviceManager?.addedDevices.contains(device.id) ?? false),
    connectionTimeout: _service is LanConnection
        ? const Duration(seconds: 65)
        : const Duration(seconds: 20),
  );

  void _sessionChanged() {
    final session = _service as LanConnection;
    final connectedDevice = session.connected ? session.device : null;
    final previousId = _lastConnectedDeviceId;
    _lastConnectedDeviceId = connectedDevice?.id;
    if (connectedDevice != null && connectedDevice.id != previousId) {
      _discovery.reportConnectionEstablished(connectedDevice);
    } else if (_discovery.phase == DiscoveryPhase.connected &&
        connectedDevice?.id != _discovery.selectedDevice?.id) {
      _discovery.reportConnectionLost();
    }
  }

  // 成功后立即保存资料，但保留完成页面，等待用户点击返回主页。
  void _connectionChanged() {
    if (_discovery.phase != DiscoveryPhase.connected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _discovery.phase != DiscoveryPhase.connected) return;
      final navigation = context.read<AppNavigationProvider>();
      if (navigation.contentPage != AppPage.addDevice) return;
      final device = _discovery.selectedDevice;
      if (device == null) return;
      final manager = context.read<DeviceManagerProvider>();
      if (device is LanDevice) {
        if (_service is LanConnection &&
            (!_service.connected || _service.device?.id != device.id)) {
          return;
        }
        manager.addLanDevice(device);
      } else {
        manager.addDevice(device.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            context.read<AppNavigationProvider>().currentPage ==
                AppPage.addDevice) {
          _goBack();
        }
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _goBack},
        child: Focus(
          autofocus: true,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
            child: ColoredBox(
              color: theme.secondary,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inset = constraints.maxWidth < 520 ? 16.0 : 28.0;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            AppTooltip(
                              message: l10n.back,
                              verticalOffset: 16,
                              child: Semantics(
                                label: l10n.back,
                                button: true,
                                child: TitleBarIconButton(
                                  theme: theme,
                                  backgroundColor: theme.secondary,
                                  isFocused: true,
                                  icon: Symbols.arrow_back_rounded,
                                  size: 28,
                                  iconSize: 18,
                                  onPressed: _goBack,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.addDevice,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorPrimary,
                                ),
                              ),
                            ),
                            const DeviceHelpMenu(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, body) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: body.maxHeight,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    inset,
                                    24,
                                    inset,
                                    // 补偿顶部标题高度，使主体相对整个内容页居中。
                                    24 + constraints.maxHeight - body.maxHeight,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 400,
                                      ),
                                      child: ListenableBuilder(
                                        listenable: Listenable.merge([
                                          _discovery,
                                          if (_service is LanConnection)
                                            _service,
                                        ]),
                                        builder: (context, child) =>
                                            _buildContent(theme),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppTheme theme) {
    final l10n = context.l10n;
    final phase = _discovery.phase;
    final selected = _discovery.selectedDevice;
    final session = _service is LanConnection ? _service : null;
    final identityChanged =
        session?.device?.id == selected?.id && session?.identityChanged == true;
    final awaitingApproval =
        session?.device?.id == selected?.id &&
        session?.phase == LanConnectionPhase.awaitingApproval;
    final (title, description) = switch (phase) {
      DiscoveryPhase.empty => (
        l10n.discoveryEmpty,
        l10n.discoveryEmptyDescription,
      ),
      DiscoveryPhase.unavailable => (
        l10n.discoveryUnavailable,
        l10n.discoveryUnavailableDescription,
      ),
      DiscoveryPhase.failed => (
        l10n.discoveryFailed,
        l10n.discoveryFailedDescription,
      ),
      DiscoveryPhase.connecting => (
        l10n.deviceConnecting,
        _discovery.selectedDevice!.name,
      ),
      DiscoveryPhase.connected => (
        l10n.deviceConnectionComplete,
        _discovery.selectedDevice!.name,
      ),
      DiscoveryPhase.connectionFailed => (
        l10n.deviceConnectionFailed,
        identityChanged
            ? l10n.lanIdentityChanged
            : l10n.deviceConnectionFailedDescription,
      ),
      _ => (l10n.connectYourDevice, l10n.discoveryDescription),
    };
    final showDevices =
        _discovery.devices.isNotEmpty &&
        (phase == DiscoveryPhase.searching || phase == DiscoveryPhase.found);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (phase == DiscoveryPhase.connected) ...[
          Icon(
            Symbols.check_circle_rounded,
            fill: 1,
            size: 56,
            color: theme.baseTertiary,
          ),
          const SizedBox(height: 18),
        ],
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: theme.textColorTertiary,
          ),
        ),
        if (selected is LanDevice &&
            (phase == DiscoveryPhase.connecting ||
                phase == DiscoveryPhase.connected ||
                phase == DiscoveryPhase.connectionFailed)) ...[
          const SizedBox(height: 4),
          Text(
            'MAC ${selected.macAddress}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.textColorTertiary),
          ),
        ],
        if (phase == DiscoveryPhase.connected && selected is LanDevice) ...[
          const SizedBox(height: 4),
          Text(
            '${l10n.lanModel}: ${selected.model}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.lanAddress}: ${selected.address}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.textColorTertiary),
          ),
        ],
        const SizedBox(height: 28),
        if (phase == DiscoveryPhase.connected)
          _action(theme, l10n.backToHome, _goBack),
        if (showDevices) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.discoveredDevices,
              style: TextStyle(
                fontSize: 13,
                color: theme.textColorSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final device in _discovery.devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _deviceRow(theme, device),
            ),
          const SizedBox(height: 16),
        ],
        if (_discovery.isSearching || phase == DiscoveryPhase.connecting)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
                  color: theme.baseTertiary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  phase == DiscoveryPhase.connecting
                      ? awaitingApproval
                            ? l10n.lanConfirmOnDevice
                            : l10n.lanConnectingDescription
                      : l10n.searchingDevices,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textColorTertiary,
                  ),
                ),
              ),
            ],
          ),
        if (phase == DiscoveryPhase.empty ||
            phase == DiscoveryPhase.failed ||
            phase == DiscoveryPhase.found)
          _action(
            theme,
            l10n.searchAgain,
            () => unawaited(_discovery.search()),
          ),
        if (phase == DiscoveryPhase.connectionFailed)
          _action(
            theme,
            identityChanged ? l10n.lanRepair : l10n.retryConnection,
            () async {
              if (identityChanged &&
                  !await confirmDeviceRepair(context, session!, selected!.id)) {
                return;
              }
              if (mounted) unawaited(_discovery.connect(selected!));
            },
          ),
        if (phase == DiscoveryPhase.connecting) ...[
          const SizedBox(height: 16),
          _action(
            theme,
            l10n.cancelConnection,
            () => unawaited(_discovery.cancelConnection()),
            primary: false,
          ),
        ],
        if (phase == DiscoveryPhase.failed ||
            phase == DiscoveryPhase.connectionFailed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.baseTertiary),
              onPressed: () => showDeviceConnectionHelp(context),
              child: Text(l10n.deviceConnectionTroubleshooting),
            ),
          ),
      ],
    );
  }

  Widget _deviceRow(AppTheme theme, DiscoveredDevice device) {
    return Semantics(
      button: true,
      child: MenuItemSurface(
        theme: theme,
        backgroundColor: theme.primary,
        // 列表位于二级背景上，悬停仍需与列表外的灰色区域区分。
        hoverColor: theme.secondaryTextHoverColor,
        borderRadius: BorderRadius.circular(10),
        onPressed: () => unawaited(_discovery.connect(device)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Symbols.wifi, size: 26, color: theme.baseTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device is LanDevice
                          ? 'MAC ${device.macAddress}'
                          : context.l10n.tapToConnect,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Symbols.chevron_right_rounded,
                size: 20,
                color: theme.baseTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
    AppTheme theme,
    String label,
    VoidCallback onPressed, {
    bool primary = true,
  }) => AppActionButton(
    theme: theme,
    label: label,
    onPressed: onPressed,
    primary: primary,
  );
}
