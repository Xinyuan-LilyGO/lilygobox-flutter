/*
 * @Description: 展示应用版本、版权等关于信息。
 * @Author: LILYGO_L
 * @Date: 2025-11-17 11:28:26
 * @LastEditTime: 2026-10-02 20:42:05
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_info/package_info_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import 'content_layout.dart';

class AboutContent extends StatelessWidget {
  const AboutContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = context.watch<PackageInfoProvider>();
    final version = packageInfoProvider.version.replaceFirst(
      RegExp(r'^[vV]'),
      '',
    );

    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.about,
      description: context.l10n.aboutSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.version,
          description: version,
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        SettingsField(
          theme: theme,
          title: context.l10n.copyright,
          description: '${packageInfoProvider.appName} 2025 LILYGO Corporation',
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
