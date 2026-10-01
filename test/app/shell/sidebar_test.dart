/*
 * @Description: 验证侧栏连续拖动、折叠展开、导航布局与账号入口行为。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygo_box/app/shell/pages/page.dart';
import 'package:lilygo_box/app/shell/state/provider.dart';
import 'package:lilygo_box/app/shell/widgets/resizable_sidebar.dart';
import 'package:lilygo_box/core/layout/split_view_provider.dart';
import 'package:lilygo_box/core/theme/provider.dart';
import 'package:lilygo_box/features/devices/state/manager_provider.dart';
import 'package:lilygo_box/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('one held drag can collapse, reopen and keep resizing', (
    tester,
  ) async {
    final shell = AppShellProvider();
    addTearDown(shell.dispose);
    const sidebarBodyKey = ValueKey('sidebar-body');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: shell,
        child: const MaterialApp(
          home: Scaffold(
            body: ResizableSidebar(
              sidebar: SizedBox.expand(key: sidebarBodyKey),
              content: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    final panel = find.byKey(const ValueKey('sidebar-panel'));
    final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
    final body = find.byKey(sidebarBodyKey);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(shell.isSidebarVisible, isFalse);
    expect(tester.getSize(panel).width, 0);

    await drag.moveBy(const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(shell.isSidebarVisible, isTrue);
    expect(tester.getSize(panel).width, 280);
    expect(tester.getSize(body).width, 280);

    // 同一次按住拖动，展开结束后应立即跟手，内容宽度不能与侧栏脱节。
    for (final delta in [-60.0, 70.0, -50.0]) {
      await drag.moveBy(Offset(delta, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(panel).width, shell.sidebarWidth);
      expect(tester.getSize(body).width, tester.getSize(panel).width);
    }

    // 不等折叠动画完成就反向展开，再快速缩窄，任何一帧都不能露出空白。
    await drag.moveBy(const Offset(-160, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    expect(shell.isSidebarVisible, isFalse);
    expect(tester.getSize(panel).width, greaterThan(0));
    await drag.moveBy(const Offset(140, 0));
    await tester.pump();
    expect(shell.isSidebarVisible, isTrue);
    for (final delta in [-30.0, 60.0, -40.0, 30.0]) {
      await drag.moveBy(Offset(delta, 0));
      await tester.pump(const Duration(milliseconds: 16));
      // 展开动画中继续拖动，应立即由指针接管，不反复启动追赶动画。
      expect(tester.getSize(panel).width, shell.sidebarWidth);
      expect(
        tester.getSize(body).width,
        greaterThanOrEqualTo(tester.getSize(panel).width),
      );
      expect(tester.getTopLeft(body).dx, tester.getTopLeft(panel).dx);
    }
    await tester.pumpAndSettle();
    await drag.moveBy(const Offset(35, 0));
    await tester.pump();
    expect(tester.getSize(panel).width, shell.sidebarWidth);
    expect(tester.getSize(body).width, tester.getSize(panel).width);
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(body).width, tester.getSize(panel).width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag takes over the displayed width during reopening', (
    tester,
  ) async {
    final shell = AppShellProvider();
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: shell,
        child: const MaterialApp(
          home: Scaffold(
            body: ResizableSidebar(
              sidebar: Align(
                alignment: Alignment.topLeft,
                child: Text('Anchor', key: ValueKey('sidebar-anchor')),
              ),
              content: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    final panel = find.byKey(const ValueKey('sidebar-panel'));
    final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
    final anchor = find.byKey(const ValueKey('sidebar-anchor'));
    final anchorX = tester.getTopLeft(anchor).dx;
    shell.toggleSidebar();
    await tester.pumpAndSettle();
    shell.toggleSidebar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    final displayedWidth = tester.getSize(panel).width;
    expect(displayedWidth, lessThan(shell.sidebarWidth));

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // 按下边界即接管动画，不能在识别拖动前继续跑向旧目标。
    expect(tester.getSize(panel).width, closeTo(displayedWidth, .01));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getSize(panel).width, closeTo(displayedWidth + 40, .01));
    await gesture.moveBy(const Offset(45, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(tester.getSize(panel).width, closeTo(displayedWidth + 55, .01));
    expect(tester.getTopLeft(anchor).dx, anchorX);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, closeTo(shell.sidebarWidth, .01));
    expect(tester.getTopLeft(anchor).dx, anchorX);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging past the minimum collapses and toggle restores sidebar',
    (tester) async {
      final shell = AppShellProvider()..updateSelectedIndex(2);
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: shell,
          child: MaterialApp(
            home: Scaffold(
              body: ResizableSidebar(
                sidebar: const Text('Navigation'),
                content: const TextField(),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Keep page state');
      final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
      final resizeGesture = await tester.startGesture(tester.getCenter(handle));
      await resizeGesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(shell.sidebarWidth, greaterThan(240));
      final expandedWidth = shell.sidebarWidth;
      expect(
        tester.getSize(find.byKey(const ValueKey('sidebar-panel'))).width,
        expandedWidth,
      );
      await resizeGesture.up();
      await tester.pumpAndSettle();

      final collapseGesture = await tester.startGesture(
        tester.getCenter(handle),
      );
      await collapseGesture.moveBy(const Offset(-220, 0));
      await tester.pump();
      expect(shell.isSidebarVisible, isFalse);
      final panel = find.byKey(const ValueKey('sidebar-panel'));
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getSize(panel).width, greaterThan(0));
      expect(tester.getSize(panel).width, lessThan(expandedWidth));
      // 继续向左拖动不能让尚未完成的收缩动画直接跳到零。
      await collapseGesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.text('Navigation'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('sidebar-panel'))).width,
        0,
      );
      expect(find.text('Keep page state'), findsOneWidget);
      expect(shell.selectedIndex, 2);
      await collapseGesture.up();
      await tester.pumpAndSettle();

      final expandGesture = await tester.startGesture(tester.getCenter(handle));
      await expandGesture.moveBy(const Offset(160, 0));
      await tester.pump();
      expect(shell.isSidebarVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getSize(panel).width, greaterThan(0));
      expect(tester.getSize(panel).width, lessThan(shell.sidebarWidth));
      await expandGesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, shell.sidebarWidth);

      shell.toggleSidebar();
      await tester.pumpAndSettle();

      shell.toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.text('Navigation'), findsOneWidget);
      expect(shell.sidebarWidth, inInclusiveRange(180, expandedWidth));
      expect(find.text('Keep page state'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sidebar has branding, labeled home and borderless account entry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1150, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = AppShellProvider();
      final devices = DeviceManagerProvider()
        ..addDevice('A device with a long display name');
      final theme = ThemeProvider();
      final split = SplitViewProvider();
      addTearDown(shell.dispose);
      addTearDown(devices.dispose);
      addTearDown(theme.dispose);
      addTearDown(split.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: shell),
            ChangeNotifierProvider.value(value: devices),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: split),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AppShell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LilygoBox'), findsOneWidget);
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('账号设置'), findsOneWidget);
      expect(find.text('未登录'), findsOneWidget);

      shell.resizeSidebar(180, maxWidth: 360);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 检查中间帧与快速反向切换，侧栏文字不应在收缩时发生溢出。
      final panel = find.byKey(const ValueKey('sidebar-panel'));
      final expandedWidth = tester.getSize(panel).width;
      shell.toggleSidebar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final shrinkingWidth = tester.getSize(panel).width;
      expect(shrinkingWidth, greaterThan(0));
      expect(shrinkingWidth, lessThan(expandedWidth));
      expect(tester.takeException(), isNull);

      shell.toggleSidebar();
      await tester.pump();
      expect(tester.getSize(panel).width, closeTo(shrinkingWidth, 0.01));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, expandedWidth);

      shell.toggleSidebar();
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, 0);
      expect(find.text('首页'), findsNothing);
      shell.toggleSidebar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getSize(panel).width, greaterThan(0));
      expect(tester.getSize(panel).width, lessThan(expandedWidth));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('账号设置'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('账号设置'), findsOneWidget);
      expect(shell.selectedIndex, 0);
    },
  );
}
