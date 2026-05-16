/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-05 15:54:19
 * @LastEditTime: 2025-11-19 13:40:57
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/theme_provider.dart';
import '../widgets/settings_split_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 确保使用正确的方式获取 Provider 的值 (使用 listen: false)
    final theme = Provider.of<ThemeProvider>(context, listen: false).themeData;

    // 移除顶部栏 Container，让 SettingsSplitView 填充整个屏幕
    return Container(
      color: theme.primary, // 整体背景色
      child: const SettingsSplitView(),
    );
  }
}
