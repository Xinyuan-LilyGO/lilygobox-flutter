/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-25 09:15:47
 * @LastEditTime: 2025-11-24 14:38:24
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
  final Color secondaryTextHoverColor;
  final Color secondaryTextHoverColor_2;
  final Color secondaryTextSelectedColor;
  final Color secondaryTextBackgroundColor;
  final Color tertiaryTextBackgroundColor;
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
  final Color sidebarHoverIconColor;
  final Color sidebarHoverIconColor2;
  final Color sidebarIconBackgroundColor;
  final Color sidebarIndicatorColor;
  final Color appTitleBarIconBackgroundColor;
  final Color dividerColor;
  final Color dividerColorNormal;
  final Color basePrimary;
  final Color baseSecondary;
  final Color baseTertiary;

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
    required this.secondaryTextBackgroundColor,
    required this.secondaryTextHoverColor,
    required this.secondaryTextHoverColor_2,
    required this.secondaryTextSelectedColor,
    required this.tertiaryTextBackgroundColor,
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
    required this.sidebarHoverIconColor,
    required this.sidebarHoverIconColor2,
    required this.sidebarIconBackgroundColor,
    required this.sidebarIndicatorColor,
    required this.appTitleBarIconBackgroundColor,
    required this.dividerColor,
    required this.dividerColorNormal,
    required this.basePrimary,
    required this.baseSecondary,
    required this.baseTertiary,
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
      secondaryTextBackgroundColor: const Color.fromARGB(255, 60, 60, 60),
      secondaryTextHoverColor: const Color.fromARGB(255, 60, 60, 60),
      secondaryTextHoverColor_2: const Color.fromARGB(255, 80, 80, 80),
      secondaryTextSelectedColor: const Color.fromARGB(255, 80, 80, 80),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 40, 40, 40),
      tertiaryTextHoverColor: const Color.fromARGB(255, 50, 50, 50),
      tertiaryTextHighlightColor: const Color.fromARGB(255, 80, 80, 80),
      tertiaryTextSplashColor: const Color.fromARGB(255, 60, 60, 60),
      appTitleTextColor: const Color.fromARGB(255, 215, 215, 215),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 215, 215, 215),
      iconBackgroundColor: const Color.fromARGB(255, 80, 80, 80),
      iconHoverColor: const Color.fromARGB(255, 120, 120, 120),
      iconHighlightColor: const Color.fromARGB(255, 130, 130, 130),
      iconSplashColor: const Color.fromARGB(255, 180, 180, 180),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 215, 215, 215),
      sidebarHoverIconColor: const Color.fromARGB(255, 120, 120, 120),
      sidebarHoverIconColor2: const Color.fromARGB(255, 100, 177, 76),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 55, 55, 55),
      sidebarIndicatorColor: const Color.fromARGB(255, 200, 200, 200),
      appTitleBarIconBackgroundColor: Colors.grey.withValues(alpha: 0.2),
      dividerColor: const Color.fromARGB(255, 100, 100, 100),
      dividerColorNormal: const Color.fromARGB(255, 126, 109, 202),
      basePrimary: const Color.fromARGB(255, 126, 109, 202),
      baseSecondary: const Color.fromARGB(255, 126, 109, 202),
      baseTertiary: const Color.fromARGB(255, 145, 127, 221),
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFE0E0E0),
      tertiary: const Color(0xFFBDBDBD),
      textColorPrimary: const Color.fromARGB(255, 25, 25, 25),
      textColorSecondary: const Color.fromARGB(255, 35, 35, 35),
      textColorTertiary: const Color.fromARGB(255, 105, 105, 105),
      primaryTextHoverColor: const Color.fromARGB(255, 215, 215, 215),
      primaryTextSelectedColor: const Color.fromARGB(255, 195, 195, 195),
      secondaryTextBackgroundColor: const Color.fromARGB(255, 190, 190, 190),
      secondaryTextHoverColor: const Color.fromARGB(255, 200, 200, 200),
      secondaryTextHoverColor_2: const Color.fromARGB(255, 180, 180, 180),
      secondaryTextSelectedColor: const Color.fromARGB(255, 180, 180, 180),
      tertiaryTextBackgroundColor: const Color.fromARGB(255, 160, 160, 160),
      tertiaryTextHoverColor: const Color.fromARGB(255, 180, 180, 180),
      tertiaryTextHighlightColor: const Color.fromARGB(100, 200, 200, 200),
      tertiaryTextSplashColor: const Color.fromARGB(100, 210, 210, 210),
      appTitleTextColor: const Color.fromARGB(255, 50, 50, 50),
      inactiveTextColor: Colors.grey,
      iconColor: const Color.fromARGB(255, 40, 40, 40),
      iconBackgroundColor: const Color.fromARGB(255, 200, 200, 200),
      iconHoverColor: const Color.fromARGB(255, 180, 180, 180),
      iconHighlightColor: const Color.fromARGB(255, 160, 160, 160),
      iconSplashColor: const Color.fromARGB(255, 150, 150, 150),
      inactiveIconColor: Colors.grey,
      sidebarIconColor: const Color.fromARGB(255, 40, 40, 40),
      sidebarHoverIconColor: const Color.fromARGB(255, 170, 170, 170),
      sidebarHoverIconColor2: const Color.fromARGB(255, 125, 191, 105),
      sidebarIconBackgroundColor: const Color.fromARGB(255, 200, 200, 200),
      sidebarIndicatorColor: const Color.fromARGB(255, 40, 40, 40),
      appTitleBarIconBackgroundColor: Colors.grey.withValues(alpha: 0.2),
      dividerColor: const Color.fromARGB(255, 80, 80, 80),
      dividerColorNormal: const Color.fromARGB(255, 182, 168, 255),
      basePrimary: const Color.fromARGB(255, 182, 168, 255),
      baseSecondary: const Color.fromARGB(255, 182, 168, 255),
      baseTertiary: const Color.fromARGB(255, 182, 168, 255),
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
