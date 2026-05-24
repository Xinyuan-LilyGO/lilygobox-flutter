import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/vscode_settings.dart';

class GeneralSettingsContent extends StatelessWidget {
  const GeneralSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return VscodeSettingsPage(
      theme: theme,
      title: context.l10n.general,
      children: const [],
    );
  }
}
