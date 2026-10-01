/*
 * @Description: 为尚未适配设置页的设备显示说明，并提供返回入口。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/animated_circle_icon_button.dart';
import '../../../../core/widgets/settings/widgets.dart';

class UnsupportedDeviceSettings extends StatelessWidget {
  const UnsupportedDeviceSettings({
    super.key,
    required this.deviceName,
    required this.onClose,
  });

  final String deviceName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    return ColoredBox(
      color: theme.secondary,
      child: Stack(
        children: [
          SettingsPageLayout(
            theme: theme,
            title: context.l10n.deviceSettings,
            children: [
              const SizedBox(height: 24),
              Text(deviceName, style: TextStyle(color: theme.textColorPrimary)),
              const SizedBox(height: 8),
              Text(
                context.l10n.deviceSettingsUnavailable,
                style: TextStyle(color: theme.textColorSecondary),
              ),
            ],
          ),
          Positioned(
            top: 20,
            right: 20,
            child: AnimatedCircleIconButton(
              icon: Icons.close_rounded,
              theme: theme,
              size: 40,
              iconSize: 22,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}
