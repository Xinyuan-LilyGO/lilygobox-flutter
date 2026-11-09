/*
 * @Description: 验证设置工具只接受受支持的应用设置和值域。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 10:59:54
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/settings_tool_handler.dart';

class _MemoryPreferences implements PreferencesStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applies supported theme and layout settings', () async {
    final preferences = await AppPreferences.load(
      storage: _MemoryPreferences(),
    );
    final theme = ThemeProvider(preferences: preferences);
    final language = LanguageProvider(preferences: preferences);
    final shell = AppShellProvider(preferences: preferences);
    final splitView = SplitViewProvider(preferences: preferences);
    final handler = SettingsToolHandler(
      preferences: preferences,
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
    );

    await handler.execute('set_theme', {'theme': 'light'});
    await handler.execute('set_language', {'language': 'zh'});
    await handler.execute('set_sidebar_width', {'width': 240});
    await handler.execute('set_content_split_width', {'width': 420});

    expect(theme.currentTheme, ThemeType.light);
    expect(language.languageCode, 'zh');
    expect(shell.sidebarWidth, 240);
    expect(splitView.splitWidth, 420);
    await preferences.flush();
    theme.dispose();
    language.dispose();
    shell.dispose();
    splitView.dispose();
    preferences.dispose();
  });

  test('rejects unsupported values without changing settings', () async {
    final preferences = await AppPreferences.load(
      storage: _MemoryPreferences(),
    );
    final theme = ThemeProvider(preferences: preferences);
    final handler = SettingsToolHandler(
      preferences: preferences,
      theme: theme,
      language: LanguageProvider(preferences: preferences),
      shell: AppShellProvider(preferences: preferences),
      splitView: SplitViewProvider(preferences: preferences),
    );

    await expectLater(
      handler.execute('set_sidebar_width', {'width': 900}),
      throwsFormatException,
    );
    await expectLater(
      handler.execute('set_theme', {'theme': 'unknown'}),
      throwsFormatException,
    );
    expect(theme.currentTheme, ThemeProvider.defaultTheme);
    theme.dispose();
    preferences.dispose();
  });
}
