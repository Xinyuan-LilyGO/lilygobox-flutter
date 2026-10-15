/*
 * @Description: 提供通用设置分类的页面布局。
 * @Author: LILYGO_L
 * @Date: 2026-05-24 23:22:38
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/shell/state/provider.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/layout/split_view_provider.dart';
import '../../../../core/storage/preferences.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import 'content_layout.dart';

class GeneralSettingsContent extends StatelessWidget {
  const GeneralSettingsContent({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return SettingsContentLayout(
      theme: theme,
      title: context.l10n.general,
      description: context.l10n.generalSettingsDescription,
      children: [
        SettingsField(
          theme: theme,
          title: context.l10n.restoreDefaults,
          description: context.l10n.restoreDefaultsDescription,
          child: AppActionButton(
            key: const ValueKey('restore-defaults'),
            theme: theme,
            label: context.l10n.restoreDefaults,
            onPressed: () => _confirmReset(context),
            settingBackground: true,
            backgroundColor: theme.adaptiveColor(
              dark: theme.secondaryTextBackgroundColor,
              light: theme.secondaryTextHoverColor,
            ),
            hoverColor: theme.secondaryTextHoverColorAlt,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: theme,
      actionKey: 'restore-defaults',
      title: l10n.restoreDefaultsConfirmTitle,
      description: l10n.restoreDefaultsConfirmDescription,
      confirmLabel: l10n.restoreDefaults,
    );
    if (confirmed != true || !context.mounted) return;
    // 仅重置明确的应用偏好，不清空设备列表或其他持久化数据。
    context.read<ThemeProvider>().setTheme(ThemeType.dark);
    context.read<LanguageProvider>().changeLanguage('en');
    context.read<AppShellProvider?>()?.resetLayout();
    context.read<SplitViewProvider?>()?.resetSplitWidth();
    context.read<AppPreferences?>()?.setValue('settingsSidebarWidth', 212.0);
  }
}
