/*
 * @Description: 管理中英文界面语言、语言切换及本地化文本访问。
 * @Author: LILYGO_L
 * @Date: 2025-10-27 10:06:04
 * @LastEditTime: 2026-10-27 14:11:56
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../storage/preferences.dart';

class LanguageProvider with ChangeNotifier {
  LanguageProvider({AppPreferences? preferences}) : _preferences = preferences {
    final code = preferences?.stringValue('language', 'auto');
    _languageCode = switch (code) {
      'en' || 'zh' => code!,
      _ => 'auto',
    };
  }

  final AppPreferences? _preferences;
  String _languageCode = 'auto';

  String get languageCode => _languageCode;

  Locale? get locale => _languageCode == 'auto' ? null : Locale(_languageCode);

  void setLocale(Locale locale) {
    final isSupported = supportedLanguages.any(
      (language) => language['code'] == locale.languageCode,
    );
    final nextLanguageCode = isSupported ? locale.languageCode : 'auto';
    if (_languageCode == nextLanguageCode) return;
    _languageCode = nextLanguageCode;
    _preferences?.setValue('language', _languageCode);
    notifyListeners();
  }

  // 添加支持的语言列表
  static final List<Map<String, String>> supportedLanguages = [
    {'code': 'auto', 'name': 'Auto-detect', 'nativeName': 'Auto-detect'},
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'zh', 'name': 'Chinese', 'nativeName': '中文'},
  ];

  // 获取当前语言的显示名称
  String get currentLanguageDisplayName {
    final lang = supportedLanguages.firstWhere(
      (lang) => lang['code'] == _languageCode,
      orElse: () => supportedLanguages.first,
    );
    return lang['nativeName']!;
  }

  // 切换语言的便捷方法
  void changeLanguage(String languageCode) {
    if (languageCode == 'auto') {
      if (_languageCode == 'auto') return;
      _languageCode = 'auto';
      _preferences?.setValue('language', _languageCode);
      notifyListeners();
      return;
    }
    setLocale(Locale(languageCode));
  }

  String get currentLanguage {
    switch (_languageCode) {
      case 'zh':
        return '中文';
      default:
        return 'English';
    }
  }
}

// 便捷扩展方法，用于在任意地方访问本地化文本
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
