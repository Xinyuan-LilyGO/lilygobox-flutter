/*
 * @Description: 构建应用设置页面的背景与设置分栏内容。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 15:54:19
 * @LastEditTime: 2025-11-19 13:40:57
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/provider.dart';
import '../widgets/split_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).themeData;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: theme.primary, // 整体背景色
      child: const SettingsSplitView(),
    );
  }
}
