/*
 * @Description: 展示已连接设备的真实状态、固件信息和连接操作。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 18:37:01
 * @LastEditTime: 2026-10-04 18:58:06
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/provider.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';

class ConnectedDevicePage extends StatelessWidget {
  const ConnectedDevicePage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final session = context.watch<LanConnection>();
    final saved = context.watch<DeviceManagerProvider>().lanDevice(deviceId);
    final l10n = context.l10n;
    final selected = session.device?.id == deviceId;
    final online = selected && session.connected;
    final busy = selected && session.busy;
    final identityChanged = selected && session.identityChanged;
    final device = selected ? session.device : saved;
    final status = online
        ? l10n.deviceConnected
        : busy
        ? l10n.deviceConnecting
        : l10n.lanOffline;

    Widget row(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              title,
              style: TextStyle(color: theme.textColorTertiary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SelectableText(
              value,
              contextMenuBuilder: AppTextSelectionMenu.build,
              style: TextStyle(color: theme.textColorPrimary),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 520 ? 20 : 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device?.name ?? deviceId,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      online ? Symbols.check_circle : Symbols.link_off,
                      fill: 1,
                      size: 18,
                      color: online
                          ? theme.baseTertiary
                          : theme.textColorTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(color: theme.textColorSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      row(l10n.lanModel, device?.model ?? '—'),
                      row(l10n.lanMacAddress, device?.macAddress ?? '—'),
                      row(l10n.lanAddress, device?.address ?? '—'),
                      row(l10n.lanFirmware, online ? session.firmware : '—'),
                      row(
                        l10n.lanUptime,
                        online ? '${session.uptimeMs ~/ 1000} s' : '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  identityChanged
                      ? l10n.lanIdentityChanged
                      : online
                      ? l10n.lanConnectedDescription
                      : busy
                      ? l10n.lanConfirmOnDevice
                      : l10n.lanReconnectDescription,
                  style: TextStyle(color: theme.textColorTertiary, height: 1.5),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (online || busy)
                      AppActionButton(
                        theme: theme,
                        label: online
                            ? l10n.lanDisconnect
                            : l10n.cancelConnection,
                        onPressed: session.disconnect,
                      )
                    else
                      AppActionButton(
                        theme: theme,
                        primary: true,
                        label: identityChanged
                            ? l10n.lanRepair
                            : l10n.retryConnection,
                        onPressed:
                            device == null || session.busy || session.connected
                            ? null
                            : () async {
                                if (identityChanged &&
                                    !await confirmDeviceRepair(
                                      context,
                                      session,
                                      deviceId,
                                    )) {
                                  return;
                                }
                                if (context.mounted) {
                                  unawaited(session.connect(device));
                                }
                              },
                      ),
                    if (!online && !busy)
                      AppActionButton(
                        theme: theme,
                        label: l10n.searchAgain,
                        onPressed: () => context
                            .read<AppNavigationProvider>()
                            .setPage(AppPage.addDevice),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
