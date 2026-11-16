/*
 * @Description: 验证设备设置导航携带目标设备，并按设备分派页面及正确返回。
 */

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/pages/page.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/window_page_stack.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/update_scope.dart';
import 'package:lilygobox/core/widgets/animated_circle_icon_button.dart';
import 'package:lilygobox/features/devices/presentation/widgets/unsupported_settings.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

void main() {
  test('device settings requires a target and notifies on target changes', () {
    final navigation = AppNavigationProvider();
    addTearDown(navigation.dispose);
    var changes = 0;
    navigation.addListener(() => changes++);
    expect(
      () => navigation.setPage(AppPage.deviceSettings),
      throwsArgumentError,
    );
    expect(() => navigation.openDeviceSettings('  '), throwsArgumentError);
    expect(navigation.currentPage, AppPage.home);
    navigation.openDeviceSettings('Device A');
    expect(navigation.settingsDeviceName, 'Device A');
    navigation.openDeviceSettings('Device A');
    expect(changes, 1);
    navigation.openDeviceSettings('Other device');
    expect(changes, 2);
    expect(navigation.settingsDeviceName, 'Other device');
    navigation.goHome();
    expect(navigation.settingsDeviceName, isNull);
    expect(navigation.currentPage, AppPage.home);
  });

  testWidgets('window routes arbitrary device settings to the fallback page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1150, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigation = AppNavigationProvider()..openDeviceSettings('Device A');
    final theme = ThemeProvider();
    final shell = AppShellProvider()..openDeviceManagement();
    final devices = DeviceManagerProvider();
    final split = SplitViewProvider();
    addTearDown(navigation.dispose);
    addTearDown(theme.dispose);
    addTearDown(shell.dispose);
    addTearDown(devices.dispose);
    addTearDown(split.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: navigation),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: shell),
          ChangeNotifierProvider.value(value: devices),
          ChangeNotifierProvider.value(value: split),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Column(children: [WindowPageStack()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UnsupportedDeviceSettings), findsOneWidget);
    expect(find.text('Device A'), findsOneWidget);
    await tester.tap(find.byType(AnimatedCircleIconButton));
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.home);
    expect(find.byType(AppShell), findsOneWidget);

    final originalShellState = tester.state(find.byType(AppShell));
    final semantics = tester.ensureSemantics();
    SnapshotController backgroundSnapshot() => tester
        .widget<SnapshotWidget>(
          find.byWidgetPredicate(
            (widget) =>
                widget is SnapshotWidget && widget.child is ThemeUpdateScope,
            skipOffstage: false,
          ),
        )
        .controller;
    SnapshotController overlaySnapshot() => tester
        .widget<SnapshotWidget>(
          find.byWidgetPredicate(
            (widget) =>
                widget is SnapshotWidget &&
                widget.child is RepaintBoundary &&
                (widget.child! as RepaintBoundary).child is! AppShell,
          ),
        )
        .controller;
    expect(backgroundSnapshot().allowSnapshotting, isFalse);
    navigation.openDeviceSettings('Device A');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(backgroundSnapshot().allowSnapshotting, isTrue);
    expect(overlaySnapshot().allowSnapshotting, isTrue);
    // Merely hovering over the moving page keeps both cached layers active.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final hoverPoint = tester.getCenter(find.text('Device A'));
    await mouse.addPointer(location: hoverPoint);
    await mouse.moveTo(hoverPoint + const Offset(1, 0));
    expect(overlaySnapshot().allowSnapshotting, isTrue);
    expect(backgroundSnapshot().allowSnapshotting, isTrue);
    await mouse.removePointer();
    // Clicking while the settings surface is moving keeps live input and paint.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Device A')),
    );
    await gesture.up();
    expect(overlaySnapshot().allowSnapshotting, isFalse);
    expect(
      tester.getSemantics(find.text('Device A')).getSemanticsData().label,
      contains('Device A'),
    );
    // Reversing an in-flight transition retains the live shell and its State.
    navigation.closeSettings();
    await tester.pump();
    expect(backgroundSnapshot().allowSnapshotting, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.state(find.byType(AppShell, skipOffstage: false)),
      same(originalShellState),
    );
    navigation.openDeviceSettings('Device A');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlaySnapshot().allowSnapshotting, isTrue);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.text('Device A')),
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, 20),
      ),
    );
    expect(overlaySnapshot().allowSnapshotting, isFalse);
    expect(backgroundSnapshot().allowSnapshotting, isTrue);
    expect(
      tester.getSemantics(find.text('Device A')).getSemanticsData().label,
      contains('Device A'),
    );
    navigation.closeSettings();
    await tester.pumpAndSettle();
    expect(backgroundSnapshot().allowSnapshotting, isFalse);
    expect(find.byType(UnsupportedDeviceSettings), findsNothing);
    expect(tester.state(find.byType(AppShell)), same(originalShellState));

    navigation.openDeviceSettings('Device A');
    await tester.pumpAndSettle();
    expect(backgroundSnapshot().allowSnapshotting, isFalse);
    navigation.openDeviceSettings('Other device');
    await tester.pumpAndSettle();
    expect(find.byType(UnsupportedDeviceSettings), findsOneWidget);
    expect(find.text('Other device'), findsOneWidget);
    expect(find.text('此设备暂未提供设置选项。'), findsOneWidget);
    navigation.openDeviceSettings('Another device');
    await tester.pumpAndSettle();
    expect(find.text('Other device'), findsNothing);
    expect(find.text('Another device'), findsOneWidget);
    await tester.tap(find.byType(AnimatedCircleIconButton));
    await tester.pumpAndSettle();
    expect(navigation.currentPage, AppPage.home);
    expect(navigation.settingsDeviceName, isNull);
    expect(find.byType(AppShell), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
