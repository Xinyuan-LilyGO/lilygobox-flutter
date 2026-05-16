/*
 * @Description: T-Glasses-P4 板子设置页面
 * @Author: LILYGO_L
 * @Date: 2025-11-19 14:00:00
 * @LastEditTime: 2025-11-20 10:02:17
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/theme_provider.dart';
import '../widgets/t_glasses_p4_settings_split_view.dart';

class DeviceSettingsTGlassesP4 extends StatelessWidget {
  const DeviceSettingsTGlassesP4({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    return Container(
      color: theme.primary, // 确保覆盖整个背景
      child: const TGlassesP4SettingsSplitView(),
    );
  }
}
