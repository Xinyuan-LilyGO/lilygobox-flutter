import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/vscode_settings.dart';

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

    return VscodeSettingsPage(
      theme: theme,
      title: context.l10n.languageAndRegion,
      children: [
        VscodeSettingsRow(
          theme: theme,
          title: context.l10n.language,
          description: context.l10n.languageDescription,
          modified: currentLanguageCode != 'en',
          controlWidth: 240.0,
          onReset: () => languageProvider.changeLanguage('en'),
          control: VscodeSettingSelect<String>(
            theme: theme,
            value: currentLanguageCode,
            items: LanguageProvider.supportedLanguages.map((language) {
              final nativeName = language['nativeName']!;
              final name = language['name']!;

              return DropdownMenuItem<String>(
                value: language['code'],
                child: Text('$nativeName ($name)'),
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
      ],
    );
  }
}
