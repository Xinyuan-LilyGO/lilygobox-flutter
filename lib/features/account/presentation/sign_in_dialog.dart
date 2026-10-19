import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/context_menu/text_selection_menu.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/definition.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../domain/models.dart';
import '../state/provider.dart';

// 同一窗口的登录框在请求失败和关闭动画期间也不允许重复打开。
final _signInDialogs = Expando<bool>();

Future<void> showAccountSignIn(
  BuildContext context, {
  required AppTheme theme,
  required AccountProvider account,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_signInDialogs[navigator] == true ||
      account.busy ||
      account.user != null) {
    return;
  }
  _signInDialogs[navigator] = true;
  final route = DialogRoute<void>(
    context: context,
    builder: (_) => _AccountSignInDialog(theme: theme, account: account),
  );
  try {
    unawaited(account.signIn());
    await navigator.push(route);
  } finally {
    account.cancel();
    await route.completed;
    _signInDialogs[navigator] = false;
  }
}

class _AccountSignInDialog extends StatefulWidget {
  const _AccountSignInDialog({required this.theme, required this.account});

  final AppTheme theme;
  final AccountProvider account;

  @override
  State<_AccountSignInDialog> createState() => _AccountSignInDialogState();
}

class _AccountSignInDialogState extends State<_AccountSignInDialog>
    with SingleTickerProviderStateMixin {
  bool _copied = false;
  Widget? _lastDialog;
  late AccountPhase _contentPhase;
  late final AnimationController _contentTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final CurvedAnimation _contentCurve = CurvedAnimation(
    parent: _contentTransition,
    curve: Curves.linear,
  );

  @override
  void initState() {
    super.initState();
    _contentPhase = widget.account.phase;
    widget.account.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (_contentPhase != widget.account.phase) {
      _contentPhase = widget.account.phase;
      if ((widget.account.phase == AccountPhase.requesting ||
              widget.account.phase == AccountPhase.waiting) &&
          _lastDialog != null &&
          ModalRoute.of(context)?.isCurrent == true) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _contentTransition.value = 1;
        } else {
          _contentTransition.forward(from: 0);
        }
      }
    }
    if (widget.account.phase != AccountPhase.signedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    widget.account.removeListener(_changed);
    _contentCurve.dispose();
    _contentTransition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.account,
    builder: (context, _) {
      // 完成授权和退出时保留原画面，避免清空验证码后闪现空框或重新播放渐变。
      if (_lastDialog != null &&
          (ModalRoute.of(context)?.isCurrent == false ||
              widget.account.phase == AccountPhase.completing ||
              widget.account.phase == AccountPhase.signedIn)) {
        return _lastDialog!;
      }
      final account = widget.account;
      final theme = widget.theme;
      final l10n = context.l10n;
      final code = account.authorization;
      final status = switch (account.phase) {
        AccountPhase.requesting => l10n.githubRequesting,
        AccountPhase.waiting => l10n.githubWaiting,
        AccountPhase.completing => l10n.githubCompleting,
        _ => null,
      };
      return _lastDialog = FadeTransition(
        opacity: _contentCurve,
        child: AppDialog(
          theme: theme,
          title: l10n.githubSignIn,
          constraints: const BoxConstraints(maxWidth: 408),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textColorSecondary,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.githubSignInDialogDescription),
                    if (code != null) ...[
                      const SizedBox(height: 12),
                      Text(l10n.githubCodeInstructions),
                      const SizedBox(height: 12),
                      SelectableText(
                        code.userCode,
                        key: const ValueKey('github-user-code'),
                        contextMenuBuilder: AppTextSelectionMenu.build,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: theme.textColorPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _button(
                        'github-copy-code',
                        _copied ? l10n.githubCodeCopied : l10n.githubCopyCode,
                        () async {
                          await Clipboard.setData(
                            ClipboardData(text: code.userCode),
                          );
                          if (mounted) setState(() => _copied = true);
                        },
                      ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: 12),
                      Semantics(liveRegion: true, child: Text(status)),
                    ],
                    if (account.error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          accountErrorText(l10n, account.error!),
                          key: const ValueKey('github-error'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            _button(
              'github-cancel',
              account.busy ? l10n.settingsCancel : l10n.closeWindow,
              () => Navigator.of(context).pop(),
            ),
            if (code != null)
              _button(
                'github-open-browser',
                l10n.githubOpenBrowser,
                account.openAuthorizationPage,
                primary: true,
              ),
            if (!account.busy &&
                account.user == null &&
                account.configured &&
                account.supported)
              _button('github-retry-sign-in', l10n.githubSignIn, () {
                setState(() => _copied = false);
                unawaited(account.signIn());
              }, primary: true),
          ],
        ),
      );
    },
  );

  Widget _button(
    String id,
    String label,
    VoidCallback onPressed, {
    bool primary = false,
  }) => AppActionButton(
    key: ValueKey(id),
    theme: widget.theme,
    label: label,
    onPressed: onPressed,
    primary: primary,
    settingBackground: !primary,
    fontSize: 12,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    borderRadius: BorderRadius.circular(8),
  );
}

String accountErrorText(AppLocalizations l10n, AccountError error) =>
    switch (error) {
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
