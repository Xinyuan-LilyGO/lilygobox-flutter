/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:43:14
 * @LastEditTime: 2025-11-21 15:48:12
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/theme_provider.dart';

class TGlassesP4PageDeviceSettings extends StatelessWidget {
  const TGlassesP4PageDeviceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final theme = themeProvider.themeData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 15.0, bottom: 8.0),
          child: Text(
            "设备设置",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Card(
            color: theme.secondary,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "基本设置",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildSettingItem(theme, "设备名称", "T-Glasses-P4"),
                  _buildSettingItem(theme, "设备ID", "TGLS-P4-20241117"),
                  _buildSettingItem(theme, "硬件版本", "Rev 2.1"),
                  _buildSettingItem(theme, "启动模式", "正常启动"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建设置项
  Widget _buildSettingItem(AppTheme theme, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: theme.textColorSecondary)),
          Text(
            value,
            style: TextStyle(
              color: theme.textColorPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
