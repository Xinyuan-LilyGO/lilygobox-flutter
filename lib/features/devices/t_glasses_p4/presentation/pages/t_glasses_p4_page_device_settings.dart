import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/theme_provider.dart';
import '../../../../../core/widgets/vscode_settings.dart';

class TGlassesP4PageDeviceSettings extends StatelessWidget {
  const TGlassesP4PageDeviceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    return VscodeSettingsPage(
      theme: theme,
      title: '设备设置',
      children: [
        VscodeSettingsRow(
          theme: theme,
          title: 'device_name',
          description: '设备在列表中显示的名称',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'T-Glasses-P4',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'device_id',
          description: '当前设备唯一识别 ID',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'TGLS-P4-20241117',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'hardware_version',
          description: '当前设备硬件版本',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(theme: theme, value: 'Rev 2.1'),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: 'boot_mode',
          description: '下次启动时使用的设备模式',
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: '正常启动',
          ),
        ),
      ],
    );
  }
}
