/*
 * @Description: 验证设置覆盖页的返回路径、连接页面保留及隐藏页面资源释放。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 20:29:43
 * @LastEditTime: 2026-10-04 20:58:06
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/retained_page_stack.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/features/account/state/provider.dart';
import 'package:lilygobox/features/devices/domain/discovery_service.dart';
import 'package:lilygobox/features/devices/presentation/pages/add_page.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../features/account/authorization_test.dart'
    show FakeApi, MemoryStore;
import '../../features/devices/discovery_test.dart'
    show TestDiscoveryService, device;

class _TestLanConnection extends LanConnection {
  final service = TestDiscoveryService();

  @override
  Stream<DiscoveredDevice> discover() => service.discover();

  @override
  Future<bool> connect(DiscoveredDevice device) => service.connect(device);

  @override
  Future<void> cancelConnection() => service.cancelConnection();
}

void main() {
  test(
    'settings returns to the underlying page, including nested settings',
    () {
      final navigation = AppNavigationProvider();
      addTearDown(navigation.dispose);
      navigation.setPage(AppPage.addDevice);
      navigation.openDeviceSettings('P4');
      navigation.setPage(AppPage.settings);
      expect(navigation.contentPage, AppPage.addDevice);
      navigation.closeSettings();
      expect(navigation.currentPage, AppPage.deviceSettings);
      expect(navigation.settingsDeviceName, 'P4');
      navigation.closeSettings();
      expect(navigation.currentPage, AppPage.addDevice);
      expect(navigation.settingsDeviceName, isNull);
      navigation.setPage(AppPage.settings);
      navigation.goHome();
      navigation.closeSettings();
      expect(navigation.currentPage, AppPage.home);
    },
  );

  testWidgets('settings preserves the add page and its pending connection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1150, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigation = AppNavigationProvider()..setPage(AppPage.addDevice);
    final theme = ThemeProvider();
    final shell = AppShellProvider();
    final devices = DeviceManagerProvider();
    final split = SplitViewProvider();
    final language = LanguageProvider();
    final connection = _TestLanConnection();
    final account = AccountProvider(
      clientId: 'test',
      api: FakeApi(),
      store: MemoryStore(),
    );
    for (final provider in [
      navigation,
      theme,
      shell,
      devices,
      split,
      language,
      account,
      connection,
    ]) {
      addTearDown(provider.dispose);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: navigation),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: shell),
          ChangeNotifierProvider.value(value: devices),
          ChangeNotifierProvider.value(value: split),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider<LanConnection>.value(value: connection),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: Column(children: [WindowPageStack()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalState = tester.state(find.byType(AddDevicePage));
    connection.service.scans.single.add(device);
    await tester.pumpAndSettle();
    await tester.tap(find.text('T-Display-P4'));
    await tester.pumpAndSettle();
    expect(find.text('取消连接'), findsOneWidget);
    navigation.setPage(AppPage.settings);
    await tester.pumpAndSettle();
    expect(originalState.mounted, isTrue);
    expect(find.byType(AddDevicePage), findsNothing);
    final close = find.byWidgetPredicate(
      (w) => w is TitleBarIconButton && w.size == 28,
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.addDevice);
    expect(tester.state(find.byType(AddDevicePage)), same(originalState));
    expect(find.text('取消连接'), findsOneWidget);
    expect(find.text('T-Display-P4'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hidden connection continues and only removal disposes the page',
    (tester) async {
      final theme = ThemeProvider();
      final service = TestDiscoveryService();
      addTearDown(theme.dispose);
      var active = 'add';
      var includeAdd = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return RetainedPageStack(
                    activeKey: active,
                    pages: {
                      if (includeAdd)
                        'add': AddDevicePage(discoveryService: service),
                      'other': const Center(child: Text('Other page')),
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      service.scans.single.add(device);
      await tester.pumpAndSettle();
      await tester.tap(find.text('T-Display-P4'));
      await tester.pumpAndSettle();
      final pageState = tester.state(find.byType(AddDevicePage));
      final cancellations = service.cancelledConnections;
      rebuild(() => active = 'other');
      await tester.pumpAndSettle();
      expect(pageState.mounted, isTrue);
      expect(service.cancelledConnections, cancellations);
      service.connections.single.complete(true);
      await tester.pumpAndSettle();
      rebuild(() => active = 'add');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AddDevicePage)), same(pageState));
      expect(find.text('打开设备'), findsOneWidget);
      rebuild(() {
        active = 'other';
        includeAdd = false;
      });
      await tester.pumpAndSettle();
      expect(pageState.mounted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
