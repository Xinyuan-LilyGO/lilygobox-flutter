/*
 * @Description: 统一应用操作的二次确认弹窗、取消按钮及确认按钮样式。
 */

import 'package:flutter/material.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'action_button.dart';
import 'dialog_style.dart';

/// 确认和流程提示共用的弹窗外观。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.theme,
    required this.title,
    required this.content,
    required this.actions,
    this.constraints,
    this.contentPadding,
    this.titleLeading,
    this.titleFontSize = 18,
    this.titleFontWeight = FontWeight.normal,
  });

  final AppTheme theme;
  final String title;

  /// 可选的标题前置图标，与标题一起布局，正文不再单独占位。
  final Widget? titleLeading;
  final Widget content;
  final List<Widget> actions;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? contentPadding;
  final double titleFontSize;
  final FontWeight titleFontWeight;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: AppDialogStyle.titleStyle(
        theme,
      ).copyWith(fontSize: titleFontSize, fontWeight: titleFontWeight),
    );
    return AlertDialog(
      constraints: constraints,
      backgroundColor: AppDialogStyle.backgroundColor(theme),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDialogStyle.borderRadius,
      ),
      title: titleLeading == null
          ? titleText
          : Row(
              children: [
                titleLeading!,
                const SizedBox(width: 8),
                Expanded(child: titleText),
              ],
            ),
      contentPadding: contentPadding,
      content: content,
      actions: actions,
    );
  }
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
          AppActionButton.dialog(
            key: ValueKey('${confirm ? 'confirm' : 'cancel'}-$actionKey'),
            theme: theme,
            label: confirm ? confirmLabel : cancelLabel,
            primary: confirm,
            onPressed: () => Navigator.pop(dialogContext, confirm),
          ),
      ],
    ),
  );
  return confirmed == true;
}
