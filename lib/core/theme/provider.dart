/*
 * @Description: 维护深浅主题配色，统一驱动主题渐变并支持减少动画。
 * @Author: LILYGO_L
 * @Date: 2025-10-25 09:15:47
 * @LastEditTime: 2026-10-03 20:29:43
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../storage/preferences.dart';
import 'definition.dart';

export 'definition.dart';

class ThemeProvider with ChangeNotifier {
  ThemeProvider({TickerProvider? vsync, AppPreferences? preferences})
    : _preferences = preferences {
    _currentTheme = preferences?.stringValue('theme', 'dark') == 'light'
        ? ThemeType.light
        : ThemeType.dark;
    if (vsync != null) {
      _transition = AnimationController(
        vsync: vsync,
        duration: transitionDuration,
        value: 1,
      )..addListener(_onTransition);
    }
  }

  final AppPreferences? _preferences;

  static const transitionDuration = Duration(milliseconds: 180);
  AnimationController? _transition;
  AppTheme? _displayedTheme;
  AppTheme? _transitionStart;
  bool _disableAnimations = false;

  void _onTransition() {
    _displayedTheme = AppTheme.lerp(
      _transitionStart!,
      _themes[_currentTheme]!,
      Curves.easeInOut.transform(_transition!.value),
    );
    notifyListeners();
  }

  void setDisableAnimations(bool value) {
    _disableAnimations = value;
    if (value && (_transition?.isAnimating ?? false)) {
      _transition!.value = 1;
    }
  }

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
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 80, 80, 80),
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
      secondaryTextHoverColorAlt: const Color.fromARGB(255, 180, 180, 180),
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
      dividerColor: const Color.fromARGB(255, 80, 80, 80),
      dividerColorNormal: const Color(0xFF7963C6),
      basePrimary: const Color(0xFF7963C6),
      baseSecondary: const Color(0xFF7963C6),
      baseTertiary: const Color(0xFF7963C6),
    ),
  };

  ThemeType get currentTheme => _currentTheme;
  AppTheme get themeData => _displayedTheme ?? _themes[_currentTheme]!;
  List<AppTheme> get allThemes => _themes.values.toList();

  void cycleTheme() {
    final nextTheme = (_currentTheme.index + 1) % ThemeType.values.length;
    setTheme(ThemeType.values[nextTheme]);
  }

  void setTheme(ThemeType themeType) {
    if (_currentTheme == themeType) return;
    // 连续切换时从当前屏幕配色接续，不跳回上一次主题端点。
    _transitionStart = themeData;
    _currentTheme = themeType;
    _preferences?.setValue('theme', themeType.name);
    if (_transition == null || _disableAnimations) {
      _transition?.stop();
      _displayedTheme = _themes[themeType];
    } else {
      _transition!.forward(from: 0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _transition?.dispose();
    super.dispose();
  }
}
