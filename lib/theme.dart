import 'package:flutter/material.dart';
import 'language.dart';

class DefaultThemeColors {
  static const primary = Color(0xFF36393F);
  static const secondary = Color(0xFF2F3136);
  static const tertiary = Color(0xFF202225);
}

enum ThemeType {
  dark,   // 黑色格调
  light,  // 亮色格调
}

class AppTheme {
  final ThemeType type;
  final String nameKey;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color textColor;

  const AppTheme({
    required this.type,
    required this.nameKey,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.textColor,
  });

  String getName(LanguageProvider languageProvider) {
    return languageProvider.t(nameKey);
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
    ),
    ThemeType.light: AppTheme(
      type: ThemeType.light,
      nameKey: 'theme_light',
      primary: const Color(0xFFF5F5F5),
      secondary: const Color(0xFFE0E0E0),
      tertiary: const Color(0xFFBDBDBD),
      textColor: Colors.black,
    ),
  };

  ThemeType get currentTheme => _currentTheme;
  AppTheme get themeData => _themes[_currentTheme]!;
  List<AppTheme> get allThemes => _themes.values.toList();

  void setTheme(ThemeType themeType) {
    _currentTheme = themeType;
    notifyListeners();
  }

  void cycleTheme() {
    final themes = ThemeType.values;
    final currentIndex = themes.indexOf(_currentTheme);
    final nextIndex = (currentIndex + 1) % themes.length;
    _currentTheme = themes[nextIndex];
    notifyListeners();
  }
}