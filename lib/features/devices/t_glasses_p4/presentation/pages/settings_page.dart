/*
 * @Description: T-Glasses-P4 板子设置页面
 * @Author: LILYGO_L
 * @Date: 2025-11-19 14:00:00
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/provider.dart';
import '../widgets/settings_split_view.dart';

class DeviceSettingsTGlassesP4 extends StatelessWidget {
  const DeviceSettingsTGlassesP4({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).themeData;

    return Container(
      color: theme.primary, // 确保覆盖整个背景
      child: TGlassesP4SettingsSplitView(onClose: onClose),
    );
  }
}
