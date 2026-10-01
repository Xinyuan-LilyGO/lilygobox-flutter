/*
 * @Description: 展示外观设置，支持主题预览卡片切换及恢复默认主题。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/settings/widgets.dart';
import 'theme_picker.dart';

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

    return SettingsPageLayout(
      theme: theme,
      title: context.l10n.personalization,
      children: [
        SettingsRow(
          theme: theme,
          title: context.l10n.theme,
          description: context.l10n.themeDescription,
          modified: currentThemeType != ThemeType.dark,
          onReset: () => themeProvider.setTheme(ThemeType.dark),
          controlWidth: 240,
          control: ThemePicker(
            theme: theme,
            value: currentThemeType,
            themes: themeProvider.allThemes,
            onChanged: themeProvider.setTheme,
          ),
        ),
      ],
    );
  }
}
