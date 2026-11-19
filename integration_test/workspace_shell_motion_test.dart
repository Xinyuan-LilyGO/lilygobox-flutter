import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:lilygobox/app/lilygobox_app.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/core/app_info/app_update_provider.dart';
import 'package:lilygobox/core/app_info/app_update_service.dart';
import 'package:lilygobox/core/app_info/package_info_provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/window/desktop_window.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_scrollbar.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';
import 'package:lilygobox/features/devices/state/manager_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';
import 'fixtures/workspace_motion.dart';

class _ProfileWindow extends WindowProvider {
  @override
  Future<void> configureTray(Map<String, Object> appearance) async {}
}

class _OfflineUpdates extends AppUpdateProvider {
  _OfflineUpdates(super.packageInfo);

  @override
  Future<AppUpdate?> check() async => null;
}

Future<void> _prepareShellWindow(RootIsolateToken root) =>
    Isolate.run(() async {
      BackgroundIsolateBinaryMessenger.ensureInitialized(root);
      await configureDesktopWindow();
    });

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'measure imported history through the maximized workspace shell',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await binding.waitUntilFirstFrameRasterized;
      debugPrint('SHELL_MOTION first frame rasterized');
      final root = ServicesBinding.rootIsolateToken!;
      await tester.runAsync(
        () => _prepareShellWindow(root).timeout(const Duration(seconds: 20)),
      );
      final window = await tester.runAsync(initializeDesktopWindow);
      expect(window!.backgroundColor.a, 0);
      debugPrint('SHELL_MOTION transparent window ready');
      await setMotionWindowMaximized(tester, true);
      final semantics = tester.ensureSemantics();
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      final storage = AgentStorage(path: ':memory:');
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        storage: storage,
      );
      final mode = Platform.environment['LILYGOBOX_MOTION_CASE'] ?? 'both';
      final loadedChat = mode == 'loaded-chat';
      final count = loadedChat
          ? 24
          : int.parse(Platform.environment['LILYGOBOX_MOTION_CARDS'] ?? '3000');
      expect(count, greaterThanOrEqualTo(4));
      final fixture = await seedMotionCanvas(
        storage,
        count,
        fullHistory: loadedChat,
        recycleCount: loadedChat ? 5000 : 0,
        recycledMessages: loadedChat
            ? int.parse(
                Platform.environment['LILYGOBOX_MOTION_RECYCLED_MESSAGES'] ??
                    '2',
              )
            : 0,
      );
      late final AiWorkspaceProvider graph;
      final nativeWindow = _ProfileWindow();
      final navigation = AppNavigationProvider();
      final devices = DeviceManagerProvider(preferences: scope.preferences);
      final info = PackageInfoProvider();
      final updates = _OfflineUpdates(info);
      final clock = Stopwatch()..start();
      final report = <String, dynamic>{};
      binding.reportData = report;
      Future<void> rest() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await binding.endOfFrame;
      }

      Future<void> wheel(Offset point, double delta) =>
          tester.sendEventToBinding(
            PointerScrollEvent(
              viewId: tester.view.viewId,
              timeStamp: clock.elapsed,
              kind: PointerDeviceKind.mouse,
              position: point,
              scrollDelta: Offset(0, delta),
            ),
          );

      Timer? restoreHeartbeat;
      try {
        await binding.watchPerformance(() async {
          final restoring = Stopwatch()..start();
          var previousPulse = 0;
          var longestGap = 0;
          void sampleEventLoop() {
            final now = restoring.elapsedMicroseconds;
            longestGap = math.max(longestGap, now - previousPulse);
            previousPulse = now;
          }

          restoreHeartbeat = Timer.periodic(
            const Duration(milliseconds: 16),
            (_) => sampleEventLoop(),
          );
          graph = AiWorkspaceProvider(scope.provider);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: scope.preferences),
                ChangeNotifierProvider.value(value: scope.provider),
                ChangeNotifierProvider.value(value: graph),
                ChangeNotifierProvider.value(value: theme),
                ChangeNotifierProvider.value(value: language),
                ChangeNotifierProvider.value(value: shell),
                ChangeNotifierProvider.value(value: split),
                ChangeNotifierProvider.value(value: navigation),
                ChangeNotifierProvider<WindowProvider>.value(
                  value: nativeWindow,
                ),
                ChangeNotifierProvider.value(value: devices),
                ChangeNotifierProvider.value(value: info),
                ChangeNotifierProvider<AppUpdateProvider>.value(value: updates),
              ],
              child: const LilygoBoxApp(),
            ),
          );
          report['shell_first_workspace_frame_ms'] =
              restoring.elapsedMilliseconds;
          await graph.initialized;
          expect(graph.sessions, hasLength(count));
          report['shell_database_restore_ms'] = restoring.elapsedMilliseconds;
          await waitForMotionCards(tester);
          sampleEventLoop();
          restoreHeartbeat!.cancel();
          report['shell_restore_max_ui_event_gap_ms'] = longestGap / 1000;
          report['shell_restore_to_cards_ms'] = restoring.elapsedMilliseconds;
        }, reportKey: 'shell_cold_restore_canvas');
        await rest();
        expect(
          tester
              .widget<AppWindowFrame>(find.byType(AppWindowFrame))
              .isMaximized,
          isTrue,
        );
        expect(find.byKey(const ValueKey('sidebar-home')), findsOneWidget);
        expect(window.backgroundColor.a, 255);
        final transfer = AgentStorageController(graph);
        try {
          await transfer.import(await transfer.inspect(motionPackagePath()));
        } finally {
          transfer.dispose();
        }
        await rest();
        final chatId = graph.importedAgentIds.single;
        final messageCount = graph.find(chatId)!.assistant.messages.length;
        expect(messageCount, 10000);
        expect(graph.sessions, hasLength(count + 1));
        if (loadedChat) {
          expect(
            graph.sessions.map((agent) => agent.assistant.messages.length),
            everyElement(10000),
          );
          expect(graph.recycledAgents, hasLength(5000));
          expect(
            graph.recycledAgents.first.record['conversation']['messages'],
            hasLength(fixture['messages_per_recycled_agent']!),
          );
        }
        report.addAll({
          ...fixture,
          'all_active_messages': graph.sessions.fold<int>(
            0,
            (count, agent) => count + agent.assistant.messages.length,
          ),
          'canvas_nodes': count + 1,
          'chat_messages': messageCount,
          'physical_width': tester.view.physicalSize.width,
          'physical_height': tester.view.physicalSize.height,
          'dpr': tester.view.devicePixelRatio,
          'refresh_rate': tester.view.display.refreshRate,
          'renderer': ui.ImageFilter.isShaderFilterSupported
              ? 'Impeller'
              : 'Skia',
          'maximized': nativeWindow.isMaximized,
          'native_background_alpha': window.backgroundColor.a,
          'semantics_enabled': binding.semanticsEnabled,
        });
        final canvas = find.byKey(const ValueKey('task-topology-canvas'));
        final transform = tester
            .widget<InteractiveViewer>(canvas)
            .transformationController!;
        Future<void> frameCard(String id, double scale) async {
          final position = graph.canvasPositions[id]!;
          final size = tester.getSize(canvas);
          transform.value = Matrix4.translationValues(
            size.width * .12 - position[0] * scale,
            size.height * .32 - position[1] * scale,
            0,
          )..scaleByDouble(scale, scale, 1, 1);
          await rest();
        }

        Finder card(String id) => find.byKey(ValueKey('topology-node-$id'));
        if (mode != 'chat' && !loadedChat) {
          const grabbedId = '1000-2';
          const neighborId = '1000-3';
          await frameCard(grabbedId, .25);
          final canvasCenter = tester.getCenter(canvas);
          final beforePan = transform.toScene(canvasCenter);
          await binding.watchPerformance(() async {
            for (var event = 0; event < 36; event++) {
              await wheel(canvasCenter, 55);
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
            await rest();
          }, reportKey: 'shell_canvas_overview_wheel');
          final pan = (transform.toScene(canvasCenter) - beforePan).dy * .25;
          report['shell_overview_travel_px'] = pan;
          expect(pan, greaterThan(1000));
          const scale = .7;
          await frameCard(grabbedId, scale);
          await tester.tap(card(grabbedId), kind: PointerDeviceKind.mouse);
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
          await tester.tap(card(neighborId), kind: PointerDeviceKind.mouse);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.keyA,
            physicalKey: PhysicalKeyboardKey.keyA,
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
          await rest();
          final initial = Map.of(graph.canvasPositions);
          final picked = tester.renderObject<RenderBox>(card(grabbedId));
          final neighbor = tester.renderObject<RenderBox>(card(neighborId));
          const grab = Offset(90, 52);
          var pointer = picked.localToGlobal(grab);
          final spacing =
              neighbor.localToGlobal(Offset.zero) -
              picked.localToGlobal(Offset.zero);
          final trace = <List<num>>[];
          await binding.watchPerformance(() async {
            final drag = await tester.startGesture(
              pointer,
              kind: PointerDeviceKind.mouse,
            );
            final timer = Stopwatch()..start();
            void sample() {
              trace.add([
                timer.elapsedMicroseconds,
                (picked.localToGlobal(grab) - pointer).distance,
                (neighbor.localToGlobal(Offset.zero) -
                        picked.localToGlobal(Offset.zero) -
                        spacing)
                    .distance,
              ]);
            }

            try {
              pointer += const Offset(24, 8);
              await drag.moveTo(pointer);
              await binding.endOfFrame;
              for (var event = 0; event < 12; event++) {
                await wheel(pointer, 40);
                pointer += const Offset(4, 2);
                await drag.moveTo(pointer);
                await binding.endOfFrame;
                sample();
              }
              final lastWheel = Stopwatch()..start();
              while (lastWheel.elapsedMilliseconds < 250) {
                await binding.endOfFrame;
                sample();
              }
            } finally {
              await drag.up();
              await rest();
            }
          }, reportKey: 'shell_selection_drag_wheel');
          final moved = initial.keys.where((id) {
            final before = initial[id]!;
            final after = graph.canvasPositions[id]!;
            return before[0] != after[0] || before[1] != after[1];
          }).length;
          report['shell_drag_moved_cards'] = moved;
          report['shell_drag_us_anchor_error_spacing_error'] = trace;
          expect(moved, count + 1);
          expect(
            trace.map((sample) => sample[1]).reduce(math.max),
            lessThan(.1),
          );
          expect(
            trace.map((sample) => sample[2]).reduce(math.max),
            lessThan(.1),
          );
        }
        if (mode != 'canvas') {
          await frameCard(chatId, 1);
          final open = find.byKey(ValueKey('topology-open-$chatId'));
          final chat = find.byKey(ValueKey('topology-chat-$chatId'));
          final viewport = find.descendant(
            of: chat,
            matching: find.byKey(const ValueKey('ai-message-scroll')),
          );
          await binding.watchPerformance(() async {
            final start = Stopwatch()..start();
            await tester.tap(open, kind: PointerDeviceKind.mouse);
            await binding.endOfFrame;
            report['shell_open_first_frame_ms'] = start.elapsedMilliseconds;
            await rest();
          }, reportKey: 'shell_open_chat');
          expect(graph.activeConversationId, chatId);
          expect(viewport, findsOneWidget);
          final bar = tester.widget<ChatHistoryScrollbar>(
            find.descendant(
              of: chat,
              matching: find.byType(ChatHistoryScrollbar),
            ),
          );
          final targetMessage = loadedChat ? 3630 : 4106;
          bar.seek((targetMessage - .5) / messageCount, true);
          await rest();
          final bounds = tester.getRect(viewport);
          final bodies = find.descendant(
            of: chat,
            matching: find.byType(ChatMessageBody),
          );
          (String, RenderBox) pickAnchor() {
            return tester
                .elementList(bodies)
                .map(
                  (element) => (
                    (element.widget as ChatMessageBody).message.id,
                    element.findRenderObject()! as RenderBox,
                  ),
                )
                .reduce((first, second) {
                  double distance(RenderBox body) =>
                      (body.localToGlobal(Offset.zero).dy - bounds.center.dy)
                          .abs();
                  return distance(first.$2) <= distance(second.$2)
                      ? first
                      : second;
                });
          }

          final (middleId, middle) = pickAnchor();
          final middleNumber = int.parse(middleId.split('-').last);
          expect(
            middleNumber,
            inInclusiveRange(targetMessage - 2, targetMessage + 2),
          );
          report['shell_chat_initial_anchor'] = middleId;
          final single = <List<num>>[];
          final signals = <double>[];
          void captureWheel(PointerEvent event) {
            if (event is PointerScrollEvent) signals.add(event.scrollDelta.dy);
          }

          await withNativeMotionMouse(tester, bounds.center, (mouse) async {
            binding.pointerRouter.addGlobalRoute(captureWheel);
            try {
              await binding.watchPerformance(() async {
                final start = middle.localToGlobal(Offset.zero).dy;
                final timer = Stopwatch()..start();
                mouse.wheel();
                while (timer.elapsedMilliseconds < 450) {
                  await binding.endOfFrame;
                  single.add([
                    timer.elapsedMicroseconds,
                    middle.localToGlobal(Offset.zero).dy - start,
                  ]);
                }
              }, reportKey: 'shell_chat_single_wheel');
            } finally {
              binding.pointerRouter.removeGlobalRoute(captureWheel);
            }
          });
          report['shell_chat_single_us_px'] = single;
          report['shell_chat_native_wheel_deltas'] = signals;
          expect(signals, hasLength(1));
          final travel = -signals.single;
          expect(travel, greaterThan(0));
          expect(single.last[1], closeTo(travel, 1));
          expect(
            single
                .where((frame) => frame[1] > 0 && frame[1] < travel - 1)
                .map((frame) => frame[1])
                .toSet()
                .length,
            greaterThan(2),
          );
          final burst = <List<num>>[];
          final firstLoaded = tester
              .widget<ChatMessageBody>(bodies.first)
              .message
              .id;
          var anchor = pickAnchor().$2;
          var lastY = anchor.localToGlobal(Offset.zero).dy;
          var displacement = 0.0;
          final before = bar.readLogicalFraction();
          final timer = Stopwatch();
          void sample(List<List<num>> trace) {
            expect(anchor.attached, isTrue);
            final currentY = anchor.localToGlobal(Offset.zero).dy;
            displacement += currentY - lastY;
            lastY = currentY;
            if ((currentY - bounds.center.dy).abs() > bounds.height * .4) {
              anchor = pickAnchor().$2;
              lastY = anchor.localToGlobal(Offset.zero).dy;
            }
            trace.add([timer.elapsedMicroseconds, displacement]);
          }

          Future<void> framesFor(
            int milliseconds,
            List<List<num>> trace,
          ) async {
            final interval = Stopwatch()..start();
            do {
              await binding.endOfFrame;
              sample(trace);
            } while (interval.elapsedMilliseconds < milliseconds);
          }

          await binding.watchPerformance(() async {
            timer.start();
            for (var event = 0; event < 64; event++) {
              await wheel(bounds.center, -65);
              await framesFor(30, burst);
            }
            await framesFor(280, burst);
          }, reportKey: 'shell_chat_burst_across_history_windows');
          report['shell_chat_burst_us_px'] = burst;
          report['shell_chat_first_message_before'] = firstLoaded;
          final afterFirst = tester
              .widget<ChatMessageBody>(bodies.first)
              .message
              .id;
          report['shell_chat_first_message_after'] = afterFirst;
          report['shell_chat_burst_messages_travelled'] =
              (before - bar.readLogicalFraction()) * messageCount;
          expect(afterFirst, isNot(firstLoaded));
          expect(displacement, greaterThan(3500));
          for (final samples in [single, burst]) {
            for (var frame = 1; frame < samples.length; frame++) {
              expect(
                samples[frame][1],
                greaterThanOrEqualTo(samples[frame - 1][1] - .5),
              );
            }
          }
          if (loadedChat) {
            Future<void> resetTrace() async {
              bar.seek((targetMessage - .5) / messageCount, true);
              await rest();
              anchor = pickAnchor().$2;
              lastY = anchor.localToGlobal(Offset.zero).dy;
              displacement = 0;
              timer.reset();
            }

            await resetTrace();
            final paused = <List<num>>[];
            final events = <List<num>>[];
            void captureBurst(PointerEvent event) {
              if (event is PointerScrollEvent) {
                events.add([
                  event.timeStamp.inMicroseconds,
                  event.scrollDelta.dy,
                ]);
              }
            }

            await withNativeMotionMouse(tester, bounds.center, (mouse) async {
              binding.pointerRouter.addGlobalRoute(captureBurst);
              try {
                await binding.watchPerformance(() async {
                  timer.reset();
                  for (final delay in [28, 28, 145, 28, 28, 350]) {
                    mouse.wheel();
                    await framesFor(delay, paused);
                  }
                }, reportKey: 'shell_chat_native_pause_resume');
              } finally {
                binding.pointerRouter.removeGlobalRoute(captureBurst);
              }
            });
            report['shell_chat_pause_resume_native_us_dy'] = List.of(events);
            report['shell_chat_pause_resume_us_px'] = paused;
            expect(events, hasLength(6));
            double expectedWheelTravel() {
              final acceleration = WheelScrollAcceleration();
              return events.fold<double>(0, (sum, event) {
                final time = Duration(microseconds: event[0].toInt());
                final delta = Offset(0, event[1].toDouble());
                return sum - acceleration.apply(delta, time).dy;
              });
            }

            expect(displacement, closeTo(expectedWheelTravel(), 1));
            await resetTrace();
            final rapid = <List<num>>[];
            final rapidStartId = tester
                .widget<ChatMessageBody>(bodies.first)
                .message
                .id;
            events.clear();
            await withNativeMotionMouse(tester, bounds.center, (mouse) async {
              binding.pointerRouter.addGlobalRoute(captureBurst);
              try {
                await binding.watchPerformance(() async {
                  timer.reset();
                  final tail = Stopwatch();
                  Future<void> sendBurst() async {
                    for (var index = 0; index < 48; index++) {
                      mouse.wheel();
                      await Future<void>.delayed(
                        const Duration(milliseconds: 8),
                      );
                    }
                  }

                  Future<void> captureFrames() async {
                    do {
                      await binding.endOfFrame;
                      sample(rapid);
                    } while (!tail.isRunning || tail.elapsedMilliseconds < 350);
                  }

                  await Future.wait([
                    sendBurst().whenComplete(tail.start),
                    captureFrames(),
                  ]);
                }, reportKey: 'shell_chat_native_rapid_burst');
              } finally {
                binding.pointerRouter.removeGlobalRoute(captureBurst);
              }
            });
            report['shell_chat_rapid_native_us_dy'] = events;
            report['shell_chat_rapid_us_px'] = rapid;
            final rapidEndId = tester
                .widget<ChatMessageBody>(bodies.first)
                .message
                .id;
            report['shell_chat_rapid_first_messages'] = [
              rapidStartId,
              rapidEndId,
            ];
            expect(rapidEndId, isNot(rapidStartId));
            expect(events, hasLength(48));
            expect(events.map((event) => event[1]), everyElement(lessThan(0)));
            expect(displacement, closeTo(expectedWheelTravel(), 1));
            await resetTrace();
            final middleScroll = <List<num>>[];
            final middleEvents = <String>[];
            int? middlePointer;
            void captureMiddle(PointerEvent event) {
              if (event is PointerDownEvent &&
                  event.buttons == kMiddleMouseButton) {
                middlePointer = event.pointer;
                middleEvents.add('down');
              } else if (event.pointer == middlePointer &&
                  event is PointerMoveEvent &&
                  event.buttons == kMiddleMouseButton) {
                middleEvents.add('move');
              } else if (event.pointer == middlePointer &&
                  event is PointerUpEvent) {
                middleEvents.add('up');
              }
            }

            await withNativeMotionMouse(tester, bounds.center, (mouse) async {
              binding.pointerRouter.addGlobalRoute(captureMiddle);
              try {
                await binding.watchPerformance(() async {
                  timer.reset();
                  Future<void> waitFor(String event) async {
                    final deadline = Stopwatch()..start();
                    while (!middleEvents.contains(event) &&
                        deadline.elapsedMilliseconds < 2000) {
                      await binding.endOfFrame;
                      sample(middleScroll);
                    }
                    expect(middleEvents, contains(event));
                  }

                  mouse.middleDown();
                  await waitFor('down');
                  mouse.middleMove(const Offset(0, -54));
                  await waitFor('move');
                  await framesFor(500, middleScroll);
                  mouse.middleUp();
                  await waitFor('up');
                  final whenReleased = displacement;
                  await framesFor(160, middleScroll);
                  expect(displacement, closeTo(whenReleased, .5));
                }, reportKey: 'shell_chat_middle_auto_scroll');
              } finally {
                binding.pointerRouter.removeGlobalRoute(captureMiddle);
              }
            });
            report['shell_chat_native_middle_events'] = middleEvents;
            report['shell_chat_middle_us_px'] = middleScroll;
            expect(displacement, greaterThan(100));
            for (final trace in [paused, rapid, middleScroll]) {
              for (var index = 1; index < trace.length; index++) {
                expect(
                  trace[index][1],
                  greaterThanOrEqualTo(trace[index - 1][1] - .5),
                );
              }
            }
          }
          await binding.watchPerformance(() async {
            await tester.tap(
              find.byKey(const ValueKey('topology-back')),
              kind: PointerDeviceKind.mouse,
            );
            await rest();
          }, reportKey: 'shell_return_to_canvas');
          expect(graph.activeConversationId, isNull);
          expect(canvas, findsOneWidget);
        }
        await setMotionWindowMaximized(tester, false);
        await rest();
        expect(nativeWindow.isMaximized, isFalse);
        expect(window.backgroundColor.a, 0);
        await setMotionWindowMaximized(tester, true);
        await rest();
        expect(nativeWindow.isMaximized, isTrue);
        expect(window.backgroundColor.a, 255);
        expect(tester.takeException(), isNull);
      } finally {
        restoreHeartbeat?.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        await graph.flush();
        graph.dispose();
        scope.dispose();
        await storage.close();
        updates.dispose();
        info.dispose();
        nativeWindow.dispose();
        devices.dispose();
        navigation.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
