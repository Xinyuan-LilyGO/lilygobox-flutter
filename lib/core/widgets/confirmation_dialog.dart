/*
 * @Description: 统一应用操作的二次确认弹窗、取消按钮及确认按钮样式。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 23:41:53
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import '../theme/material_palette.dart';
import 'action_button.dart';

/// 确认和流程提示共用的弹窗外观。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.theme,
    required this.title,
    required this.content,
    required this.actions,
    this.constraints,
  });

  final AppTheme theme;
  final String title;
  final Widget content;
  final List<Widget> actions;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: constraints,
    backgroundColor: theme.materialColors.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    title: Text(
      title,
      style: TextStyle(fontSize: 18, color: theme.textColorPrimary),
    ),
    content: content,
    actions: actions,
  );
}

Future<bool> showAppConfirmation({
  required BuildContext context,
  required AppTheme theme,
  required String actionKey,
  required String title,
  required String description,
  required String confirmLabel,
}) async {
  final cancelLabel = context.l10n.settingsCancel;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      theme: theme,
      title: title,
      content: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: theme.textColorSecondary,
        ),
      ),
      actions: [
        for (final confirm in [false, true])
          AppActionButton(
            key: ValueKey('${confirm ? 'confirm' : 'cancel'}-$actionKey'),
            theme: theme,
            label: confirm ? confirmLabel : cancelLabel,
            primary: confirm,
            settingBackground: !confirm,
            onPressed: () => Navigator.pop(dialogContext, confirm),
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            borderRadius: BorderRadius.circular(8),
          ),
      ],
    ),
  );
  return confirmed == true;
}
