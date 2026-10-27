/*
 * @Description: 复用公共确认弹窗处理设备证书变化后的重新配对。
 * @Author: LILYGO_L
 * @Date: 2026-10-06 16:00:00
 * @LastEditTime: 2026-10-06 16:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../state/lan_connection.dart';

Future<bool> confirmDeviceRepair(
  BuildContext context,
  LanConnection session,
  String deviceId,
) async {
  final l10n = context.l10n;
  final confirmed = await showAppConfirmation(
    context: context,
    theme: context.read<ThemeProvider>().themeData,
    actionKey: 'device-repair',
    title: l10n.lanRepair,
    description: l10n.lanRepairDescription,
    confirmLabel: l10n.lanRepair,
  );
  if (!confirmed || !context.mounted) return false;
  final cleared = await session.resetDeviceTrust(deviceId);
  if (!cleared && context.mounted) {
    showAppNotice(ScaffoldMessenger.of(context), l10n.deviceConnectionFailed);
  }
  return cleared;
}
