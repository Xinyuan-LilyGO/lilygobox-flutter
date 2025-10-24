import 'package:flutter/material.dart';

enum LanguageType {
  chinese,
  english,
}

class LanguageData {
  final LanguageType type;
  final String name;
  final String code;
  final Map<String, String> translations;

  const LanguageData({
    required this.type,
    required this.name,
    required this.code,
    required this.translations,
  });

  String translate(String key) {
    return translations[key] ?? key;
  }
}

class LanguageProvider with ChangeNotifier {
  LanguageType _currentLanguage = LanguageType.chinese;

  final Map<LanguageType, LanguageData> _languages = {
    LanguageType.chinese: LanguageData(
      type: LanguageType.chinese,
      name: '中文',
      code: 'zh',
      translations: {
        'app_title': 'Ciallo',
        'theme_dark': '黑色格调',
        'theme_light': '亮色格调',
        'current_theme': '当前主题',
        'switch_theme': '切换主题',
        'language': '语言',
        'switch_language': '切换语言',
        'minimize': '最小化',
        'maximize': '最大化',
        'restore': '还原',
        'close': '关闭',
        'app_content': '应用程序内容区域',
        'custom_title_bar': '自定义标题栏',
        'chinese': '中文',
        'english': '英文',
        'window_controls': '窗口控制',
      },
    ),
    LanguageType.english: LanguageData(
      type: LanguageType.english,
      name: 'English',
      code: 'en',
      translations: {
        'app_title': 'Ciallo',
        'theme_dark': 'Dark Theme',
        'theme_light': 'Light Theme',
        'current_theme': 'Current Theme',
        'switch_theme': 'Switch Theme',
        'language': 'Language',
        'switch_language': 'Switch Language',
        'minimize': 'Minimize',
        'maximize': 'Maximize',
        'restore': 'Restore',
        'close': 'Close',
        'app_content': 'Application Content Area',
        'custom_title_bar': 'Custom Title Bar',
        'chinese': 'Chinese',
        'english': 'English',
        'window_controls': 'Window Controls',
      },
    ),
  };

  LanguageType get currentLanguage => _currentLanguage;
  LanguageData get languageData => _languages[_currentLanguage]!;
  List<LanguageData> get allLanguages => _languages.values.toList();

  void setLanguage(LanguageType languageType) {
    _currentLanguage = languageType;
    notifyListeners();
  }

  void cycleLanguage() {
    final languages = LanguageType.values;
    final currentIndex = languages.indexOf(_currentLanguage);
    final nextIndex = (currentIndex + 1) % languages.length;
    _currentLanguage = languages[nextIndex];
    notifyListeners();
  }

  String t(String key) {
    return languageData.translate(key);
  }
}