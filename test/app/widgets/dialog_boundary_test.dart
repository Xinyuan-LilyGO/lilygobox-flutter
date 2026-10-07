/*
 * @Description: 验证遮罩仅覆盖内容区，窗口按钮仍可用，确认期间禁止标题栏页面切换。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 23:41:53
 * @LastEditTime: 2026-10-03 23:56:45
 * @License: GPL 3.0
 */

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/device_connection_coordinator.dart';
import 'package:lilygobox/app/lilygobox_app.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/title_bar_control_button.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/core/app_info/package_info_provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/features/account/domain/models.dart';
import 'package:lilygobox/features/account/state/provider.dart';
import 'package:lilygobox/features/devices/data/lan_discovery.dart';
import 'package:lilygobox/features/devices/presentation/widgets/home_device_card.dart';
import 'package:lilygobox/features/devices/state/lan_connection.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/storage/preferences_test.dart' show MemoryPreferencesStorage;
import '../../features/account/authorization_test.dart'
    show FakeApi, MemoryStore;

class TestWindowProvider extends WindowProvider {
  int minimizeCalls = 0;
  int closeCalls = 0;

  @override
  Future<void> minimize() async => minimizeCalls++;

  @override
  Future<void> handleMaximizeRestore() async {
    isMaximized ? onWindowUnmaximize() : onWindowMaximize();
  }

  @override
  Future<void> close({bool discardUnsaved = false}) async => closeCalls++;
}

class _Connection extends LanConnection {
  void publish(LanDevice target) {
    device = target;
    phase = LanConnectionPhase.connected;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'rounded window compositing does not leak the light base through a mask',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final key = GlobalKey();
      for (final mode in ThemeType.values) {
        theme.setTheme(mode);
        for (final ratio in [1.0, 1.25, 1.5]) {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(devicePixelRatio: ratio),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 100,
                      height: 80,
                      child: AppWindowFrame(
                        theme: theme.themeData,
                        isMaximized: false,
                        child: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final leakedPixels = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: ratio);
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final bytes = data!.buffer.asUint8List();
            var leaked = 0;
            // 全黑遮罩和黑色阴影之外不应残留浅色底板的抗锯齿亮边。
            for (var i = 0; i < bytes.length; i += 4) {
              if (bytes[i + 3] > 0 &&
                  (bytes[i] > 0 || bytes[i + 1] > 0 || bytes[i + 2] > 0)) {
                leaked++;
              }
            }
            image.dispose();
            return leaked;
          });
          expect(leakedPixels, 0, reason: '$mode at $ratio');
        }
      }
    },
  );

  testWidgets('dialog stays inside the frame through window size changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PackageInfo.setMockInitialValues(
      appName: 'LilygoBox',
      packageName: 'lilygobox',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final theme = ThemeProvider();
    final language = LanguageProvider()..changeLanguage('zh');
    final navigation = AppNavigationProvider()..setPage(AppPage.settings);
    final window = TestWindowProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final devices = DeviceManagerProvider();
    final connection = _Connection();
    final coordinator = DeviceConnectionCoordinator(
      connection: connection,
      devices: devices,
      navigation: navigation,
    );
    addTearDown(coordinator.dispose);
    final info = PackageInfoProvider();
    final preferences = await AppPreferences.load(
      storage: MemoryPreferencesStorage(),
    );
    final store = MemoryStore()..token = const GithubToken('test-token');
    final account = AccountProvider(
      clientId: 'test',
      api: FakeApi(),
      store: store,
    );
    await account.restore();
    for (final provider in [
      theme,
      language,
      navigation,
      window,
      shell,
      split,
      devices,
      info,
      preferences,
      account,
      connection,
    ]) {
      addTearDown(provider.dispose);
    }
    final boundaryKey = GlobalKey();
    Future<List<List<int>>> sampleWindowEdges() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        final pixels = [
          for (final point in [
            const Offset(5, 325),
            const Offset(11, 11),
            const Offset(15, 325),
            const Offset(350, 25),
          ])
            bytes.sublist(
              (point.dy.toInt() * image.width + point.dx.toInt()) * 4,
              (point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 4,
            ),
        ];
        image.dispose();
        return pixels;
      }))!;
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: navigation),
          ChangeNotifierProvider<WindowProvider>.value(value: window),
          ChangeNotifierProvider.value(value: shell),
          ChangeNotifierProvider.value(value: split),
          ChangeNotifierProvider.value(value: devices),
          ChangeNotifierProvider.value(value: info),
          ChangeNotifierProvider.value(value: preferences),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider<LanConnection>.value(value: connection),
          Provider.value(value: coordinator),
        ],
        child: RepaintBoundary(key: boundaryKey, child: const LilygoBoxApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-general')));
    await tester.pumpAndSettle();
    final beforeDialog = await sampleWindowEdges();
    await tester.tap(find.byKey(const ValueKey('restore-defaults')));
    await tester.pumpAndSettle();
    final withDialog = await sampleWindowEdges();
    expect(withDialog[0], beforeDialog[0]);
    expect(withDialog[1], beforeDialog[1]);
    expect(withDialog[2], isNot(beforeDialog[2]));
    expect(withDialog[3], beforeDialog[3]);
    final barrier = find.byWidgetPredicate(
      (widget) => widget is ModalBarrier && widget.color != null,
    );
    final frameClip = find
        .descendant(
          of: find.byType(AppWindowFrame),
          matching: find.byType(ClipRRect),
        )
        .first;
    expect(tester.getRect(barrier), const Rect.fromLTWH(10, 40, 980, 600));
    expect(
      tester.widget<ClipRRect>(frameClip).borderRadius,
      BorderRadius.circular(10),
    );
    expect(find.ancestor(of: barrier, matching: frameClip), findsOneWidget);
    // 窗口外部的透明边距不属于弹窗遮罩，点击它不能关闭确认框。
    await tester.tapAt(const Offset(5, 325));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final titleSettings = find.byKey(const ValueKey('titlebar-settings'));
    expect(tester.widget<TitleBarIconButton>(titleSettings).onPressed, isNull);
    final windowButtons = find.byType(AppTitleBarControlsButtonTemplate);
    await tester.tap(windowButtons.at(0));
    await tester.pumpAndSettle();
    expect(window.minimizeCalls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(windowButtons.at(1));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.getRect(barrier), const Rect.fromLTWH(0, 30, 1000, 620));
    expect(tester.widget<ClipRRect>(frameClip).borderRadius, BorderRadius.zero);
    await tester.tap(windowButtons.at(1));
    await tester.binding.setSurfaceSize(const Size(900, 600));
    await tester.pumpAndSettle();
    expect(tester.getRect(barrier), const Rect.fromLTWH(10, 40, 880, 550));
    await tester.tap(windowButtons.at(2));
    await tester.pumpAndSettle();
    expect(window.closeCalls, 1);
    await tester.tap(find.byKey(const ValueKey('cancel-restore-defaults')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(navigation.currentPage, AppPage.settings);
    expect(
      tester.widget<TitleBarIconButton>(titleSettings).onPressed,
      isNotNull,
    );

    navigation.goHome();
    await tester.pumpAndSettle();
    final trigger = find.byKey(const ValueKey('account-menu-trigger'));
    final signOut = find.byKey(const ValueKey('account-menu-sign-out'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(signOut).dy,
      greaterThan(tester.getBottomLeft(find.text('设置')).dy),
    );
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-menu-card')), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.getRect(barrier), const Rect.fromLTWH(10, 40, 880, 550));
    final sidebarToggle = find.byKey(const ValueKey('toggle-sidebar'));
    expect(tester.widget<TitleBarIconButton>(titleSettings).onPressed, isNull);
    expect(tester.widget<TitleBarIconButton>(sidebarToggle).onPressed, isNull);
    final wasVisible = shell.isSidebarVisible;
    await tester.tap(titleSettings);
    await tester.tap(sidebarToggle);
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.home);
    expect(shell.isSidebarVisible, wasVisible);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(account.user, isNotNull);
    await tester.tap(find.byKey(const ValueKey('cancel-github-sign-out')));
    await tester.pumpAndSettle();
    expect(store.token, isNotNull);
    expect(
      tester.widget<TitleBarIconButton>(titleSettings).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TitleBarIconButton>(sidebarToggle).onPressed,
      isNotNull,
    );
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-github-sign-out')));
    await tester.pumpAndSettle();
    expect(store.token, isNull);
    expect(account.user, isNull);
    expect(navigation.currentPage, AppPage.home);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(signOut, findsNothing);
    expect(find.text('设置'), findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    // 标题栏移到 Navigator 外后，悬停提示仍有可用的 Overlay。
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(titleSettings));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    // 连接不弹提示，原有底部删除提示必须留在窗口圆角内部。
    const target = LanDevice(
      id: '001122334455',
      name: 'Desk P4',
      model: 'T-Display-P4',
      address: '192.168.1.8',
      port: 18464,
    );
    connection.publish(target);
    await tester.pumpAndSettle();
    final notice = find.byType(SnackBar);
    final noticeSurface = find
        .descendant(of: notice, matching: find.byType(Material))
        .first;
    final frameRect = tester.getRect(frameClip);
    expect(notice, findsNothing);
    await tester.tap(
      find.byType(HomeDeviceCard),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除设备'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-device')));
    await tester.pumpAndSettle();
    expect(find.text('设备已删除。'), findsOneWidget);
    expect(tester.widget<SnackBar>(notice).behavior, isNull);
    expect(
      tester.getRect(noticeSurface).left,
      greaterThanOrEqualTo(frameRect.left),
    );
    expect(
      tester.getRect(noticeSurface).right,
      lessThanOrEqualTo(frameRect.right),
    );
    expect(find.ancestor(of: notice, matching: frameClip), findsOneWidget);
    expect(
      tester.getRect(noticeSurface).bottom,
      lessThanOrEqualTo(frameRect.bottom),
    );
    window.onWindowMaximize();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(noticeSurface).right,
      lessThanOrEqualTo(tester.getRect(frameClip).right),
    );
    expect(tester.takeException(), isNull);
  });
}
