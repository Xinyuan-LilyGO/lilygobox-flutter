import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

@pragma('vm:entry-point')
void trayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayMenuApp());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'profile production settings transitions at normal and maximized size',
    (tester) async {
      await tester.runAsync(app.main);
      Future<void> frames([int count = 40]) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      }

      await frames(100);
      final context = tester.element(find.byType(AppTitleBar));
      final navigation = context.read<AppNavigationProvider>();
      final window = context.read<WindowProvider>();
      final nativeWindow = WindowManager.instance.getCurrent()!;
      if (nativeWindow.isMaximized) {
        await tester.runAsync(window.handleMaximizeRestore);
        await frames();
      }
      expect(nativeWindow.isMaximized, isFalse);
      context.read<AppShellProvider>().openAssistant();
      await frames();
      Future<void> settingsCycle({bool hoverDuringEntrance = false}) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        // Keep the pointer on the incoming settings surface, away from the
        // account trigger and settings navigation on the left. Never click it.
        final point = Offset(size.width * .75, size.height - 80);
        await mouse.addPointer(location: point);
        try {
          await tester.tap(find.byKey(const ValueKey('account-menu-trigger')));
          await frames(20);
          await tester.tap(find.byKey(const ValueKey('account-menu-settings')));
          // Exercise real hover events throughout the 500ms entrance instead
          // of only MouseTracker enter/exit updates under a stationary mouse.
          for (var i = 0; i < 32; i++) {
            if (hoverDuringEntrance) {
              await mouse.moveTo(point + Offset(i.isEven ? 2 : 0, 0));
            }
            await frames(1);
          }
          await frames(18);
          expect(navigation.currentPage, AppPage.settings);
          navigation.closeSettings();
          await frames();
          expect(navigation.currentPage, AppPage.home);
        } finally {
          await mouse.removePointer();
        }
      }

      var zoomIn = true;
      Future<void> manipulateCanvas() async {
        expect(nativeWindow.isMaximized, isTrue);
        final viewer = find.byType(InteractiveViewer);
        expect(viewer, findsOneWidget);
        final controller = tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!;
        final beforePan = controller.value.clone();
        // Use a free point on the canvas rather than a card or toolbar.
        final point = tester.getTopLeft(viewer) + const Offset(80, 120);
        final pan = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        for (var i = 0; i < 20; i++) {
          await pan.moveBy(const Offset(4, 2));
          await frames(1);
        }
        await pan.up();
        await frames(12);
        expect(controller.value, isNot(equals(beforePan)));
        final beforeZoom = controller.value.getMaxScaleOnAxis();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          for (var i = 0; i < 6; i++) {
            tester.binding.handlePointerEvent(
              PointerScrollEvent(
                position: point,
                scrollDelta: Offset(0, zoomIn ? -24 : 24),
                kind: PointerDeviceKind.mouse,
              ),
            );
            await frames(1);
          }
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await frames(20);
        expect(
          controller.value.getMaxScaleOnAxis(),
          zoomIn ? greaterThan(beforeZoom) : lessThan(beforeZoom),
        );
        zoomIn = !zoomIn;
      }

      // Reproduce the reported order: maximize first, then open settings for
      // the first time. Keep this separate from warmed repeated transitions.
      await tester.runAsync(window.handleMaximizeRestore);
      await frames();
      expect(nativeWindow.isMaximized, isTrue);
      // Only the first group is a cold settings mount in this process. Run
      // with WINDOW_PERF_HOVER_FIRST=true to give moving-pointer entry that role.
      const hoverFirst = bool.fromEnvironment('WINDOW_PERF_HOVER_FIRST');
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['cold_settings_pointer_scenario'] = hoverFirst
          ? 'hover'
          : 'stationary';
      for (final hover in [hoverFirst, !hoverFirst]) {
        final scenario = hover ? 'hover' : 'stationary';
        final first = hover == hoverFirst ? 'first_open' : 'first_in_group';
        await manipulateCanvas();
        await binding.watchPerformance(
          () => settingsCycle(hoverDuringEntrance: hover),
          reportKey: 'settings_maximized_after_canvas_${scenario}_$first',
        );
        for (var i = 0; i < 4; i++) {
          await manipulateCanvas();
          await binding.watchPerformance(
            () => settingsCycle(hoverDuringEntrance: hover),
            reportKey:
                'settings_maximized_after_canvas_${scenario}_repeated_$i',
          );
        }
      }
      await tester.runAsync(window.handleMaximizeRestore);
      await frames();
      expect(nativeWindow.isMaximized, isFalse);
      // Retain the same content and renderer for repeated transitions.
      await settingsCycle();
      await binding.watchPerformance(() async {
        for (var i = 0; i < 4; i++) {
          await settingsCycle();
        }
      }, reportKey: 'settings_normal');
      final maximizeMs = <double>[];
      await binding.watchPerformance(() async {
        for (var i = 0; i < 4; i++) {
          final stopwatch = Stopwatch()..start();
          await tester.runAsync(window.handleMaximizeRestore);
          maximizeMs.add(stopwatch.elapsedMicroseconds / 1000);
          await frames(20);
        }
      }, reportKey: 'window_resize');
      await tester.runAsync(window.handleMaximizeRestore);
      await frames();
      expect(
        nativeWindow.isMaximized,
        isTrue,
        reason: 'Measure settings only after the native window is maximized',
      );
      binding.reportData!['maximized_window_size'] = {
        'width': tester.view.physicalSize.width,
        'height': tester.view.physicalSize.height,
      };
      await settingsCycle();
      await binding.watchPerformance(() async {
        for (var i = 0; i < 4; i++) {
          await settingsCycle();
        }
      }, reportKey: 'settings_maximized');
      binding.reportData!['native_resize_call_ms'] = maximizeMs;
      await tester.runAsync(window.handleMaximizeRestore);
      await frames();
    },
  );
}
