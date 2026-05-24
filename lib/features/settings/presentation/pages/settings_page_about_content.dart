import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_info/package_info_provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/vscode_settings.dart';

class AboutContent extends StatelessWidget {
  const AboutContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final packageInfoProvider = context.watch<PackageInfoProvider>();

    return VscodeSettingsPage(
      theme: theme,
      title: context.l10n.about,
      children: [
        VscodeSettingsRow(
          theme: theme,
          title: context.l10n.version,
          description: context.l10n.version,
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value: 'v${packageInfoProvider.version}',
          ),
        ),
        VscodeSettingsRow(
          theme: theme,
          title: context.l10n.copyright,
          description: context.l10n.copyright,
          controlWidth: 260.0,
          showMoreButton: false,
          control: VscodeSettingReadOnlyField(
            theme: theme,
            value:
                '${packageInfoProvider.appName} 2025 LILYGO Corporation',
          ),
        ),
      ],
    );
  }
}
