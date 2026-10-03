/*
 * @Description: 配置读写失败时显示可重试提示，避免保存失败被误认为成功。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 20:29:43
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/language_provider.dart';
import '../../core/storage/preferences.dart';
import '../../core/theme/provider.dart';
import '../../core/widgets/action_button.dart';
import '../../core/window/provider.dart';

class PreferencesNotice extends StatelessWidget {
  const PreferencesNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferences>();
    if (preferences.error == null) return const SizedBox.shrink();
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    return Material(
      color: theme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                preferences.error == PreferencesError.read
                    ? l10n.preferencesReadError
                    : l10n.preferencesWriteError,
                style: TextStyle(color: theme.textColorPrimary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppActionButton(
                  theme: theme,
                  label: l10n.preferencesRetry,
                  onPressed: preferences.retry,
                  fontSize: 12,
                ),
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.windows ||
                        defaultTargetPlatform == TargetPlatform.linux ||
                        defaultTargetPlatform == TargetPlatform.macOS))
                  AppActionButton(
                    theme: theme,
                    label: l10n.preferencesExitWithoutSaving,
                    onPressed: () => context.read<WindowProvider>().close(
                      discardUnsaved: true,
                    ),
                    fontSize: 12,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
