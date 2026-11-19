import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_history_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/message_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';

Future<Map<String, dynamic>> _sourceConversation() async {
  const path = String.fromEnvironment('CHAT_PERF_PAYLOAD');
  if (path.isEmpty) throw ArgumentError('Provide a copied CHAT_PERF_PAYLOAD');
  final payload = path.endsWith('.7z')
      ? await AgentPackage.read(path)
      : jsonDecode(await File(path).readAsString()) as Map;
  final sessions = ((payload['workflow'] as Map)['sessions'] as List)
      .cast<Map>();
  return Map<String, dynamic>.from(sessions.first['conversation'] as Map);
}

Map<String, dynamic> _scaledConversation(
  Map<String, dynamic> source,
  int count,
) {
  if (count == 0) return source;
  final sourceMessages = (source['messages'] as List).cast<Map>();
  if (count == 1) {
    final longest = sourceMessages
        .map((message) => message['content'] as String)
        .reduce(
          (first, second) => first.length >= second.length ? first : second,
        );
    return {
      'messages': [
        ConversationCodec.message(
          AiMessage(
            id: 'single-extreme-message',
            role: 'assistant',
            content: List.filled(12, longest).join('\n\n'),
          ),
        ),
      ],
      'history': <Map<String, Object?>>[],
    };
  }
  final prototype = ConversationCodec.message(
    const AiMessage(id: 'fixture', role: 'assistant', content: ''),
  );
  return {
    'messages': List.generate(count, (index) {
      final original = sourceMessages[index % sourceMessages.length];
      return {
        ...prototype,
        'id': 'stress-$count-$index',
        'role': original['role'],
        'content': original['content'],
        'createdAt': original['createdAt'],
      };
    }, growable: false),
    'history': <Map<String, Object?>>[],
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile exact-height history windows at large message counts', (
    tester,
  ) async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final navigation = AppNavigationProvider();
    final scope = (await tester.runAsync(
      () => createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
      ),
    ))!;
    await tester.runAsync(() => scope.provider.initialized);
    final source = (await tester.runAsync(_sourceConversation))!;
    final fixtureReports = <Map<String, Object?>>[];
    final semantics = tester.ensureSemantics();
    Future<void> frames([int count = 20]) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }

    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: language),
            ChangeNotifierProvider.value(value: navigation),
            ChangeNotifierProvider.value(value: scope.provider),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationDelegates,
            scrollBehavior: const AppScrollBehavior(),
            theme: ThemeData(
              colorScheme: theme.themeData.materialColors,
              scrollbarTheme: const ScrollbarThemeData(
                crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
              ),
            ),
            home: const Scaffold(body: AssistantPage()),
          ),
        ),
      );
      await frames();
      final handle = (await tester.runAsync(
        () =>
            const MethodChannel('lilygobox/window_layout')
                .invokeMethod<int>('getWindowHandle'),
      ))!;
      final isMaximized = ffi.DynamicLibrary.open('user32.dll')
          .lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
            'IsZoomed',
          );
      if (isMaximized(handle) == 0) {
        await tester.runAsync(
          () =>
              const MethodChannel('lilygobox/window_layout')
                  .invokeMethod<void>('toggleMaximize'),
        );
      }
      await frames(60);
      expect(isMaximized(handle), isNot(0));
      binding.reportData = <String, dynamic>{};
      final time = Stopwatch()..start();
      const countConfig = String.fromEnvironment(
        'CHAT_PERF_COUNTS',
        defaultValue: '0,1,10000,100000,1000000',
      );
      for (final count in countConfig.split(',').map(int.parse)) {
        debugPrint('CHAT_HISTORY_SETUP count=$count');
        final loading = Stopwatch()..start();
        await tester.runAsync(() async {
          scope.provider.clearConversation();
          scope.provider.restoreWorkspaceConversation(
            _scaledConversation(source, count),
          );
        });
        final restoringMs = loading.elapsedMicroseconds / 1000;
        await frames(40);
        final finder = find.byKey(const ValueKey('ai-message-scroll'));
        final scroll = tester.widget<SingleChildScrollView>(finder).controller!;
        final history = tester.state<ChatHistoryWindowState>(
          find.byType(ChatHistoryWindow),
        );
        final report = <String, Object?>{
          'message_count': scope.provider.messages.length,
          'source': count == 0
              ? 'complete_exported_conversation'
              : count == 1
              ? 'repeated_longest_exported_message'
              : 'restored_message_models_using_exported_text',
          'persisted_million_messages': false,
          'initial_mounted_messages': history.loadedMessageCount,
          'restore_ms': restoringMs,
          'resident_memory_bytes': ProcessInfo.currentRss,
          'physical_width': tester.view.physicalSize.width,
          'physical_height': tester.view.physicalSize.height,
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'refresh_rate': tester.view.display.refreshRate,
          'maximized': isMaximized(handle) != 0,
          'initial_extent': scroll.position.maxScrollExtent,
        };
        expect(scroll.position.maxScrollExtent, greaterThan(1000));
        scroll.jumpTo(scroll.position.maxScrollExtent * .55);
        await frames();
        final point = tester.getCenter(finder);
        debugPrint('CHAT_HISTORY_MEASURE count=$count');
        await binding.watchPerformance(() async {
          var minimum = scroll.offset;
          var maximum = minimum;
          for (var event = 0; event < 64; event++) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                viewId: tester.view.viewId,
                position: point,
                scrollDelta: Offset(0, event < 32 ? -48 : 48),
                timeStamp: time.elapsed,
                kind: PointerDeviceKind.mouse,
              ),
            );
            await frames(2);
            if (scroll.offset < minimum) minimum = scroll.offset;
            if (scroll.offset > maximum) maximum = scroll.offset;
          }
          await frames(16);
          report['scroll_minimum'] = minimum;
          report['scroll_maximum'] = maximum;
          report['final_mounted_messages'] = history.loadedMessageCount;
          expect(maximum - minimum, greaterThan(1000));
          expect(
            scope.provider.messages.length,
            count > 1
                ? count
                : count == 1
                ? 1
                : (source['messages'] as List).length,
          );
        }, reportKey: 'chat_history_$count');
        if (count > 1) {
          scroll.jumpTo(scroll.position.viewportDimension * 4 + 400);
          await frames(6);
          String firstMountedId() => tester
              .widgetList<ChatMessageBody>(find.byType(ChatMessageBody))
              .first
              .message
              .id;
          final initialFirstId = firstMountedId();
          await binding.watchPerformance(() async {
            for (var event = 0; event < 64; event++) {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  viewId: tester.view.viewId,
                  position: point,
                  scrollDelta: const Offset(0, -64),
                  timeStamp: time.elapsed,
                  kind: PointerDeviceKind.mouse,
                ),
              );
              await frames(2);
            }
            await frames(16);
            report['preload_first_id_before'] = initialFirstId;
            report['preload_first_id_after'] = firstMountedId();
            report['preload_mounted_messages_after'] =
                history.loadedMessageCount;
            expect(firstMountedId(), isNot(initialFirstId));
            expect(scope.provider.messages.length, count);
          }, reportKey: 'chat_history_preload_$count');
        }
        fixtureReports.add(report);
      }
      binding.reportData!['fixtures'] = fixtureReports;
      binding.reportData!['scope'] =
          'production_chat_in_maximized_opaque_native_test_window';
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
      navigation.dispose();
    }
  });
}
