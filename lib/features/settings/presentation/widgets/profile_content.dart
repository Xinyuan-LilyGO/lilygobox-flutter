/*
 * @Description: 展示 GitHub 个人资料、设备授权验证码和本地登录会话操作。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 20:56:44
 * @LastEditTime: 2026-10-03 23:41:53
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../account/presentation/confirm_sign_out.dart';
import '../../../account/presentation/sign_in_dialog.dart';
import '../../../account/presentation/widgets/avatar.dart';
import '../../../account/state/provider.dart';
import 'content_layout.dart';

class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key, required this.theme});
  final AppTheme theme;

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  bool _signInOpen = false;
  AppTheme get theme => widget.theme;

  Future<void> _signIn(AccountProvider account) async {
    if (_signInOpen) return;
    setState(() => _signInOpen = true);
    try {
      await showAccountSignIn(context, theme: theme, account: account);
    } finally {
      if (mounted) setState(() => _signInOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = context.watch<AccountProvider>();
    final user = account.user;
    final phaseLabel = switch (account.phase) {
      AccountPhase.restoring => l10n.githubRestoring,
      AccountPhase.requesting => l10n.githubRequesting,
      AccountPhase.waiting => l10n.githubWaiting,
      AccountPhase.completing => l10n.githubCompleting,
      AccountPhase.signingOut => l10n.githubSigningOut,
      _ => null,
    };
    return SettingsContentLayout(
      theme: theme,
      title: l10n.profile,
      description: l10n.githubAccountDescription,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountAvatar(theme: theme, user: user),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? l10n.notSignedIn,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorPrimary,
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '@${user.login}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!_signInOpen && phaseLabel != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              phaseLabel,
              style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!_signInOpen && account.error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              accountErrorText(l10n, account.error!),
              key: const ValueKey('github-error'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: theme.textColorSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (user != null) ...[
          Text(
            l10n.githubSignOutDescription,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.textColorTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _action(
              'github-sign-out',
              l10n.githubSignOut,
              account.busy
                  ? null
                  : () => confirmAccountSignOut(context, theme: theme),
            ),
          ),
        ] else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _action(
                'profile-sign-in',
                l10n.githubSignIn,
                account.busy || _signInOpen ? null : () => _signIn(account),
                primary: true,
              ),
              if (account.canRetryRestore)
                _action(
                  'github-retry-restore',
                  l10n.githubRetryRestore,
                  account.busy || _signInOpen ? null : account.restore,
                ),
            ],
          ),
      ],
    );
  }

  Widget _action(
    String key,
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
  }) => !primary
      ? AppActionButton.settings(
          key: ValueKey(key),
          theme: theme,
          label: label,
          onPressed: onPressed,
        )
      : AppActionButton(
          key: ValueKey(key),
          theme: theme,
          label: label,
          onPressed: onPressed,
          primary: primary,
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          borderRadius: BorderRadius.circular(8),
        );
}
