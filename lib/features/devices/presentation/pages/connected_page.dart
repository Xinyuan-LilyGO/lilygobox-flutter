/*
 * @Description: 设备详情页，采用可变卡片布局展示设备、连接、电池和控制信息。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 15:14:56
 * @LastEditTime: 2026-10-13 12:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/card_shadow.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/tilt_card.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../data/lan_discovery.dart';
import '../../domain/device_control.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';
import '../widgets/battery_capacity_dialog.dart';
import '../widgets/device_battery_colors.dart';
import '../widgets/device_battery_estimate.dart';
import '../widgets/device_dashboard.dart';
import '../widgets/device_name_dialog.dart';
import '../widgets/device_page_frame.dart';
import '../widgets/device_status_badge.dart';

enum _DeviceDetailView { control, information, battery, connection }

class ConnectedDevicePage extends StatefulWidget {
  const ConnectedDevicePage({
    super.key,
    required this.deviceId,
    this.nestedView,
    this.pageTitle,
    this.active = true,
  });

  final String deviceId;
  final ValueNotifier<bool>? nestedView;
  final ValueNotifier<DevicePageTitle?>? pageTitle;
  final bool active;

  @override
  State<ConnectedDevicePage> createState() => _ConnectedDevicePageState();
}

class _ConnectedDevicePageState extends State<ConnectedDevicePage>
    with SingleTickerProviderStateMixin {
  _DeviceDetailView _view = _DeviceDetailView.control;
  final List<_DeviceDetailView> _viewHistory = [];
  bool _rotationConfirmationOpen = false;
  late final AnimationController _viewTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    widget.nestedView?.addListener(_handleOuterBack);
  }

  @override
  void didUpdateWidget(covariant ConnectedDevicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      // 从主页重新进入时返回概览，仅清空导航历史，保留控制值。
      _view = _DeviceDetailView.control;
      _viewHistory.clear();
      _viewTransition.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        widget.nestedView?.value = false;
        widget.pageTitle?.value = null;
      });
    }
    if (oldWidget.nestedView != widget.nestedView) {
      oldWidget.nestedView?.removeListener(_handleOuterBack);
      widget.nestedView?.addListener(_handleOuterBack);
    }
  }

  @override
  void dispose() {
    widget.nestedView?.removeListener(_handleOuterBack);
    _viewTransition.dispose();
    super.dispose();
  }

  void _animateViewChange() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _viewTransition.value = 1;
    } else {
      _viewTransition.forward(from: 0);
    }
  }

  void _handleOuterBack() {
    if (widget.nestedView?.value == false &&
        _view != _DeviceDetailView.control &&
        mounted) {
      // 按实际进入路径逐层返回，连接详情先回到设备信息。
      final previous = _viewHistory.isEmpty
          ? _DeviceDetailView.control
          : _viewHistory.removeLast();
      setState(() => _view = previous);
      widget.pageTitle?.value = previous == _DeviceDetailView.control
          ? null
          : _pageTitle;
      widget.nestedView?.value = previous != _DeviceDetailView.control;
      _animateViewChange();
    }
  }

  void _openView(_DeviceDetailView view) {
    if (_view == view) return;
    _viewHistory.add(_view);
    setState(() => _view = view);
    widget.pageTitle?.value = _pageTitle;
    _animateViewChange();
    widget.nestedView?.value = view != _DeviceDetailView.control;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final session = context.watch<LanConnection>();
    final saved = context.watch<DeviceManagerProvider>().lanDevice(
      widget.deviceId,
    );
    final l10n = context.l10n;
    final selected = session.device?.id == widget.deviceId;
    final online = selected && session.connected;
    final busy = selected && session.busy;
    final identityChanged = selected && session.identityChanged;
    final device = selected ? session.device : saved;
    final status = online
        ? l10n.homeDeviceOnline
        : busy
        ? l10n.homeDeviceConnecting
        : l10n.homeDeviceOffline;
    final description = identityChanged
        ? l10n.lanIdentityChanged
        : online
        ? l10n.lanConnectedDescription
        : busy
        ? session.phase == LanConnectionPhase.awaitingApproval
              ? l10n.lanConfirmOnDevice
              : l10n.lanConnectingDescription
        : l10n.lanReconnectDescription;
    final action = _connectionAction(
      theme: theme,
      l10n: l10n,
      session: session,
      device: device,
      online: online,
      busy: busy,
      identityChanged: identityChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return SingleChildScrollView(
          key: PageStorageKey('${widget.deviceId}-${_view.name}'),
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 32,
            18,
            compact ? 18 : 32,
            30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1110),
              child: FadeTransition(
                opacity: _viewTransition,
                child: _view == _DeviceDetailView.control
                    ? _controlView(
                        theme: theme,
                        l10n: l10n,
                        device: device,
                        status: status,
                        description: description,
                        online: online,
                        compact: compact,
                        connecting: busy,
                      )
                    : _subpage(
                        theme: theme,
                        title: _viewTitle(l10n),
                        child: switch (_view) {
                          _DeviceDetailView.information => _informationView(
                            theme,
                            l10n,
                            device,
                            online,
                            session,
                            () => _openView(_DeviceDetailView.connection),
                          ),
                          _DeviceDetailView.battery => _batteryView(
                            theme,
                            online,
                          ),
                          _DeviceDetailView.connection => _connectionView(
                            theme,
                            l10n,
                            device,
                            online,
                            busy,
                            action,
                            status,
                            description,
                          ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  DevicePageTitle? get _pageTitle => switch (_view) {
    _DeviceDetailView.information => DevicePageTitle.information,
    _DeviceDetailView.battery => DevicePageTitle.battery,
    _DeviceDetailView.connection => DevicePageTitle.connection,
    _DeviceDetailView.control => null,
  };

  String _viewTitle(AppLocalizations l10n) => switch (_view) {
    _DeviceDetailView.information => l10n.deviceInfoTab,
    _DeviceDetailView.battery => l10n.deviceBatteryPageTitle,
    _DeviceDetailView.connection => l10n.deviceConnectionTab,
    _ => l10n.deviceDetails,
  };

  Widget _controlView({
    required AppTheme theme,
    required AppLocalizations l10n,
    required LanDevice? device,
    required String status,
    required String description,
    required bool online,
    required bool compact,
    required bool connecting,
  }) => DeviceDashboard(
    theme: theme,
    name: device?.name ?? widget.deviceId,
    model: device?.modelLabel ?? '—',
    status: status,
    online: online,
    description: description,
    connecting: connecting,
    controlState: _controlState,
    controlsReady: context.read<LanConnection>().controlsReadyFor(
      widget.deviceId,
    ),
    brightness:
        (_controlState?.number(DeviceControlField.brightness) ?? 90) / 100,
    volume: (_controlState?.number(DeviceControlField.volume) ?? 90) / 100,
    vibration:
        (_controlState?.number(DeviceControlField.hapticStrength) ?? 90) / 100,
    screenOn: _controlState?.enabled(DeviceControlField.screenEnabled) ?? true,
    soundOn: _controlState?.enabled(DeviceControlField.soundEnabled) ?? true,
    vibrationOn:
        _controlState?.enabled(DeviceControlField.hapticEnabled) ?? true,
    rotation: _controlState?.number(DeviceControlField.rotation) ?? 0,
    lockTimeoutSeconds:
        _controlState?.values[DeviceControlField.lockTimeoutSeconds] as int? ??
        300,
    onLockTimeout: (value) =>
        _setControl(DeviceControlField.lockTimeoutSeconds, value),
    onBrightness: (value) => _setControl(
      DeviceControlField.brightness,
      (value * 100).round().clamp(10, 100),
    ),
    onVolume: (value) =>
        _setControl(DeviceControlField.volume, (value * 100).round()),
    onVibration: (value) =>
        _setControl(DeviceControlField.hapticStrength, (value * 100).round()),
    onScreen: (value) => _setControl(DeviceControlField.screenEnabled, value),
    onSound: (value) => _setControl(DeviceControlField.soundEnabled, value),
    onVibrationEnabled: (value) =>
        _setControl(DeviceControlField.hapticEnabled, value),
    onRotation: _confirmRotation,
    onInformation: () => _openView(_DeviceDetailView.information),
    onBattery: () => _openView(_DeviceDetailView.battery),
  );
  Widget _subpage({
    required AppTheme theme,
    required String title,
    required Widget child,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) => Text(
          title,
          style: TextStyle(
            // 主次标题共用左边界；与设备概览保持相同的主标题层级。
            fontSize:
                constraints.maxWidth < 620 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21
                ? 24
                : 28,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: theme.textColorPrimary,
          ),
        ),
      ),
      const SizedBox(height: 7),
      Text(
        switch (_view) {
          _DeviceDetailView.information => context.l10n.deviceDashboardIdentity,
          _DeviceDetailView.battery => context.l10n.deviceDashboardViewBattery,
          _DeviceDetailView.connection => context.l10n.connectionInformation,
          _DeviceDetailView.control => context.l10n.deviceDashboardSubtitle,
        },
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: theme.textColorTertiary,
        ),
      ),
      const SizedBox(height: 20),
      child,
    ],
  );

  Widget _informationView(
    AppTheme theme,
    AppLocalizations l10n,
    LanDevice? device,
    bool online,
    LanConnection session,
    VoidCallback onConnection,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final identity = _card(
        theme,
        enabled: online,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailText(l10n.homeDeviceCardLabel, theme, size: 16, bold: true),
            // 中央区域预留设备图片；未提供图片时使用统一的灰色占位图标。
            SizedBox(
              height: 144,
              child: Center(
                child: Icon(
                  Symbols.blur_on,
                  size: 80,
                  color: theme.textColorTertiary,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  device?.name ?? widget.deviceId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _detailText(
                  device?.modelLabel ?? '—',
                  theme,
                  size: 13,
                  muted: true,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Symbols.wifi, size: 20, color: theme.basePrimary),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Wi-Fi',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.basePrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final details = _card(
        theme,
        enabled: online,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailText(
              l10n.deviceInformationTitle,
              theme,
              size: 15,
              bold: true,
            ),
            const SizedBox(height: 12),
            for (final item in [
              (l10n.deviceNameLabel, device?.name ?? widget.deviceId),
              (l10n.lanModel, device?.model ?? '—'),
              (
                l10n.lanModelVersion,
                device?.modelVersion.isNotEmpty == true
                    ? device!.modelVersion
                    : '—',
              ),
              (
                l10n.lanFirmware,
                online && session.firmware.isNotEmpty ? session.firmware : '—',
              ),
              (l10n.lanMacAddress, device?.macAddress ?? '—'),
              (l10n.lanUptime, online ? '${session.uptimeMs ~/ 1000} s' : '—'),
            ])
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.materialColors.outlineVariant,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _informationRow(
                    theme,
                    item.$1,
                    item.$2,
                    onEdit:
                        item.$1 == l10n.deviceNameLabel &&
                            online &&
                            session.controlsReadyFor(widget.deviceId) &&
                            (_controlState?.supports(
                                  DeviceControlField.deviceName,
                                ) ??
                                false)
                        ? () => _editDeviceName(theme)
                        : null,
                    stacked:
                        (narrow
                                ? constraints.maxWidth - 40
                                : (constraints.maxWidth - 18) * .69 - 40) <
                            320 ||
                        MediaQuery.textScalerOf(context).scale(13) > 18,
                  ),
                ),
              ),
          ],
        ),
      );
      final top = narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 18), details],
            )
          // 宽窗口保持卡片底部齐平，左侧空余高度分配到内容组之间。
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 31, child: identity),
                  const SizedBox(width: 18),
                  Expanded(flex: 69, child: details),
                ],
              ),
            );
      final connection = _card(
        theme,
        onTap: onConnection,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.secondary.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Symbols.link,
                size: 21,
                fill: 1,
                color: theme.textColorPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.deviceInformationConnection,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    online
                        ? '${l10n.homeDeviceOnline} · Wi-Fi'
                        : l10n.homeDeviceOffline,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              l10n.deviceInformationView,
              style: TextStyle(fontSize: 12, color: theme.textColorTertiary),
            ),
            const SizedBox(width: 8),
            Icon(
              Symbols.chevron_right,
              size: 19,
              color: theme.textColorTertiary,
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [top, const SizedBox(height: 18), connection],
      );
    },
  );

  /// 信息卡片使用外层已知宽度选择排版，避免等高布局查询 LayoutBuilder 的固有尺寸。
  Widget _informationRow(
    AppTheme theme,
    String label,
    String value, {
    required bool stacked,
    VoidCallback? onEdit,
  }) {
    final caption = _detailText(label, theme, muted: true);
    final detail = onEdit == null
        ? SelectableText(
            value,
            contextMenuBuilder: AppTextSelectionMenu.build,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.textColorPrimary,
            ),
          )
        : Align(
            alignment: stacked
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Transform.translate(
              offset: Offset(stacked ? -10 : 0, 0),
              child: Semantics(
                button: true,
                label: label,
                child: MenuItemSurface(
                  key: const ValueKey('device-name-edit'),
                  theme: theme,
                  backgroundColor: theme.primary,
                  hoverColor: theme.hoverColorForBackground(theme.primary),
                  onPressed: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: onEdit == null ? 9 : 5),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption, const SizedBox(height: 6), detail],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: caption),
                const SizedBox(width: 18),
                Expanded(child: detail),
              ],
            ),
    );
  }

  DeviceControlState? get _controlState =>
      context.read<LanConnection>().controlStateFor(widget.deviceId);

  /// 旋转会关闭硬件上的当前页面；确认前不发送控制命令或改变选中角度。
  Future<void> _confirmRotation(int angle) async {
    final connection = context.read<LanConnection>();
    if (_rotationConfirmationOpen ||
        !connection.connected ||
        connection.device?.id != widget.deviceId ||
        _controlState?.number(DeviceControlField.rotation) == angle) {
      return;
    }
    _rotationConfirmationOpen = true;
    try {
      final confirmed = await showAppConfirmation(
        context: context,
        theme: context.read<ThemeProvider>().themeData,
        actionKey: 'device-rotation',
        title: context.l10n.deviceRotationConfirmTitle,
        description: context.l10n.deviceRotationConfirmDescription,
        confirmLabel: context.l10n.deviceRotationConfirmAction,
      );
      if (!confirmed ||
          !mounted ||
          !widget.active ||
          !connection.connected ||
          connection.device?.id != widget.deviceId) {
        return;
      }
      _setControl(DeviceControlField.rotation, angle);
    } finally {
      _rotationConfirmationOpen = false;
    }
  }

  void _setControl(DeviceControlField field, Object value) {
    final connection = context.read<LanConnection>();
    if (connection.device?.id == widget.deviceId) {
      connection.setControl(field, value);
    }
  }

  Widget _batteryView(AppTheme theme, bool online) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final summary = _card(
        theme,
        enabled: online,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_controlState?.battery?.charging == true) ...[
                  Icon(
                    Symbols.bolt,
                    fill: 1,
                    size: 22,
                    color: theme.textColorPrimary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _detailText(
                    _controlState?.battery == null
                        ? context.l10n.deviceBatteryUnknown
                        : _controlState!.battery!.full &&
                              _controlState!.battery!.charging
                        ? context.l10n.deviceBatteryFull
                        : _controlState!.battery!.charging
                        ? context.l10n.deviceBatteryChargingState
                        : context.l10n.deviceBatteryPowerState,
                    theme,
                    size: 15,
                    bold: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: deviceBatteryHeadingGap),
            DeviceBatteryEstimate(
              battery: _controlState?.battery,
              color: theme.textColorPrimary,
            ),
            const SizedBox(height: deviceBatteryGraphicGap),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 276),
                child: DeviceBatteryGraphic(
                  theme: theme,
                  progress: (_controlState?.battery?.percent ?? 0) / 100,
                  height: 116,
                  colors: DeviceBatteryColors(theme),
                ),
              ),
            ),
            const SizedBox(height: deviceBatteryGraphicGap),
            _detailText(
              !online
                  ? context.l10n.deviceBatteryOffline
                  : _controlState?.battery == null
                  ? context.l10n.deviceBatteryNoData
                  : _controlState!.battery!.full &&
                        _controlState!.battery!.charging
                  ? context.l10n.deviceBatteryFull
                  : _controlState!.battery!.charging
                  ? context.l10n.deviceBatteryChargerConnected
                  : context.l10n.deviceBatteryNotCharging,
              theme,
              size: 12,
              muted: true,
            ),
          ],
        ),
      );
      final details = _card(
        theme,
        enabled: online,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailText(
              context.l10n.deviceBatteryPageTitle,
              theme,
              size: 15,
              bold: true,
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final voltage = _batteryMetric(
                  theme,
                  Symbols.bolt,
                  context.l10n.deviceBatteryVoltage,
                  _controlState?.battery == null
                      ? '—'
                      : (_controlState!.battery!.voltageMv / 1000)
                            .toStringAsFixed(2),
                  'V',
                );
                final temperature = _batteryMetric(
                  theme,
                  Symbols.thermometer,
                  context.l10n.deviceBatteryTemperature,
                  _controlState?.battery?.temperatureC?.toStringAsFixed(1) ??
                      '—',
                  '°C',
                );
                if ((narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 18) * .63) <
                    356) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      voltage,
                      const SizedBox(height: 14),
                      temperature,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: voltage),
                    const SizedBox(width: 14),
                    Expanded(child: temperature),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryChargingStatus,
              _controlState?.battery == null
                  ? '—'
                  : _controlState!.battery!.full
                  ? context.l10n.deviceBatteryFull
                  : _controlState!.battery!.charging
                  ? context.l10n.deviceBatteryChargingState
                  : context.l10n.deviceBatteryNotCharging,
            ),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryCurrent,
              _controlState?.battery == null
                  ? '—'
                  : '${_controlState!.battery!.currentMa} mA',
            ),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryLevel,
              _controlState?.battery == null
                  ? '—'
                  : '${_controlState!.battery!.percent}%',
            ),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryHealth,
              switch (_controlState?.battery?.healthPercent) {
                final health? => '$health%',
                null => '—',
              },
            ),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryTimeToFull,
              _batteryDuration(
                context,
                _controlState?.battery?.timeToFullMinutes,
              ),
            ),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryTimeToEmpty,
              _batteryDuration(
                context,
                _controlState?.battery?.timeToEmptyMinutes,
              ),
            ),
            const SizedBox(height: 4),
            _batteryStatusRow(
              theme,
              context.l10n.deviceBatteryCapacity,
              switch (_controlState?.values[DeviceControlField
                  .batteryCapacityMah]) {
                final int capacity => '$capacity mAh',
                _ => '—',
              },
              editable: true,
              onTap:
                  online &&
                      context.read<LanConnection>().controlsReadyFor(
                        widget.deviceId,
                      ) &&
                      (_controlState?.supports(
                            DeviceControlField.batteryCapacityMah,
                          ) ??
                          false)
                  ? () => _editBatteryCapacity(theme)
                  : null,
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow) ...[
            summary,
            const SizedBox(height: 18),
            details,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 37, child: summary),
                const SizedBox(width: 18),
                Expanded(flex: 63, child: details),
              ],
            ),
        ],
      );
    },
  );

  String _batteryDuration(BuildContext context, int? minutes) => minutes == null
      ? '—'
      : context.l10n.deviceBatteryDuration(minutes ~/ 60, minutes % 60);

  Future<void> _editDeviceName(AppTheme theme) async {
    final connection = context.read<LanConnection>();
    if (!connection.controlsReadyFor(widget.deviceId) ||
        !(_controlState?.supports(DeviceControlField.deviceName) ?? false)) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => DeviceNameDialog(
        theme: theme,
        name: connection.device?.name ?? widget.deviceId,
        errorCode: () => connection.lastControlError,
        onSave: (value) => connection.device?.id == widget.deviceId
            ? connection.saveControl(DeviceControlField.deviceName, value)
            : Future.value(false),
      ),
    );
  }

  Future<void> _editBatteryCapacity(AppTheme theme) async {
    final state = _controlState;
    if (state == null ||
        !state.supports(DeviceControlField.batteryCapacityMah)) {
      return;
    }
    final connection = context.read<LanConnection>();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BatteryCapacityDialog(
        theme: theme,
        capacity: state.number(DeviceControlField.batteryCapacityMah),
        minimum: state.batteryCapacityMinimumMah,
        maximum: state.batteryCapacityMaximumMah,
        onSave: (value) => connection.device?.id == widget.deviceId
            ? connection.saveControl(
                DeviceControlField.batteryCapacityMah,
                value,
              )
            : Future.value(false),
      ),
    );
  }

  Widget _batteryMetric(
    AppTheme theme,
    IconData icon,
    String label,
    String value,
    String unit,
  ) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: theme.secondary,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, fill: 1, size: 18, color: theme.basePrimary),
            const SizedBox(width: 8),
            Flexible(child: _detailText(label, theme, size: 12, muted: true)),
          ],
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: value,
            children: [
              TextSpan(
                text: '  $unit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: theme.textColorTertiary,
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: theme.textColorPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _batteryStatusRow(
    AppTheme theme,
    String label,
    String value, {
    bool editable = false,
    VoidCallback? onTap,
  }) {
    final text = Text(
      value,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: theme.textColorPrimary,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.materialColors.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: editable ? 8 : 14),
        child: Row(
          children: [
            Expanded(child: _detailText(label, theme, muted: true)),
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: editable
                    // 背景向文字外延伸，数值仍与其他信息行共用列起点。
                    ? Transform.translate(
                        offset: const Offset(-10, 0),
                        child: Semantics(
                          button: true,
                          label: context.l10n.deviceBatteryCapacityEdit,
                          child: MenuItemSurface(
                            key: const ValueKey('device-battery-capacity-edit'),
                            theme: theme,
                            backgroundColor: theme.primary,
                            hoverColor: theme.hoverColorForBackground(
                              theme.primary,
                            ),
                            onPressed: onTap,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: text,
                            ),
                          ),
                        ),
                      )
                    : text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 按连接状态展示链路示意、连接信息与管理操作，复用现有连接按钮。
  Widget _connectionView(
    AppTheme theme,
    AppLocalizations l10n,
    LanDevice? device,
    bool online,
    bool busy,
    Widget action,
    String status,
    String description,
  ) => LayoutBuilder(
    // 在外层确定布局，等高卡片内部不使用 LayoutBuilder。
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailText(
            l10n.deviceConnectionStatusTitle,
            theme,
            size: 15,
            bold: true,
          ),
          const SizedBox(height: 16),
          _detailText(
            online ? l10n.connectionReady : status,
            theme,
            size: 24,
            bold: true,
          ),
          const SizedBox(height: 14),
          _detailText(
            description,
            theme,
            size: 12,
            color: theme.textColorTertiary,
          ),
        ],
      );
      final diagram = Row(
        children: [
          Expanded(
            child: _connectionEndpoint(
              theme,
              Symbols.laptop,
              l10n.connectionThisComputer,
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Symbols.wifi, size: 17, color: theme.basePrimary),
                    const SizedBox(width: 6),
                    _detailText(
                      'Wi-Fi',
                      theme,
                      size: 12,
                      color: theme.textColorTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 离线链路在中央断开，连接中用同步符号，避免显示成已连通。
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.materialColors.outlineVariant,
                      ),
                    ),
                    if (!online) ...[
                      const SizedBox(width: 8),
                      Icon(
                        busy ? Symbols.sync : Symbols.link_off,
                        size: 20,
                        color: theme.textColorTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Divider(
                          color: theme.materialColors.outlineVariant,
                        ),
                      ),
                    ] else
                      Icon(
                        Symbols.chevron_right,
                        size: 16,
                        color: theme.basePrimary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _connectionEndpoint(
              theme,
              Symbols.desktop_windows,
              device?.name ?? widget.deviceId,
            ),
          ),
        ],
      );
      final hero = _card(
        theme,
        padding: const EdgeInsets.all(20),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 20), diagram],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 35, child: heading),
                    const SizedBox(width: 24),
                    Expanded(flex: 65, child: diagram),
                  ],
                ),
              ),
      );
      final information = _card(
        theme,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailText(
              l10n.connectionInformation,
              theme,
              size: 15,
              bold: true,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailText(
                        l10n.connectionStatus,
                        theme,
                        size: 11,
                        muted: true,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Symbols.circle,
                            fill: 1,
                            size: 6,
                            color: deviceStatusColor(
                              theme,
                              connected: online,
                              connecting: busy,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: _detailText(status, theme, size: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailText(
                        l10n.connectionMethod,
                        theme,
                        size: 11,
                        muted: true,
                      ),
                      const SizedBox(height: 10),
                      _detailText('Wi-Fi', theme),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final item in [
              (l10n.lanAddress, device?.address ?? '—'),
              (l10n.lanMacAddress, device?.macAddress ?? '—'),
            ])
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.materialColors.outlineVariant,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _informationRow(
                    theme,
                    item.$1,
                    item.$2,
                    stacked:
                        (narrow
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 18) * .65) <
                            368 ||
                        MediaQuery.textScalerOf(context).scale(13) > 18,
                  ),
                ),
              ),
          ],
        ),
      );
      final management = _card(
        theme,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.secondary.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Symbols.link,
                    size: 21,
                    fill: 1,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _detailText(l10n.connectionManage, theme, size: 15, bold: true),
                const SizedBox(height: 16),
                _detailText(
                  l10n.connectionManualRecovery,
                  theme,
                  size: 12,
                  muted: true,
                ),
              ],
            ),
            Padding(padding: const EdgeInsets.only(top: 20), child: action),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hero,
          const SizedBox(height: 18),
          if (narrow) ...[
            information,
            const SizedBox(height: 18),
            management,
          ] else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 65, child: information),
                  const SizedBox(width: 18),
                  Expanded(flex: 35, child: management),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _card(
            theme,
            color: Color.alphaBlend(
              theme.textColorPrimary.withValues(alpha: .05),
              theme.primary,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.verified_user,
                  size: 17,
                  color: theme.textColorTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailText(
                        l10n.connectionCredentialTitle,
                        theme,
                        size: 12,
                        bold: true,
                      ),
                      const SizedBox(height: 6),
                      _detailText(
                        l10n.connectionCredentialDescription,
                        theme,
                        size: 12,
                        muted: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  /// 连接示意中的端点图标与名称，名称过长时允许换行。
  Widget _connectionEndpoint(AppTheme theme, IconData icon, String name) =>
      Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, fill: 1, size: 26, color: theme.basePrimary),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.textColorPrimary),
          ),
        ],
      );

  Widget _card(
    AppTheme theme, {
    required Widget child,
    bool enabled = true,
    double? width,
    VoidCallback? onTap,
    Color? color,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
  }) {
    // 未连接时保留最近数据，内容淡化程度与设备概览的禁用卡片一致。
    child = Semantics(
      enabled: enabled,
      child: ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(opacity: enabled ? 1 : .4, child: child),
        ),
      ),
    );
    final content = Container(
      width: width,
      decoration: BoxDecoration(
        color: color ?? theme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) {
      return CardShadow(
        theme: theme,
        borderRadius: BorderRadius.circular(22),
        child: content,
      );
    }
    // 可点击卡片复用公共交互表面，保留底色并提供按压波纹。
    return TiltCard(
      child: CardShadow(
        theme: theme,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: width,
          child: MenuItemSurface(
            theme: theme,
            onPressed: onTap,
            backgroundColor: color ?? theme.primary,
            hoverColor: color ?? theme.primary,
            borderRadius: BorderRadius.circular(22),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }

  Widget _detailText(
    String value,
    AppTheme theme, {
    double size = 13,
    bool muted = false,
    bool bold = false,
    Color? color,
  }) => Text(
    value,
    style: TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color:
          color ?? (muted ? theme.textColorTertiary : theme.textColorPrimary),
    ),
  );

  Widget _connectionAction({
    required AppTheme theme,
    required AppLocalizations l10n,
    required LanConnection session,
    required LanDevice? device,
    required bool online,
    required bool busy,
    required bool identityChanged,
  }) => AppActionButton(
    theme: theme,
    primary: !online && !busy,
    destructive: online,
    label: online
        ? l10n.lanDisconnect
        : busy
        ? l10n.cancelConnection
        : identityChanged
        ? l10n.lanRepair
        : l10n.retryConnection,
    onPressed: online
        ? () => _confirmDisconnect(session)
        : busy
        ? session.disconnect
        : device == null || session.busy || session.connected
        ? null
        : () async {
            if (identityChanged &&
                !await confirmDeviceRepair(context, session, widget.deviceId)) {
              return;
            }
            if (mounted) unawaited(session.connect(device));
          },
  );

  Future<void> _confirmDisconnect(LanConnection session) async {
    final confirmed = await showAppConfirmation(
      context: context,
      theme: context.read<ThemeProvider>().themeData,
      actionKey: 'device-disconnect',
      title: context.l10n.lanDisconnectConfirmTitle,
      description: context.l10n.lanDisconnectDescription,
      confirmLabel: context.l10n.lanDisconnect,
    );
    if (!confirmed ||
        !mounted ||
        session.device?.id != widget.deviceId ||
        !session.connected) {
      return;
    }
    session.disconnect();
  }
}
