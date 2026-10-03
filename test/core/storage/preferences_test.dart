/*
 * @Description: 验证配置重启恢复、串行写入、异常重试、无效值回退及设备资料保留。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 20:29:43
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';

class MemoryPreferencesStorage implements PreferencesStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? gate;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read failed');
    return value;
  }

  @override
  Future<void> write(String data) async {
    writes++;
    await gate?.future;
    if (failWrite) throw StateError('write failed');
    value = data;
  }
}

void main() {
  testWidgets('changes save automatically after a short quiet interval', (
    tester,
  ) async {
    final storage = MemoryPreferencesStorage();
    final preferences = await AppPreferences.load(storage: storage);
    addTearDown(preferences.dispose);
    preferences.setValue('sidebarWidth', 220.0);
    await tester.pump(const Duration(milliseconds: 150));
    preferences.setValue('sidebarWidth', 280.0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(storage.writes, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(storage.writes, 1);
    expect(jsonDecode(storage.value!)['sidebarWidth'], 280.0);
  });

  test(
    'preferences survive recreation and reset preserves saved devices',
    () async {
      final storage = MemoryPreferencesStorage();
      final preferences = await AppPreferences.load(storage: storage);
      final theme = ThemeProvider(preferences: preferences);
      final language = LanguageProvider(preferences: preferences);
      final shell = AppShellProvider(preferences: preferences);
      final split = SplitViewProvider(preferences: preferences);
      final devices = DeviceManagerProvider(preferences: preferences);
      theme.setTheme(ThemeType.light);
      language.changeLanguage('zh');
      shell.resizeSidebar(310, maxWidth: 360);
      shell.toggleSidebar();
      split.updateSplitWidth(345);
      preferences.setValue('settingsSidebarWidth', 260.0);
      devices.addDevice('T-Display-P4');
      devices.addDevice('T-Display-P4');
      expect(await preferences.flush(), isTrue);
      for (final provider in [
        theme,
        language,
        shell,
        split,
        devices,
        preferences,
      ]) {
        provider.dispose();
      }

      final restored = await AppPreferences.load(storage: storage);
      final restoredTheme = ThemeProvider(preferences: restored);
      final restoredLanguage = LanguageProvider(preferences: restored);
      final restoredShell = AppShellProvider(preferences: restored);
      final restoredSplit = SplitViewProvider(preferences: restored);
      final restoredDevices = DeviceManagerProvider(preferences: restored);
      expect(restoredTheme.currentTheme, ThemeType.light);
      expect(restoredTheme.themeData.type, ThemeType.light);
      expect(restoredLanguage.locale.languageCode, 'zh');
      expect(restoredShell.sidebarWidth, 310);
      expect(restoredShell.isSidebarVisible, isFalse);
      expect(restoredSplit.splitWidth, 345);
      expect(restored.doubleValue('settingsSidebarWidth', 212, 176, 300), 260);
      expect(restoredDevices.addedDevices, ['T-Display-P4']);

      restoredTheme.setTheme(ThemeType.dark);
      restoredLanguage.changeLanguage('en');
      restoredShell.resetLayout();
      restoredSplit.resetSplitWidth();
      expect(await restored.flush(), isTrue);
      final saved = jsonDecode(storage.value!);
      expect(saved['theme'], 'dark');
      expect(saved['language'], 'en');
      expect(saved['sidebarWidth'], AppShellProvider.defaultSidebarWidth);
      expect(saved['devices'], ['T-Display-P4']);
      restoredDevices.removeDevice('T-Display-P4');
      await restored.flush();
      expect(jsonDecode(storage.value!)['devices'], isEmpty);
      for (final provider in [
        restoredTheme,
        restoredLanguage,
        restoredShell,
        restoredSplit,
        restoredDevices,
        restored,
      ]) {
        provider.dispose();
      }
    },
  );

  test('pending writes are coalesced and newest snapshot wins', () async {
    final storage = MemoryPreferencesStorage()..gate = Completer<void>();
    final preferences = await AppPreferences.load(storage: storage);
    addTearDown(preferences.dispose);
    preferences.setValue('sidebarWidth', 200.0);
    for (var width = 201; width <= 310; width++) {
      preferences.setValue('sidebarWidth', width.toDouble());
    }
    preferences.setValue('language', 'zh');
    storage.gate!.complete();
    expect(await preferences.flush(), isTrue);
    expect(jsonDecode(storage.value!)['sidebarWidth'], 310);
    expect(jsonDecode(storage.value!)['language'], 'zh');
    expect(storage.writes, lessThanOrEqualTo(2));
  });

  test('failed writes retain latest changes for retry', () async {
    final storage = MemoryPreferencesStorage()..failWrite = true;
    final preferences = await AppPreferences.load(storage: storage);
    addTearDown(preferences.dispose);
    preferences.setValue('theme', 'light');
    expect(await preferences.flush(), isFalse);
    expect(preferences.error, PreferencesError.write);
    storage.failWrite = false;
    await preferences.retry();
    expect(preferences.error, isNull);
    expect(jsonDecode(storage.value!)['theme'], 'light');
  });

  test('read failure never overwrites unread configuration', () async {
    final storage = MemoryPreferencesStorage()
      ..value = '{"language":"zh","devices":["T-Display-P4"]}'
      ..failRead = true;
    final preferences = await AppPreferences.load(storage: storage);
    addTearDown(preferences.dispose);
    preferences.setValue('theme', 'light');
    expect(await preferences.flush(), isFalse);
    expect(storage.writes, 0);
    storage.failRead = false;
    await preferences.retry();
    expect(jsonDecode(storage.value!), {
      'language': 'zh',
      'devices': ['T-Display-P4'],
      'theme': 'light',
    });
  });

  test('invalid values fall back or clamp without crashing startup', () async {
    final storage = MemoryPreferencesStorage()
      ..value = jsonEncode({
        'theme': 'unknown',
        'language': 'xx',
        'sidebarWidth': -100,
        'sidebarVisible': 'true',
        'splitWidth': 'broken',
        'devices': ['P4', '', 42, 'P4'],
      });
    final preferences = await AppPreferences.load(storage: storage);
    final theme = ThemeProvider(preferences: preferences);
    final language = LanguageProvider(preferences: preferences);
    final shell = AppShellProvider(preferences: preferences);
    expect(theme.currentTheme, ThemeType.dark);
    expect(language.locale.languageCode, 'en');
    expect(shell.sidebarWidth, AppShellProvider.minSidebarWidth);
    expect(shell.isSidebarVisible, isTrue);
    expect(preferences.doubleValue('splitWidth', 300, 100, 1200), 300);
    expect(preferences.stringList('devices'), ['P4']);
    for (final provider in [theme, language, shell, preferences]) {
      provider.dispose();
    }
    storage.value = 'invalid json';
    final corrupted = await AppPreferences.load(storage: storage);
    expect(corrupted.error, PreferencesError.read);
    corrupted.setValue('language', 'zh');
    expect(await corrupted.flush(), isFalse);
    expect(storage.value, 'invalid json');
    corrupted.dispose();
  });
}
