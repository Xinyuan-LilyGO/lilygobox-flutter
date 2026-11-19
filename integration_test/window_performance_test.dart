import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/app/widgets/title_bar.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/recycle_bin_dialog.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/storage_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
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
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(app.main);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['has_errors'] = false;
      binding.reportData!['semantics_enabled'] = binding.semanticsEnabled;
      Future<void> frames([int count = 40]) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump();
        }
        final error = tester.takeException();
        if (error != null) {
          binding.reportData!['has_errors'] = true;
          binding.reportData!['last_error'] = error.toString();
        }
        expect(error, isNull);
      }

      await frames(100);
      final context = tester.element(find.byType(AppTitleBar));
      final navigation = context.read<AppNavigationProvider>();
      final window = context.read<WindowProvider>();
      final shell = context.read<AppShellProvider>();
      final workspaces = context.read<AiWorkspaceProvider>();
      await tester.runAsync(() => workspaces.initialized);
      final nativeWindow = WindowManager.instance.getCurrent()!;
      final initiallyMaximized = nativeWindow.isMaximized;
      final initialShellIndex = shell.selectedIndex;
      final initialDeviceSection = shell.deviceManagementSelected;
      final initialPage = navigation.currentPage;
      final initialContentPage = navigation.contentPage;
      final initialDeviceName = navigation.settingsDeviceName;
      final initialSettingsSection = navigation.settingsSection;
      final initialAgents = [
        for (final agent in workspaces.sessions)
          (agent.id, agent.parentId, agent.kind, agent.closed),
      ];
      final initialRecycled = workspaces.recycledAgents
          .map((agent) => agent.id)
          .toList();
      Future<void>? activeDialog;
      VoidCallback? restoreCanvasTransform;
      Future<void> settingsCycle({
        bool hoverDuringEntrance = false,
        String? entranceReportKey,
      }) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        // Keep the pointer on the incoming settings surface, away from the
        // account trigger and settings navigation on the left. Never click it.
        final point = Offset(size.width * .75, size.height - 80);
        await mouse.addPointer(location: point);
        try {
          await tester.tap(find.byKey(const ValueKey('account-menu-trigger')));
          await frames(20);
          Future<void> enterSettings() async {
            await tester.tap(
              find.byKey(const ValueKey('account-menu-settings')),
            );
            for (var i = 0; i < 32; i++) {
              if (hoverDuringEntrance) {
                await mouse.moveTo(point + Offset(i.isEven ? 2 : 0, 0));
              }
              await frames(1);
            }
          }

          if (entranceReportKey == null) {
            await enterSettings();
          } else {
            await binding.watchPerformance(
              enterSettings,
              reportKey: entranceReportKey,
            );
            binding.reportData!['${entranceReportKey}_scope'] =
                'settings_entrance';
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
        if (restoreCanvasTransform == null) {
          final initialTransform = controller.value.clone();
          restoreCanvasTransform = () {
            if (viewer.evaluate().any(
              (element) => identical(
                (element.widget as InteractiveViewer).transformationController,
                controller,
              ),
            )) {
              controller.value = initialTransform;
            }
          };
        }
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
            await tester.sendEventToBinding(
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

      Map<String, Object> windowSize() => {
        'physical_width': tester.view.physicalSize.width,
        'physical_height': tester.view.physicalSize.height,
        'logical_width':
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
        'logical_height':
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
        'device_pixel_ratio': tester.view.devicePixelRatio,
        'maximized': nativeWindow.isMaximized,
      };

      Future<void> scrollSurface(
        Finder surface,
        String label, {
        bool outermost = false,
      }) async {
        final scrollables = find
            .descendant(of: surface, matching: find.byType(Scrollable))
            .evaluate()
            .where((element) {
              final scrollable =
                  (element as StatefulElement).state as ScrollableState;
              return axisDirectionToAxis(scrollable.axisDirection) ==
                      Axis.vertical &&
                  scrollable.position.hasContentDimensions;
            })
            .toList();
        if (!outermost) {
          scrollables.sort((first, second) {
            final firstState =
                (first as StatefulElement).state as ScrollableState;
            final secondState =
                (second as StatefulElement).state as ScrollableState;
            return secondState.position.maxScrollExtent.compareTo(
              firstState.position.maxScrollExtent,
            );
          });
        }
        final viewport = scrollables.firstOrNull;
        final state = viewport == null
            ? null
            : (viewport as StatefulElement).state as ScrollableState;
        final position = state?.position;
        final before = position?.pixels ?? 0;
        final maximum = position?.maxScrollExtent ?? 0;
        var after = before;
        await binding.watchPerformance(() async {
          if (state != null && maximum > position!.minScrollExtent) {
            final target = find.byElementPredicate(
              (element) => element == viewport,
            );
            var point = tester.getCenter(target);
            if (outermost) {
              final bounds = tester
                  .getRect(target)
                  .intersect(
                    Offset.zero &
                        (tester.view.physicalSize /
                            tester.view.devicePixelRatio),
                  );
              final nestedBounds = [
                for (final element in scrollables)
                  if (element != viewport)
                    tester.getRect(
                      find.byElementPredicate(
                        (candidate) => candidate == element,
                      ),
                    ),
              ];
              final outerRenderObject = viewport!.findRenderObject();
              final candidates = [
                for (final vertical in [.05, .15, .3, .5, .7, .85, .95])
                  for (final horizontal in [.5, .05, .95])
                    Offset(
                      bounds.left + bounds.width * horizontal,
                      bounds.top + bounds.height * vertical,
                    ),
              ];
              final exclusivePoint = candidates.where((candidate) {
                if (nestedBounds.any((rect) => rect.contains(candidate))) {
                  return false;
                }
                return tester
                    .hitTestOnBinding(candidate)
                    .path
                    .any((entry) => identical(entry.target, outerRenderObject));
              }).firstOrNull;
              expect(
                exclusivePoint,
                isNotNull,
                reason:
                    '$label needs a visible point outside nested scrollables',
              );
              point = exclusivePoint!;
            }
            for (var index = 0; index < 10; index++) {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: point,
                  scrollDelta: Offset(0, before >= maximum - 1 ? -56 : 56),
                  timeStamp: Duration(milliseconds: 1000 + index * 16),
                  kind: PointerDeviceKind.mouse,
                ),
              );
              await frames(1);
            }
            await frames(18);
            after = position.pixels;
            expect(
              (after - before).abs(),
              greaterThan(.01),
              reason: '$label must move when its content is scrollable',
            );
          } else {
            await frames(6);
          }
        }, reportKey: '${label}_frames');
        binding.reportData!['${label}_scroll'] = {
          'scrollable_count': scrollables.length,
          'min_scroll_extent': position?.minScrollExtent ?? 0,
          'max_scroll_extent': maximum,
          'viewport_dimension': position?.viewportDimension ?? 0,
          'offset_before': before,
          'offset_after': after,
          'moved': (after - before).abs() > .01,
          'window': windowSize(),
        };
        if (position != null && position.pixels != before) {
          position.jumpTo(
            before
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble(),
          );
          await frames(4);
        }
      }

      Future<void> settingsPages(String sizeLabel) async {
        await tester.tap(find.byKey(const ValueKey('account-menu-trigger')));
        await frames(16);
        await tester.tap(find.byKey(const ValueKey('account-menu-settings')));
        await frames();
        final general = find.byKey(const ValueKey('settings-category-general'));
        await tester.ensureVisible(general);
        await tester.tap(general);
        await frames(22);
        expect(find.byKey(const ValueKey('general')), findsOneWidget);
        for (final section in [
          'profile',
          'general',
          'appearance',
          'language',
          'aiService',
          'storage',
          'about',
        ]) {
          final key = section == 'profile' || section == 'about'
              ? 'settings-$section'
              : 'settings-category-$section';
          final item = find.byKey(ValueKey(key));
          if (item.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              item,
              120,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('settings-sidebar')),
                    matching: find.byType(Scrollable),
                  )
                  .last,
              maxScrolls: 12,
            );
          }
          await tester.ensureVisible(item);
          await frames(4);
          await binding.watchPerformance(() async {
            await tester.tap(item);
            await frames(22);
          }, reportKey: 'settings_${sizeLabel}_${section}_open');
          final content = find.byKey(ValueKey(section));
          expect(content, findsOneWidget);
          await scrollSurface(content, 'settings_${sizeLabel}_$section');
        }
        navigation.closeSettings();
        await frames();
      }

      Future<void> readonlyPages(
        String sizeLabel,
        String memoryOwner,
        String? firstMemoryId,
        int ownerMemoryCount,
      ) async {
        binding.reportData!['${sizeLabel}_window'] = windowSize();
        await binding.watchPerformance(() async {
          for (var index = 0; index < 2; index++) {
            await tester.tap(find.byKey(const ValueKey('sidebar-devices')));
            await frames(24);
            expect(
              shell.deviceManagementSelected || shell.selectedIndex > 0,
              isTrue,
            );
            await tester.tap(find.byKey(const ValueKey('sidebar-home')));
            await frames(24);
            expect(shell.deviceManagementSelected, isFalse);
            expect(shell.selectedIndex, 0);
          }
        }, reportKey: 'assistant_device_${sizeLabel}_switch');
        await settingsPages(sizeLabel);
        final theme = context.read<ThemeProvider>().themeData;
        await binding.watchPerformance(() async {
          activeDialog = showAgentRecycleBin(context, theme);
          await frames();
        }, reportKey: 'recycle_${sizeLabel}_open');
        var recycleList = find.byKey(
          const ValueKey('recycle-agent-list-scroll'),
        );
        if (recycleList.evaluate().isEmpty) {
          recycleList = find.byKey(
            const ValueKey('recycle-agent-compact-scroll'),
          );
        }
        expect(recycleList, findsOneWidget);
        await scrollSurface(recycleList, 'recycle_${sizeLabel}_list');
        Navigator.of(context, rootNavigator: true).pop();
        await activeDialog;
        activeDialog = null;
        await frames(24);
        await binding.watchPerformance(() async {
          activeDialog = showAgentStorage(context, theme, memoryOwner);
          await frames();
          if (firstMemoryId != null) {
            final firstCard = find.byKey(
              ValueKey('storage-memory-card-$firstMemoryId'),
            );
            for (
              var attempt = 0;
              attempt < 600 && firstCard.evaluate().isEmpty;
              attempt++
            ) {
              await frames(1);
            }
            expect(
              firstCard,
              findsOneWidget,
              reason: 'The selected owner must load its known first memory',
            );
          }
        }, reportKey: 'memory_${sizeLabel}_open');
        final memoryList = find.byKey(
          const ValueKey('storage-memory-list-scroll'),
        );
        expect(memoryList, findsOneWidget);
        final itemCount = tester
            .widget<ListView>(memoryList)
            .childrenDelegate
            .estimatedChildCount!;
        final expectedLoadedCount = ownerMemoryCount.clamp(0, 50);
        final hasMore = ownerMemoryCount > expectedLoadedCount;
        expect(
          itemCount,
          ownerMemoryCount == 0 ? 1 : expectedLoadedCount + (hasMore ? 1 : 0),
        );
        binding.reportData!['memory_${sizeLabel}_data'] = {
          'owner': memoryOwner,
          'owner_total_rows': ownerMemoryCount,
          'loaded_rows': ownerMemoryCount == 0
              ? 0
              : itemCount - (hasMore ? 1 : 0),
          'known_first_memory_loaded': firstMemoryId != null,
          'memory_payload_exercised': ownerMemoryCount > 0,
          'has_more': hasMore,
        };
        await tester.ensureVisible(memoryList);
        await frames(6);
        await scrollSurface(memoryList, 'memory_${sizeLabel}_list');
        await scrollSurface(
          find.byKey(const ValueKey('storage-manager-scroll')),
          'memory_${sizeLabel}_dialog',
          outermost: true,
        );
        Navigator.of(context, rootNavigator: true).pop();
        await activeDialog;
        activeDialog = null;
        await frames(24);
      }

      try {
        if (nativeWindow.isMaximized) {
          await tester.runAsync(window.handleMaximizeRestore);
          await frames();
        }
        expect(nativeWindow.isMaximized, isFalse);
        navigation.setPage(AppPage.home);
        shell.openAssistant();
        await frames();
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
          await settingsCycle(
            hoverDuringEntrance: hover,
            entranceReportKey:
                'settings_maximized_after_canvas_${scenario}_$first',
          );
          for (var i = 0; i < 2; i++) {
            await manipulateCanvas();
            await settingsCycle(
              hoverDuringEntrance: hover,
              entranceReportKey:
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
          for (var i = 0; i < 2; i++) {
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
          for (var i = 0; i < 2; i++) {
            await settingsCycle();
          }
        }, reportKey: 'settings_maximized');
        binding.reportData!['native_resize_call_ms'] = maximizeMs;
        await tester.runAsync(window.handleMaximizeRestore);
        await frames();
        final statistics = await tester.runAsync(
          () async => workspaces.main.storage?.request('stats'),
        );
        final scopes = statistics is Map ? statistics['scopes'] : null;
        final activeIds = workspaces.sessions.map((agent) => agent.id).toSet();
        final memoryOwner = scopes is List
            ? scopes.whereType<String>().where(activeIds.contains).firstOrNull
            : null;
        final owner =
            memoryOwner ??
            workspaces.selectedId ??
            workspaces.sessions.firstOrNull?.id ??
            '';
        final ownerMemories = await tester.runAsync(() async {
          final rows = await workspaces.main.storage?.memories(owner);
          return (
            total: rows?.length ?? 0,
            firstId: rows?.firstOrNull?['id'] as String?,
          );
        });
        expect(ownerMemories, isNotNull);
        binding.reportData!['existing_data'] = {
          'active_agent_count': workspaces.sessions.length,
          'recycled_agent_count': workspaces.recycledAgents.length,
          'memory_count': statistics is Map ? statistics['memories'] : null,
          'memory_owner_has_existing_memory': memoryOwner != null,
          'selected_memory_owner': owner,
          'selected_owner_memory_count': ownerMemories!.total,
        };
        await readonlyPages(
          'normal',
          owner,
          ownerMemories.firstId,
          ownerMemories.total,
        );
        await tester.runAsync(window.handleMaximizeRestore);
        await frames();
        await readonlyPages(
          'maximized',
          owner,
          ownerMemories.firstId,
          ownerMemories.total,
        );
        expect([
          for (final agent in workspaces.sessions)
            (agent.id, agent.parentId, agent.kind, agent.closed),
        ], initialAgents);
        expect(
          workspaces.recycledAgents.map((agent) => agent.id),
          initialRecycled,
        );
      } finally {
        try {
          if (activeDialog != null && context.mounted) {
            final navigator = Navigator.of(context, rootNavigator: true);
            if (navigator.canPop()) navigator.pop();
            await activeDialog;
            activeDialog = null;
            await frames(24);
          }
        } finally {
          if (initialDeviceSection) {
            shell.openDeviceManagement();
          } else if (initialShellIndex > 0) {
            shell.updateSelectedIndex(initialShellIndex);
          } else {
            shell.openAssistant();
          }
          navigation.setPage(initialContentPage);
          if (initialPage == AppPage.settings &&
              initialSettingsSection == AppSettingsSection.aiServices) {
            navigation.openAiSettings();
          } else {
            navigation.setPage(initialPage, deviceName: initialDeviceName);
          }
          if (nativeWindow.isMaximized != initiallyMaximized) {
            await tester.runAsync(window.handleMaximizeRestore);
          }
          await frames();
          restoreCanvasTransform?.call();
        }
      }
    },
  );
}
