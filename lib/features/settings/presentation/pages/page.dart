/*
 * @Description: 构建应用设置页面的背景与设置分栏内容。
 * @Author: LILYGO_L
 * @Date: 2025-11-05 15:54:19
 * @LastEditTime: 2026-11-09 09:45:46
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

    return Container(
      color: theme.primary, // 整体背景色
      child: const SettingsSplitView(),
    );
  }
}
