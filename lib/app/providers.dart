/*
 * @Description: 集中创建并注入应用级状态管理对象。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-06 09:16:32
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/app_info/package_info_provider.dart';
import '../core/l10n/language_provider.dart';
import '../core/layout/split_view_provider.dart';
import '../core/storage/preferences.dart';
import '../core/theme/provider.dart';
import '../core/window/provider.dart';
import '../features/account/state/provider.dart';
import '../features/devices/data/pairing_store.dart';
import '../features/devices/state/lan_connection.dart';
import '../features/devices/state/manager_provider.dart';
import 'device_connection_coordinator.dart';
import 'navigation/provider.dart';
import 'shell/state/provider.dart';

class AppProviders extends StatefulWidget {
  const AppProviders({
    super.key,
    required this.child,
    required this.preferences,
  });

  final Widget child;
  final AppPreferences preferences;

  @override
  State<AppProviders> createState() => _AppProvidersState();
}

class _AppProvidersState extends State<AppProviders>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ThemeProvider _theme = ThemeProvider(
    vsync: this,
    preferences: widget.preferences,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    didChangeAccessibilityFeatures();
  }

  @override
  void didChangeAccessibilityFeatures() {
    _theme.setDisableAnimations(
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.preferences.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 应用级状态统一从这里注入，避免各页面分散创建 Provider。
    // 排序大致按作用域从基础设施到业务状态排列，后续新增全局状态也优先放在这里。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.preferences),
        ChangeNotifierProvider.value(value: _theme),
        ChangeNotifierProvider(
          create: (_) => WindowProvider(beforeClose: widget.preferences.flush),
        ),
        ChangeNotifierProvider(create: (_) => AppNavigationProvider()),
        ChangeNotifierProvider(
          create: (_) => SplitViewProvider(preferences: widget.preferences),
        ),
        ChangeNotifierProvider(
          create: (_) => LanguageProvider(preferences: widget.preferences),
        ),
        ChangeNotifierProvider(create: (_) => PackageInfoProvider()),
        ChangeNotifierProvider(
          create: (_) => AppShellProvider(preferences: widget.preferences),
        ),
        ChangeNotifierProvider(
          create: (_) => DeviceManagerProvider(preferences: widget.preferences),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final devices = context.read<DeviceManagerProvider>();
            final connection = LanConnection(
              pairingStore: SecureDevicePairingStore(),
            );
            unawaited(
              connection.restorePairings(
                devices.addedDevices.map(devices.lanDevice).whereType(),
              ),
            );
            return connection;
          },
          lazy: false,
        ),
        Provider(
          lazy: false,
          create: (context) => DeviceConnectionCoordinator(
            connection: context.read<LanConnection>(),
            devices: context.read<DeviceManagerProvider>(),
            navigation: context.read<AppNavigationProvider>(),
          ),
          dispose: (_, coordinator) => coordinator.dispose(),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => AccountProvider.production()..restore(),
        ),
      ],
      child: widget.child,
    );
  }
}
