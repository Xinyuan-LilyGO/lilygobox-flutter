/*
 * @Description: 集中创建并注入应用级状态管理对象。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/app_info/package_info_provider.dart';
import '../core/l10n/language_provider.dart';
import '../core/layout/split_view_provider.dart';
import '../core/theme/provider.dart';
import '../core/window/provider.dart';
import '../features/devices/state/manager_provider.dart';
import 'navigation/provider.dart';
import 'shell/state/provider.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 应用级状态统一从这里注入，避免各页面分散创建 Provider。
    // 排序大致按作用域从基础设施到业务状态排列，后续新增全局状态也优先放在这里。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => WindowProvider()),
        ChangeNotifierProvider(create: (_) => AppNavigationProvider()),
        ChangeNotifierProvider(create: (_) => SplitViewProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => PackageInfoProvider()),
        ChangeNotifierProvider(create: (_) => AppShellProvider()),
        ChangeNotifierProvider(create: (_) => DeviceManagerProvider()),
      ],
      child: child,
    );
  }
}
