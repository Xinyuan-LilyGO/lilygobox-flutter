import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/vscode_settings.dart';

class PersonalizationContent extends StatefulWidget {
  const PersonalizationContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<PersonalizationContent> createState() => _PersonalizationContentState();
}

class _PersonalizationContentState extends State<PersonalizationContent> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentThemeType = themeProvider.currentTheme;
    final theme = widget.theme;

    return VscodeSettingsPage(
      theme: theme,
      title: context.l10n.personalization,
      children: [
        VscodeSettingsRow(
          theme: theme,
          title: context.l10n.theme,
          description: context.l10n.themeDescription,
          modified: currentThemeType != ThemeType.dark,
          onReset: () => themeProvider.setTheme(ThemeType.dark),
          control: VscodeSettingSelect<ThemeType>(
            theme: theme,
            value: currentThemeType,
            items: ThemeType.values.map((themeType) {
              return DropdownMenuItem<ThemeType>(
                value: themeType,
                child: Text(_themeName(context, themeProvider, themeType)),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              themeProvider.setTheme(value);
            },
          ),
        ),
      ],
    );
  }

  String _themeName(
    BuildContext context,
    ThemeProvider themeProvider,
    ThemeType themeType,
  ) {
    final themeData = themeProvider.allThemes.firstWhere(
      (theme) => theme.type == themeType,
    );
    return themeData.getName(context.l10n);
  }
}
