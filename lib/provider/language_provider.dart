// language_provider.dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class LanguageProvider with ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }

  void toggleLanguage() {
    switch (_locale.languageCode) {
      case 'zh':
        _locale = const Locale('zh');
        break;
      case 'ja':
        _locale = const Locale('ja');
        break;
      default:
        _locale = const Locale('en');
        break;
    }
    notifyListeners();
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
