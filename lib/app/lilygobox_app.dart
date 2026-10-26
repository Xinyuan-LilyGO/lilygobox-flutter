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

import '../core/app_info/app_update_provider.dart';
import '../core/app_info/app_update_service.dart';
import '../core/app_info/package_info_provider.dart';
import '../core/l10n/language_provider.dart';
import '../core/theme/material_palette.dart';
import '../core/theme/provider.dart';
import '../core/widgets/app_scroll_behavior.dart';
import '../core/window/provider.dart';
import '../features/settings/presentation/widgets/about_content.dart';
import '../generated/l10n/app_localizations.dart';
import 'bootstrap/startup.dart';
import 'bootstrap/startup_presentation.dart';
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  // 完整 ThemeData 只创建两次，不在渐变的每一帧重新生成控件默认主题。
  final _materialThemes = {
    for (final type in ThemeType.values)
      type: ThemeData(
        useMaterial3: true,
        colorScheme: MaterialPalette.create(type).materialColors,
      ),
  };

  @override
  void dispose() {
    _dialogs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startup = StartupPresentation.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<PackageInfoProvider>().initializePackageInfo());
    });

    // 根组件只监听目标主题；中间配色帧由实际需要变色的组件监听。
    final themeType = context.select<ThemeProvider, ThemeType>(
      (provider) => provider.currentTheme,
    );
    return Consumer2<WindowProvider, LanguageProvider>(
      builder: (context, windowProvider, languageProvider, child) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scrollBehavior: const AppScrollBehavior(),
          theme: _materialThemes[themeType],
          // 内置控件与自定义配色采用相同的时间和曲线。
          themeAnimationDuration: ThemeProvider.transitionDuration,
          themeAnimationCurve: Curves.easeInOut,
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
                    child: Consumer<ThemeProvider>(
                      // 渐变只更新窗口底色，内部导航树保留为稳定 child。
                      builder: (context, theme, child) => AppWindowFrame(
                        theme: theme.themeData,
                        isMaximized: windowProvider.isMaximized,
                        child: child!,
                      ),
                      child: Overlay.wrap(
                        // 独立 Overlay 为标题栏悬停提示提供显示空间。
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: _dialogs.hasDialog,
                                  builder: (context, blocked, _) => AppTitleBar(
                                    navigationEnabled:
                                        !blocked &&
                                        !(startup?.visible ?? false),
                                    onUpdatePressed: () {
                                      final navigatorContext = _navigatorKey
                                          .currentState
                                          ?.overlay
                                          ?.context;
                                      if (navigatorContext == null) return;

                                      final updates = context
                                          .read<AppUpdateProvider>();
                                      final currentVersion = appReleaseVersion(
                                        context
                                            .read<PackageInfoProvider>()
                                            .version,
                                      );
                                      showDialog<void>(
                                        context: navigatorContext,
                                        builder: (dialogContext) =>
                                            AppUpdateDialog(
                                              theme: context
                                                  .read<ThemeProvider>()
                                                  .themeData,
                                              currentVersion: currentVersion,
                                              initialUpdate: updates.update,
                                              initialFailure: updates.failure,
                                            ),
                                      );
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: ClipRect(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        IgnorePointer(
                                          ignoring: startup?.visible ?? false,
                                          child: ExcludeFocus(
                                            excluding:
                                                startup?.visible ?? false,
                                            child: ExcludeSemantics(
                                              excluding:
                                                  startup?.visible ?? false,
                                              child: ScaffoldMessenger(
                                                child: navigator!,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (startup?.visible ?? false)
                                          FadeTransition(
                                            opacity: startup!.opacity,
                                            child: Consumer<ThemeProvider>(
                                              builder: (context, theme, _) =>
                                                  StartupScreen(
                                                    themeType:
                                                        theme.currentTheme,
                                                    framed: false,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
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
