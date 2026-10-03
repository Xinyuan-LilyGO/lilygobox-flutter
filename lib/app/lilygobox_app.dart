/*
 * @Description: 配置应用根组件、本地化资源和主窗口内容。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-04 00:20:00
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
import 'navigation/dialog_observer.dart';
import 'widgets/preferences_notice.dart';
import 'widgets/title_bar.dart';
import 'widgets/tray_sync.dart';
import 'widgets/window_frame.dart';
import 'widgets/window_page_stack.dart';
import 'widgets/window_resize_overlay.dart';

class LilygoBoxApp extends StatefulWidget {
  const LilygoBoxApp({super.key});

  @override
  State<LilygoBoxApp> createState() => _LilygoBoxAppState();
}

class _LilygoBoxAppState extends State<LilygoBoxApp> {
  final _dialogs = AppDialogObserver();

  @override
  void dispose() {
    _dialogs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<PackageInfoProvider>().initializePackageInfo());
    });

    return Consumer3<ThemeProvider, WindowProvider, LanguageProvider>(
      builder:
          (context, themeProvider, windowProvider, languageProvider, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: languageProvider.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              navigatorObservers: [_dialogs],
              // 标题栏位于 Navigator 上方，弹窗只覆盖下方内容区。
              builder: (context, navigator) => TraySync(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Column(
                    children: [
                      Expanded(
                        child: AppWindowFrame(
                          theme: themeProvider.themeData,
                          isMaximized: windowProvider.isMaximized,
                          child: Overlay.wrap(
                            // 独立 Overlay 为标题栏悬停提示提供显示空间。
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    ValueListenableBuilder<bool>(
                                      valueListenable: _dialogs.hasDialog,
                                      builder: (context, blocked, _) =>
                                          AppTitleBar(
                                            navigationEnabled: !blocked,
                                          ),
                                    ),
                                    Expanded(
                                      child: ClipRect(child: navigator!),
                                    ),
                                  ],
                                ),
                                const WindowResizeOverlay(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const PreferencesNotice(),
                    ],
                  ),
                ),
              ),
              home: const Scaffold(
                backgroundColor: Colors.transparent,
                body: Column(children: [WindowPageStack()]),
              ),
            );
          },
    );
  }
}
