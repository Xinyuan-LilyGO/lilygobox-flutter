/*
 * @Description: 展示设备控制、连接和信息详情，通过底部导航切换并保留页面状态。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-07 18:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/retained_page_stack.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';
import '../widgets/device_detail_navigation.dart';

class ConnectedDevicePage extends StatefulWidget {
  const ConnectedDevicePage({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ConnectedDevicePage> createState() => _ConnectedDevicePageState();
}

class _ConnectedDevicePageState extends State<ConnectedDevicePage> {
  DeviceDetailTab _tab = DeviceDetailTab.control;

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

    // 只操作当前设备的会话；其他设备在线时保留原有的重连限制。
    final connectionAction = AppActionButton(
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
                  !await confirmDeviceRepair(
                    context,
                    session,
                    widget.deviceId,
                  )) {
                return;
              }
              if (mounted) unawaited(session.connect(device));
            },
    );

    Widget control() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online) ...[
          Text(
            description,
            style: TextStyle(height: 1.5, color: theme.textColorTertiary),
          ),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: connectionAction),
          const SizedBox(height: 24),
        ],
        _sectionTitle(l10n.deviceScreenControls, theme),
        _group(theme, [
          _unavailableControl(
            theme,
            Symbols.desktop_windows,
            l10n.deviceScreenDisplay,
          ),
          _unavailableControl(
            theme,
            Symbols.brightness_6,
            l10n.deviceBrightness,
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle(l10n.deviceSettings, theme),
        _group(theme, [
          _unavailableControl(theme, Symbols.volume_up, l10n.deviceSound),
          _unavailableControl(
            theme,
            Symbols.display_settings,
            l10n.deviceDisplaySettings,
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          l10n.deviceControlsUnavailable,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: theme.textColorTertiary,
          ),
        ),
      ],
    );

    Widget connection() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.deviceConnectionTab, theme),
        _group(theme, [
          _infoRow(theme, l10n.deviceConnectionStatus, status),
          _infoRow(
            theme,
            l10n.deviceConnectionMethod,
            'Wi-Fi',
            icon: Symbols.wifi,
          ),
          _infoRow(
            theme,
            l10n.lanAddress,
            online ? device?.address ?? '—' : '—',
          ),
          _infoRow(theme, l10n.lanMacAddress, device?.macAddress ?? '—'),
        ]),
        const SizedBox(height: 18),
        Text(
          description,
          style: TextStyle(height: 1.5, color: theme.textColorTertiary),
        ),
        const SizedBox(height: 20),
        Align(alignment: Alignment.centerLeft, child: connectionAction),
      ],
    );

    Widget information() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.deviceInfoTab, theme),
        _group(theme, [
          _infoRow(
            theme,
            l10n.deviceNameLabel,
            device?.name ?? widget.deviceId,
          ),
          _infoRow(theme, l10n.lanModel, device?.model ?? '—'),
          _infoRow(
            theme,
            l10n.lanFirmware,
            online && session.firmware.isNotEmpty ? session.firmware : '—',
          ),
          _infoRow(theme, l10n.lanMacAddress, device?.macAddress ?? '—'),
          _infoRow(
            theme,
            l10n.lanUptime,
            online ? '${session.uptimeMs ~/ 1000} s' : '—',
          ),
        ]),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        // 导航独占底部空间，列表滚动和窄窗口下的长内容不会被悬浮栏遮挡。
        Widget page(DeviceDetailTab tab, Widget content) =>
            SingleChildScrollView(
              key: PageStorageKey('${widget.deviceId}-${tab.name}'),
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 36,
                20,
                compact ? 20 : 36,
                24,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DeviceHeader(
                        theme: theme,
                        name: device?.name ?? widget.deviceId,
                        model: device?.model ?? '—',
                        status: status,
                        online: online,
                        busy: busy,
                        compact: compact,
                      ),
                      const SizedBox(height: 28),
                      content,
                    ],
                  ),
                ),
              ),
            );
        return Column(
          children: [
            Expanded(
              child: RetainedPageStack(
                activeKey: _tab,
                pages: {
                  DeviceDetailTab.control: page(
                    DeviceDetailTab.control,
                    control(),
                  ),
                  DeviceDetailTab.connection: page(
                    DeviceDetailTab.connection,
                    connection(),
                  ),
                  DeviceDetailTab.info: page(
                    DeviceDetailTab.info,
                    information(),
                  ),
                },
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: DeviceDetailNavigation(
                theme: theme,
                selected: _tab,
                onSelected: (tab) => setState(() => _tab = tab),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 用户确认后再断开，避免弹窗期间切换会话误断开其他设备。
  Future<void> _confirmDisconnect(LanConnection session) async {
    final deviceId = widget.deviceId;
    final l10n = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: context.read<ThemeProvider>().themeData,
      actionKey: 'device-disconnect',
      title: l10n.lanDisconnectConfirmTitle,
      description: l10n.lanDisconnectDescription,
      confirmLabel: l10n.lanDisconnect,
    );
    if (!confirmed ||
        !mounted ||
        session.device?.id != deviceId ||
        !session.connected) {
      return;
    }
    session.disconnect();
  }

  Widget _sectionTitle(String title, AppTheme theme) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: theme.textColorSecondary,
      ),
    ),
  );

  Widget _group(AppTheme theme, List<Widget> rows) => Container(
    decoration: BoxDecoration(
      color: theme.primary,
      borderRadius: BorderRadius.circular(18),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: .13),
            ),
          rows[i],
        ],
      ],
    ),
  );

  Widget _unavailableControl(AppTheme theme, IconData icon, String title) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Icon(icon, fill: 1, size: 21, color: theme.textColorTertiary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 14, color: theme.textColorSecondary),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  context.l10n.deviceControlUnavailable,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _infoRow(
    AppTheme theme,
    String label,
    String value, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 17),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        final title = Text(
          label,
          style: TextStyle(fontSize: 14, color: theme.textColorTertiary),
        );
        final text = SelectableText(
          value,
          contextMenuBuilder: AppTextSelectionMenu.build,
          textAlign: narrow ? TextAlign.start : TextAlign.end,
          style: TextStyle(fontSize: 14, color: theme.textColorPrimary),
        );
        final detail = icon == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: theme.textColorSecondary),
                  const SizedBox(width: 6),
                  Flexible(child: text),
                ],
              );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 8), detail],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: title),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Align(alignment: Alignment.centerRight, child: detail),
            ),
          ],
        );
      },
    ),
  );
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({
    required this.theme,
    required this.name,
    required this.model,
    required this.status,
    required this.online,
    required this.busy,
    required this.compact,
  });

  final AppTheme theme;
  final String name;
  final String model;
  final String status;
  final bool online;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 23 : 28,
                fontWeight: FontWeight.w700,
                color: theme.textColorPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: theme.textColorTertiary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online
                        ? theme.adaptiveColor(
                            dark: const Color(0xFF7CBD94),
                            light: const Color(0xFF4B9565),
                          )
                        : busy
                        ? theme.baseTertiary
                        : theme.textColorTertiary,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    '$status · Wi-Fi',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 20),
      // 正式设备图片尚未接入，使用灰色 Blur On 图标预留位置。
      ExcludeSemantics(
        child: SizedBox(
          width: compact ? 64 : 112,
          height: compact ? 96 : 120,
          child: Icon(
            Symbols.blur_on,
            fill: 1,
            size: compact ? 40 : 56,
            color: theme.textColorTertiary.withValues(alpha: .45),
          ),
        ),
      ),
    ],
  );
}
