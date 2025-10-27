/*
 * @Description: None
 * @Author: LILYGO_L
<<<<<<< HEAD
 * @Date: 2025-10-25 09:15:47
 * @LastEditTime: 2025-10-27 09:38:57
=======
 * @Date: 2025-10-25 21:43:42
 * @LastEditTime: 2025-10-25 21:59:06
>>>>>>> ac2718bebcb13cbb467efbe989de293df57bc5ae
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

enum ThemeType {
  dark, // 黑色格调
  light, // 亮色格调
}

class AppTheme {
  final ThemeType type;
  final String nameKey;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color textColor;
  final Color inactiveTextColor;
  final Color iconColor;
  final Color inactiveIconColor;

  const AppTheme({
    required this.type,
    required this.nameKey,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.textColor,
    required this.inactiveTextColor,
    required this.iconColor,
    required this.inactiveIconColor,
  });

  // 注意：在调用 getName() 的地方，AppLocalizations.of(context) 可能会返回 null。
  // 在 Dart 2.12+ (空安全) 中，您可能需要进行空安全检查，
  // 比如将 AppLocalizations appLocalizations 改为 AppLocalizations? appLocalizations，
  // 或者在调用处保证 context 是有效的。
  String getName(AppLocalizations appLocalizations) {
    switch (nameKey) {
      case 'theme_dark':
        return appLocalizations.themeDark;
      case 'theme_light':
        return appLocalizations.themeLight;
      default:
        return nameKey;
    }
  }
}

class ThemeProvider with ChangeNotifier {
  ThemeType _currentTheme = ThemeType.dark;

  final Map<ThemeType, AppTheme> _themes = {
    ThemeType.dark: AppTheme(
      type: ThemeType.dark,
      nameKey: 'theme_dark',
      primary: const Color(0xFF36393F),
      secondary: const Color(0xFF2F3136),
      tertiary: const Color(0xFF202225),
      textColor: Colors.white,
      inactiveTextColor: Colors.grey,
      iconColor: Colors.white,
      inactiveIconColor: Colors.grey,
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFE0E0E0),
      tertiary: const Color(0xFFBDBDBD),
      textColor: Colors.black,
      inactiveTextColor: Colors.grey,
      iconColor: Colors.black,
      inactiveIconColor: Colors.grey,
    ),
  };

  ThemeType get currentTheme => _currentTheme;
  AppTheme get themeData => _themes[_currentTheme]!;
  List<AppTheme> get allThemes => _themes.values.toList();

  void cycleTheme() {
    final nextTheme = (_currentTheme.index + 1) % ThemeType.values.length;
    _currentTheme = ThemeType.values[nextTheme];
    notifyListeners();
  }

  void setTheme(ThemeType themeType) {
    _currentTheme = themeType;
    notifyListeners();
  }
}
