/*
 * @Description: 配置应用根组件、本地化资源和主窗口内容。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info/package_info_provider.dart';
import '../core/l10n/language_provider.dart';
import '../core/theme/provider.dart';
import '../core/window/provider.dart';
import '../generated/l10n/app_localizations.dart';
import 'widgets/window_frame.dart';

class LilygoBoxApp extends StatelessWidget {
  const LilygoBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<PackageInfoProvider>().initializePackageInfo());
    });

    return Consumer3<ThemeProvider, WindowProvider, LanguageProvider>(
      builder: (context, themeProvider, windowProvider, languageProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: languageProvider.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: AppWindowFrame(
              theme: themeProvider.themeData,
              isMaximized: windowProvider.isMaximized,
            ),
          ),
        );
      },
    );
  }
}
