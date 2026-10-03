/*
 * @Description: 为设置页和侧栏菜单统一提供退出登录确认，仅确认后清除当前会话。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 23:41:53
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../state/provider.dart';

Future<void> confirmAccountSignOut(
  BuildContext context, {
  required AppTheme theme,
}) async {
  final account = context.read<AccountProvider>();
  final userId = account.user?.id;
  if (userId == null || account.busy) return;
  final l10n = context.l10n;
  final confirmed = await showAppConfirmation(
    context: context,
    theme: theme,
    actionKey: 'github-sign-out',
    title: l10n.githubSignOutConfirmTitle,
    description: l10n.githubSignOutDescription,
    confirmLabel: l10n.githubSignOut,
  );
  if (!confirmed || !context.mounted || account.user?.id != userId) return;
  await account.signOut();
}
