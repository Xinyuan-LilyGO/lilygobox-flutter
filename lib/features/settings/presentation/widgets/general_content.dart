/*
 * @Description: 提供通用设置分类的页面布局。
 * @Author: LILYGO_L
 * @Date: 2026-05-24 23:22:38
 * @LastEditTime: 2026-10-03 18:10:36
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/action_button.dart';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SettingsColors(theme).control,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          l10n.restoreDefaultsConfirmTitle,
          style: TextStyle(fontSize: 18, color: theme.textColorPrimary),
        ),
        content: Text(
          l10n.restoreDefaultsConfirmDescription,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: theme.textColorSecondary,
          ),
        ),
        actions: [
          _dialogAction(dialogContext, l10n.settingsCancel, false),
          _dialogAction(dialogContext, l10n.restoreDefaults, true),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // 仅重置明确的应用偏好，不清空设备列表或其他持久化数据。
    context.read<ThemeProvider>().setTheme(ThemeType.dark);
    context.read<LanguageProvider>().changeLanguage('en');
  }

  Widget _dialogAction(BuildContext context, String label, bool confirm) =>
      AppActionButton(
        key: ValueKey(
          confirm ? 'confirm-restore-defaults' : 'cancel-restore-defaults',
        ),
        theme: theme,
        label: label,
        primary: confirm,
        onPressed: () => Navigator.pop(context, confirm),
        fontSize: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        borderRadius: BorderRadius.circular(8),
      );
}
