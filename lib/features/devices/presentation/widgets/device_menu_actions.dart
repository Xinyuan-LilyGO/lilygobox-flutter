/*
 * @Description: 主页与设备详情菜单共用连接操作及删除确认。
 * @Author: LILYGO_L
 * @Date: 2026-10-10 16:00:00
 * @LastEditTime: 2026-10-10 16:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../app/shell/state/provider.dart';
import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../state/lan_connection.dart';
import '../../state/manager_provider.dart';
import '../confirm_repair.dart';

/// 两处菜单共用状态判定，关闭菜单后执行连接或断开确认。
RightClickMenuItem deviceConnectionMenuItem(
  BuildContext context,
  String id,
  VoidCallback closeMenu, {
  bool showDivider = false,
}) {
  final session = context.watch<LanConnection>();
  final device = context.watch<DeviceManagerProvider>().lanDevice(id);
  final selected = session.device?.id == id;
  final online = selected && session.connected;
  final busy = selected && session.busy;
  return RightClickMenuItem(
    showDivider: showDivider,
    label: online
        ? context.l10n.lanDisconnect
        : busy
        ? context.l10n.cancelConnection
        : context.l10n.retryConnection,
    icon: online ? Symbols.link_off : Symbols.link,
    isEnabled:
        online ||
        busy ||
        (device != null && !session.busy && !session.connected),
    onTap: () async {
      closeMenu();
      if (online) {
        final confirmed = await showAppConfirmation(
          context: context,
          theme: context.read<ThemeProvider>().themeData,
          actionKey: 'device-disconnect',
          title: context.l10n.lanDisconnectConfirmTitle,
          description: context.l10n.lanDisconnectDescription,
          confirmLabel: context.l10n.lanDisconnect,
        );
        if (confirmed &&
            context.mounted &&
            session.device?.id == id &&
            session.connected) {
          session.disconnect();
        }
      } else if (busy) {
        session.disconnect();
      } else if (device != null) {
        if (selected &&
            session.identityChanged &&
            !await confirmDeviceRepair(context, session, id)) {
          return;
        }
        if (context.mounted && !session.busy && !session.connected) {
          await session.connect(device);
        }
      }
    },
  );
}

/// 删除前确认，先清除本机凭证，再删除配置并返回主页。
Future<void> deleteDeviceFromDetail(BuildContext context, String id) async {
  final manager = context.read<DeviceManagerProvider>();
  final session = context.read<LanConnection>();
  final shell = context.read<AppShellProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final confirmed = await showAppConfirmation(
    context: context,
    theme: context.read<ThemeProvider>().themeData,
    actionKey: 'delete-device',
    title: l10n.deleteDeviceConfirmTitle,
    description: l10n.deleteDeviceConfirmDescription(manager.displayName(id)),
    confirmLabel: l10n.delete,
  );
  if (!confirmed || !context.mounted || !manager.addedDevices.contains(id)) {
    return;
  }
  var deleted = false;
  try {
    if (manager.lanDevice(id) == null || await session.forgetDevice(id)) {
      deleted = await manager.removeDeviceAndSave(id);
      if (deleted) shell.updateSelectedIndex(0);
    }
  } catch (_) {
    deleted = false;
  }
  if (messenger.mounted) {
    showAppNotice(
      messenger,
      deleted ? l10n.deleteDeviceSucceeded : l10n.deleteDeviceFailed,
    );
  }
}
