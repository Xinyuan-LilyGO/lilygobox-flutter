/*
 * @Description: 设备详情页，采用可变卡片布局展示设备、连接、电池和控制信息。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 15:14:56
 * @LastEditTime: 2026-10-09 10:00:00
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
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../data/lan_discovery.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';
import '../widgets/device_battery_colors.dart';
import '../widgets/device_dashboard.dart';
import '../widgets/device_status_badge.dart';

enum _DeviceDetailView { control, information, battery, connection }

class ConnectedDevicePage extends StatefulWidget {
  const ConnectedDevicePage({
    super.key,
    required this.deviceId,
    this.nestedView,
    this.pageTitle,
  });

  final String deviceId;
  final ValueNotifier<bool>? nestedView;
  final ValueNotifier<String?>? pageTitle;

  @override
  State<ConnectedDevicePage> createState() => _ConnectedDevicePageState();
}

class _ConnectedDevicePageState extends State<ConnectedDevicePage>
    with SingleTickerProviderStateMixin {
  _DeviceDetailView _view = _DeviceDetailView.control;
  final List<_DeviceDetailView> _viewHistory = [];
  late final AnimationController _viewTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  double _brightness = .72;
  double _volume = .40;
  double _vibration = .50;
  bool _screenOn = true;
  bool _soundOn = true;
  bool _vibrationOn = true;
  int _rotation = 0;

  @override
  void initState() {
    super.initState();
    widget.nestedView?.addListener(_handleOuterBack);
  }

  @override
  void didUpdateWidget(covariant ConnectedDevicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
          : _viewTitle(context.l10n);
      widget.nestedView?.value = previous != _DeviceDetailView.control;
      _animateViewChange();
    }
  }

  void _openView(_DeviceDetailView view) {
    if (_view == view) return;
    _viewHistory.add(_view);
    setState(() => _view = view);
    widget.pageTitle?.value = _viewTitle(context.l10n);
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
    status: status,
    online: online,
    description: description,
    connecting: connecting,
    brightness: _brightness,
    volume: _volume,
    vibration: _vibration,
    screenOn: _screenOn,
    soundOn: _soundOn,
    vibrationOn: _vibrationOn,
    rotation: _rotation,
    onBrightness: (value) => setState(() => _brightness = value),
    onVolume: (value) => setState(() => _volume = value),
    onVibration: (value) => setState(() => _vibration = value),
    onScreen: (value) => setState(() => _screenOn = value),
    onSound: (value) => setState(() => _soundOn = value),
    onVibrationEnabled: (value) => setState(() => _vibrationOn = value),
    onRotation: (value) => setState(() => _rotation = value),
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
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: LayoutBuilder(
          builder: (context, constraints) => Text(
            title,
            style: TextStyle(
              // 与设备概览共享主标题层级，大字体或窄窗口采用紧凑字号。
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _detailText(
                    l10n.homeDeviceCardLabel,
                    theme,
                    size: 14,
                    muted: true,
                  ),
                ),
                const SizedBox(width: 8),
                DeviceStatusBadge(
                  theme: theme,
                  label: online
                      ? l10n.homeDeviceOnline
                      : session.busy && session.device?.id == widget.deviceId
                      ? l10n.homeDeviceConnecting
                      : l10n.homeDeviceOffline,
                  connected: online,
                  connecting:
                      session.busy && session.device?.id == widget.deviceId,
                ),
              ],
            ),
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
                _detailText(
                  device?.name ?? widget.deviceId,
                  theme,
                  size: 20,
                  bold: true,
                ),
                const SizedBox(height: 8),
                _detailText(device?.model ?? '—', theme, size: 12, muted: true),
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
  }) {
    final caption = _detailText(label, theme, muted: true);
    final detail = SelectableText(
      value,
      contextMenuBuilder: AppTextSelectionMenu.build,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.textColorPrimary,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption, const SizedBox(height: 6), detail],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: caption),
                const SizedBox(width: 18),
                Expanded(child: detail),
              ],
            ),
    );
  }

  Widget _batteryView(AppTheme theme, bool online) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final summary = _card(
        theme,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _detailText('当前电量', theme, size: 15, bold: true),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                online ? '82%' : '—',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: theme.textColorPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 236),
                child: Column(
                  children: [
                    DeviceBatteryGraphic(
                      theme: theme,
                      progress: online ? .82 : 0,
                      height: 96,
                      colors: DeviceBatteryColors(theme),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _detailText(
                    online ? '电池供电' : '未连接电池',
                    theme,
                    size: 15,
                    bold: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: _detailText(
                online ? '未连接充电器' : '设备未连接',
                theme,
                size: 12,
                muted: true,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      );
      final details = _card(
        theme,
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
                  '电压',
                  online ? '4.02' : '—',
                  'V',
                );
                final temperature = _batteryMetric(
                  theme,
                  Symbols.thermometer,
                  '温度',
                  online ? '31.6' : '—',
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
            _batteryStatusRow(theme, '充电状态', online ? '未充电' : '—'),
            _batteryStatusRow(theme, '电流', online ? '−320 mA' : '—'),
            _batteryStatusRow(theme, '供电来源', online ? '电池' : '—'),
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
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 37, child: summary),
                  const SizedBox(width: 18),
                  Expanded(flex: 63, child: details),
                ],
              ),
            ),
        ],
      );
    },
  );

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
            Icon(icon, size: 18, color: theme.basePrimary),
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

  Widget _batteryStatusRow(AppTheme theme, String label, String value) =>
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.materialColors.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(child: _detailText(label, theme, muted: true)),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

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
                        color: theme.basePrimary.withValues(
                          alpha: online ? .45 : .22,
                        ),
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
                          color: theme.basePrimary.withValues(alpha: .22),
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
                            color: theme.textColorTertiary,
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
            child: Icon(icon, size: 26, color: theme.basePrimary),
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
    double? width,
    VoidCallback? onTap,
    Color? color,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
  }) {
    final content = Container(
      width: width,
      decoration: BoxDecoration(
        color: color ?? theme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return content;
    // 可点击卡片复用公共交互表面，保留底色并提供按压波纹。
    return SizedBox(
      width: width,
      child: MenuItemSurface(
        theme: theme,
        onPressed: onTap,
        backgroundColor: color ?? theme.primary,
        hoverColor: color ?? theme.primary,
        borderRadius: BorderRadius.circular(22),
        child: Padding(padding: padding, child: child),
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
