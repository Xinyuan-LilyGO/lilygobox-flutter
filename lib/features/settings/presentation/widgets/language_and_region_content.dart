/*
 * @Description: 展示界面语言选择并使用当前语言显示选项名称。
 * @Author: LILYGO_L
 * @Date: 2025-10-31 17:01:16
 * @LastEditTime: 2026-10-02 20:42:05
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/settings/widgets.dart';
import 'content_layout.dart';

class LanguageAndRegionContent extends StatefulWidget {
  const LanguageAndRegionContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<LanguageAndRegionContent> createState() =>
      _LanguageAndRegionContentState();
}

class _LanguageAndRegionContentState extends State<LanguageAndRegionContent> {
  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final currentLanguageCode = languageProvider.locale.languageCode;
    final theme = widget.theme;

    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.languageAndRegion,
      description: context.l10n.languageSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.language,
          description: context.l10n.languageDescription,
          child: SizedBox(
            width: 220,
            child: SettingSelect<String>(
              theme: theme,
              value: currentLanguageCode,
              items: LanguageProvider.supportedLanguages.map((language) {
                final languageName = switch (language['code']) {
                  'en' => context.l10n.languageEnglish,
                  'zh' => context.l10n.languageChinese,
                  _ => language['nativeName']!,
                };

                return DropdownMenuItem<String>(
                  value: language['code'],
                  child: Text(languageName),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                languageProvider.changeLanguage(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}
