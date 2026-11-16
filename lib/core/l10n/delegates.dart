import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as sdk;
import 'package:material_ui/material_ui.dart' as material;
import '../../generated/l10n/app_localizations.dart';

/// Markdown 等依赖仍使用 SDK 控件，因此需要同时提供两套本地化代理。
const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...material.GlobalMaterialLocalizations.delegates,
  // 供仍创建 SDK Material 控件的依赖使用。
  // ignore: deprecated_member_use
  ...sdk.GlobalMaterialLocalizations.delegates,
];
