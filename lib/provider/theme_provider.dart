/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-25 09:15:47
 * @LastEditTime: 2025-11-05 16:31:52
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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
  final Color textColorPrimary;
  final Color textColorSecondary;
  final Color textColorTertiary;
  final Color primaryTextHoverColor;
  final Color primaryTextSelectedColor;
  final Color tertiarytextBackgroundColor;
  final Color tertiaryTextHoverColor;
  final Color tertiaryTextHighlightColor;
  final Color tertiaryTextSplashColor;
  final Color appTitleTextColor;
  final Color inactiveTextColor;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color iconHoverColor;
  final Color iconHighlightColor;
  final Color iconSplashColor;
  final Color inactiveIconColor;
  final Color sidebarIconColor;
  final Color sidebarSelectedIconColor;
  final Color sidebarHoverIconColor;
  final Color sidebarHoverIconColor2;
  final Color sidebarIconBackgroundColor;
  final Color sidebarIconHighlightColor;
  final Color sidebarIconSplashColor;
  final Color sidebarIndicatorColor;
  final Color appTitleBarIconBackgroundColor;
  final Color dividerColor;
  final Color dividerColor2;

  const AppTheme({
    required this.type,
    required this.nameKey,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.textColorPrimary,
    required this.textColorSecondary,
    required this.textColorTertiary,
    required this.primaryTextHoverColor,
    required this.primaryTextSelectedColor,
    required this.tertiarytextBackgroundColor,
    required this.tertiaryTextHoverColor,
    required this.tertiaryTextHighlightColor,
    required this.tertiaryTextSplashColor,
    required this.appTitleTextColor,
    required this.inactiveTextColor,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.iconHoverColor,
    required this.iconHighlightColor,
    required this.iconSplashColor,
    required this.inactiveIconColor,
    required this.sidebarIconColor,
    required this.sidebarSelectedIconColor,
    required this.sidebarHoverIconColor,
    required this.sidebarHoverIconColor2,
    required this.sidebarIconBackgroundColor,
    required this.sidebarIconHighlightColor,
    required this.sidebarIconSplashColor,
    required this.sidebarIndicatorColor,
    required this.appTitleBarIconBackgroundColor,
    required this.dividerColor,
    required this.dividerColor2,
  });

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
      primary: const Color.fromARGB(255, 25, 25, 25),
      secondary: const Color.fromARGB(255, 45, 45, 45),
      tertiary: const Color.fromARGB(255, 65, 65, 65),
      textColorPrimary: const Color.fromARGB(255, 230, 230, 230),
      textColorSecondary: const Color.fromARGB(255, 220, 220, 220),
      textColorTertiary: const Color.fromARGB(255, 150, 150, 150),
      primaryTextHoverColor: const Color.fromARGB(255, 40, 40, 40),
      primaryTextSelectedColor: const Color.fromARGB(255, 60, 60, 60),
      tertiarytextBackgroundColor: const Color.fromARGB(255, 70, 70, 70),
      tertiaryTextHoverColor: const Color.fromARGB(255, 100, 100, 100),
      tertiaryTextHighlightColor: const Color.fromARGB(100, 120, 120, 120),
      tertiaryTextSplashColor: const Color.fromARGB(100, 170, 170, 170),
      appTitleTextColor: const Color.fromARGB(255, 215, 215, 215),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 215, 215, 215),
      iconBackgroundColor: const Color.fromARGB(255, 80, 80, 80),
      iconHoverColor: const Color.fromARGB(255, 120, 120, 120),
      iconHighlightColor: const Color.fromARGB(255, 130, 130, 130),
      iconSplashColor: const Color.fromARGB(255, 180, 180, 180),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 215, 215, 215),
      sidebarSelectedIconColor: const Color.fromARGB(255, 126, 109, 202),
      sidebarHoverIconColor: const Color.fromARGB(255, 120, 120, 120),
      sidebarHoverIconColor2: const Color.fromARGB(255, 100, 177, 76),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 55, 55, 55),
      sidebarIconHighlightColor: const Color.fromARGB(100, 130, 130, 130),
      sidebarIconSplashColor: const Color.fromARGB(100, 180, 180, 180),
      sidebarIndicatorColor: const Color.fromARGB(255, 200, 200, 200),
      appTitleBarIconBackgroundColor: Colors.grey.withValues(alpha: 0.2),
      dividerColor: const Color.fromARGB(255, 100, 100, 100),
      dividerColor2: const Color.fromARGB(255, 126, 109, 202),
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFBDBDBD),
      tertiary: const Color(0xFFE0E0E0),
      textColorPrimary: const Color.fromARGB(255, 25, 25, 25),
      textColorSecondary: const Color.fromARGB(255, 35, 35, 35),
      textColorTertiary: const Color.fromARGB(255, 105, 105, 105),
      primaryTextHoverColor: const Color.fromARGB(255, 215, 215, 215),
      primaryTextSelectedColor: const Color.fromARGB(255, 195, 195, 195),
      tertiarytextBackgroundColor: const Color.fromARGB(255, 175, 175, 175),
      tertiaryTextHoverColor: const Color.fromARGB(255, 115, 115, 115),
      tertiaryTextHighlightColor: const Color.fromARGB(100, 130, 130, 130),
      tertiaryTextSplashColor: const Color.fromARGB(100, 180, 180, 180),
      appTitleTextColor: const Color.fromARGB(255, 50, 50, 50),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 40, 40, 40),
      iconBackgroundColor: const Color.fromARGB(255, 175, 175, 175),
      iconHoverColor: const Color.fromARGB(255, 135, 135, 135),
      iconHighlightColor: const Color.fromARGB(255, 125, 125, 125),
      iconSplashColor: const Color.fromARGB(255, 75, 75, 75),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 40, 40, 40),
      sidebarSelectedIconColor: const Color.fromARGB(255, 182, 168, 255),
      sidebarHoverIconColor: const Color.fromARGB(255, 155, 155, 155),
      sidebarHoverIconColor2: const Color.fromARGB(255, 125, 191, 105),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 200, 200, 200),
      sidebarIconHighlightColor: const Color.fromARGB(100, 150, 150, 150),
      sidebarIconSplashColor: const Color.fromARGB(100, 130, 130, 130),
      sidebarIndicatorColor: const Color.fromARGB(255, 40, 40, 40),
      appTitleBarIconBackgroundColor: Colors.grey.withValues(alpha: 0.2),
      dividerColor: const Color.fromARGB(255, 80, 80, 80),
      dividerColor2: const Color.fromARGB(255, 105, 105, 105),
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
