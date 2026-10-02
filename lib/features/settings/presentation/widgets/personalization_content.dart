/*
 * @Description: 展示外观设置，支持紧凑主题预览卡片切换。
 * @Author: LILYGO_L
 * @Date: 2025-10-31 17:01:16
 * @LastEditTime: 2026-10-02 20:42:05
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import 'content_layout.dart';
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

    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.personalization,
      description: context.l10n.appearanceSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.theme,
          description: context.l10n.themeDescription,
          child: ThemePicker(
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
