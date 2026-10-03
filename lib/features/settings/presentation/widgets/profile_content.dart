/*
 * @Description: 展示 GitHub 个人资料、设备授权验证码和本地登录会话操作。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 20:56:44
 * @LastEditTime: 2026-10-03 14:22:16
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../account/domain/models.dart';
import '../../../account/presentation/widgets/avatar.dart';
import '../../../account/state/provider.dart';
import 'content_layout.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key, required this.theme});
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = context.watch<AccountProvider>();
    final user = account.user;
    final code = account.authorization;
    final colors = SettingsColors(theme);
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
        if (phaseLabel != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              phaseLabel,
              style: TextStyle(fontSize: 12, color: theme.textColorSecondary),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (code != null) ...[
          Text(
            l10n.githubCodeInstructions,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.textColorSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.control,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code.userCode,
              key: const ValueKey('github-user-code'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textColorPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _action('github-copy-code', l10n.githubCopyCode, () async {
                await Clipboard.setData(ClipboardData(text: code.userCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.githubCodeCopied)));
              }),
              _action(
                'github-open-browser',
                l10n.githubOpenBrowser,
                account.openAuthorizationPage,
                primary: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (account.error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error(l10n, account.error!),
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
              account.busy ? null : account.signOut,
            ),
          ),
        ] else if (!account.busy)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _action(
                'profile-sign-in',
                l10n.githubSignIn,
                account.signIn,
                primary: true,
              ),
              if (account.canRetryRestore)
                _action(
                  'github-retry-restore',
                  l10n.githubRetryRestore,
                  account.restore,
                ),
            ],
          )
        else if (account.phase == AccountPhase.requesting ||
            account.phase == AccountPhase.waiting)
          Align(
            alignment: Alignment.centerLeft,
            child: _action(
              'github-cancel',
              l10n.settingsCancel,
              account.cancel,
            ),
          ),
      ],
    );
  }

  Widget _action(
    String key,
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
  }) {
    final colors = SettingsColors(theme);
    final foreground = primary ? Colors.white : theme.textColorPrimary;
    final background = primary ? theme.basePrimary : colors.control;
    return MenuItemSurface(
      key: ValueKey(key),
      theme: theme,
      backgroundColor: background,
      hoverColor: primary
          ? Color.alphaBlend(foreground.withValues(alpha: .1), background)
          : colors.hover,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: foreground,
          ),
        ),
      ),
    );
  }

  String _error(AppLocalizations l10n, AccountError error) => switch (error) {
    AccountError.notConfigured => l10n.githubNotConfigured,
    AccountError.unsupported => l10n.githubUnsupported,
    AccountError.network => l10n.githubNetworkError,
    AccountError.denied => l10n.githubDenied,
    AccountError.expired => l10n.githubExpired,
    AccountError.invalidClient ||
    AccountError.flowDisabled => l10n.githubConfigurationError,
    AccountError.rateLimited => l10n.githubRateLimited,
    AccountError.invalidResponse => l10n.githubInvalidResponse,
    AccountError.storage => l10n.githubStorageError,
    AccountError.browser => l10n.githubBrowserError,
  };
}
