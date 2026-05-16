/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-10-27 10:06:04
 * @LastEditTime: 2025-11-17 11:27:21
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';

class LanguageProvider with ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }

  // 添加支持的语言列表
  static final List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'zh', 'name': 'Chinese', 'nativeName': '中文'},
    {'code': 'ja', 'name': 'Japanese', 'nativeName': '日本語'},
  ];

  // 获取当前语言的显示名称
  String get currentLanguageDisplayName {
    final lang = supportedLanguages.firstWhere(
      (lang) => lang['code'] == _locale.languageCode,
      orElse: () => supportedLanguages.first,
    );
    return lang['nativeName']!;
  }

  // 切换语言的便捷方法
  void changeLanguage(String languageCode) {
    final newLocale = Locale(languageCode);
    if (_locale.languageCode != languageCode) {
      _locale = newLocale;
      notifyListeners();
    }
  }

  String get currentLanguage {
    switch (_locale.languageCode) {
      case 'zh':
        return '中文';
      case 'ja':
        return '日本語';
      default:
        return 'English';
    }
  }
}

// 便捷扩展方法，用于在任意地方访问本地化文本
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
