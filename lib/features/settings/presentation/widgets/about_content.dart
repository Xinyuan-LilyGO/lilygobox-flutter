/*
 * @Description: 展示应用版本、版权等关于信息。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_info/package_info_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/settings/widgets.dart';

class AboutContent extends StatelessWidget {
  const AboutContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = context.watch<PackageInfoProvider>();

    return SettingsPageLayout(
      theme: theme,
      title: context.l10n.about,
      children: [
        SettingsRow(
          theme: theme,
          title: context.l10n.version,
          description: context.l10n.version,
          showMoreButton: false,
          control: SettingReadOnlyField(
            theme: theme,
            value: 'v${packageInfoProvider.version}',
          ),
        ),
        SettingsRow(
          theme: theme,
          title: context.l10n.copyright,
          description: context.l10n.copyright,
          controlWidth: 260.0,
          showMoreButton: false,
          control: SettingReadOnlyField(
            theme: theme,
            value: '${packageInfoProvider.appName} 2025 LILYGO Corporation',
          ),
        ),
      ],
    );
  }
}
