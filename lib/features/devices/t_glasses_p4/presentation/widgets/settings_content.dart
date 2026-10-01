/*
 * @Description: 展示 T-Glasses-P4 设备设置中的设备信息字段。
 * @Author: LILYGO_L
 * @Date: 2025-11-21 15:52:08
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/provider.dart';
import '../../../../../core/widgets/settings/widgets.dart';

class TGlassesP4PageDeviceSettings extends StatelessWidget {
  const TGlassesP4PageDeviceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    return SettingsPageLayout(
      theme: theme,
      title: '设备设置',
      children: [
        SettingsRow(
          theme: theme,
          title: 'device_name',
          description: '设备在列表中显示的名称',
          showMoreButton: false,
          control: SettingReadOnlyField(theme: theme, value: 'T-Glasses-P4'),
        ),
        SettingsRow(
          theme: theme,
          title: 'device_id',
          description: '当前设备唯一识别 ID',
          showMoreButton: false,
          control: SettingReadOnlyField(
            theme: theme,
            value: 'TGLS-P4-20241117',
          ),
        ),
        SettingsRow(
          theme: theme,
          title: 'hardware_version',
          description: '当前设备硬件版本',
          showMoreButton: false,
          control: SettingReadOnlyField(theme: theme, value: 'Rev 2.1'),
        ),
        SettingsRow(
          theme: theme,
          title: 'boot_mode',
          description: '下次启动时使用的设备模式',
          showMoreButton: false,
          control: SettingReadOnlyField(theme: theme, value: '正常启动'),
        ),
      ],
    );
  }
}
