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
import 'material_palette.dart';

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
    ThemeType.dark: MaterialPalette.create(ThemeType.dark),
    ThemeType.light: MaterialPalette.create(ThemeType.light),
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
