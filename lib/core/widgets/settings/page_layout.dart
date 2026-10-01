/*
 * @Description: 提供设置页面的标题、分隔线与滚动内容布局。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';

/// 应用设置和设备设置共用的标题、分隔线与滚动内容布局。
class SettingsPageLayout extends StatelessWidget {
  const SettingsPageLayout({
    super.key,
    required this.theme,
    required this.title,
    required this.children,
  });

  final AppTheme theme;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(20.0, 28.0, 20.0, 24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Text(
                title,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Divider(
              color: theme.dividerColor.withValues(alpha: 0.28),
              height: 1,
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
