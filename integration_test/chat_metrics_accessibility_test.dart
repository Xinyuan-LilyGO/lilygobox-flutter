import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';
import 'fixtures/workspace_motion.dart';

List<int> _delta(String text) => utf8.encode(
  'data: ${jsonEncode({
    'choices': [
      {
        'delta': {'content': text},
      },
    ],
  })}\n\n',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await requestNativeAccessibility();
    final timeout = Stopwatch()..start();
    while (!PlatformDispatcher.instance.semanticsEnabled &&
        timeout.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    expect(PlatformDispatcher.instance.semanticsEnabled, isTrue);
  });
  testWidgets('maximized chat keeps metric details open across live compaction', (
    tester,
  ) async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final navigation = AppNavigationProvider();
    final input = StreamController<List<int>>();
    final resumed = StreamController<List<int>>();
    var replies = 0;
    final scope = (await tester.runAsync(() async {
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient.streaming((request, body) async {
          final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
          final first =
              (payload['messages'] as List).first['content'] as String;
          final stream = first.startsWith('Summarize')
              ? Stream.fromIterable([
                  _delta('An earlier conversation about route planning.'),
                  utf8.encode('data: [DONE]\n\n'),
                ])
              : ++replies == 1
              ? input.stream
              : resumed.stream;
          return http.StreamedResponse(
            stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final assistant = scope.provider;
      await assistant.initialized;
      final service = await assistant.saveService(
        name: 'Accessibility fixture',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await assistant.selectModel(service, 'test-model');
      assistant.restoreWorkspaceConversation({
        'messages': <Object?>[],
        'history': [
          for (var index = 0; index < 12; index++)
            {
              'role': index.isEven ? 'user' : 'assistant',
              'content': 'Earlier route $index ${'landmark ' * 35}',
            },
        ],
      });
      assistant.contextBudgetTokens = 5000;
      assistant.contextCompactionPercent = 70;
      return scope;
    }))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
      navigation.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: navigation),
          ChangeNotifierProvider.value(value: scope.provider),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationDelegates,
          scrollBehavior: const AppScrollBehavior(),
          home: const Scaffold(body: AssistantPage()),
        ),
      ),
    );
    Future<void> frames(int count) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }

    await frames(12);
    await setMotionWindowMaximized(tester, true);
    await frames(20);
    expect(PlatformDispatcher.instance.semanticsEnabled, isTrue);
    final assistant = scope.provider;
    final turn = assistant.sendMessage('Describe the route in Markdown.');
    const contextKey = ValueKey('ai-context-usage-metric');
    const cacheKey = ValueKey('ai-cache-usage-metric');
    final contextMetric = find.byKey(contextKey);
    final cacheMetric = find.byKey(cacheKey);
    final contextDetails = find.byKey(ValueKey('$contextKey-details'));
    final cacheDetails = find.byKey(ValueKey('$cacheKey-details'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(contextMetric));
    final initialUsage = assistant.estimatedContextTokens;
    input.add(
      _delta('## Route\n\n${'See [map](https://example.test).\n\n' * 22}'),
    );
    await frames(36);
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('ai-message-scroll')),
        )
        .controller!;
    await mouse.down(tester.getCenter(contextMetric));
    await mouse.up();
    await frames(12);
    expect(contextDetails, findsOneWidget);
    expect(assistant.estimatedContextTokens, greaterThan(initialUsage));
    expect(replies, 1);
    for (var section = 0; section < 40 && replies < 2; section++) {
      input.add(
        _delta(
          '### Section $section\n\n${'* Long paragraph with **details**.\n' * 18}\n',
        ),
      );
      await frames(3);
      expect(contextDetails, findsOneWidget);
      if (section == 6) {
        await frames(16);
        expect(replies, 1);
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
      }
    }
    await frames(20);
    expect(replies, 2);
    await input.close();
    expect(
      assistant.messages.where((message) => message.role == 'compaction'),
      hasLength(1),
    );
    resumed.add(_delta('Continued after compression.'));
    await frames(10);
    expect(contextDetails, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(4);
    expect(contextDetails, findsNothing);
    await mouse.moveTo(tester.getCenter(cacheMetric));
    await frames(36);
    await mouse.down(tester.getCenter(cacheMetric));
    await mouse.up();
    await frames(12);
    expect(cacheDetails, findsOneWidget);
    resumed.add(utf8.encode('data: [DONE]\n\n'));
    await resumed.close();
    await turn;
    await frames(12);
    expect(assistant.messages.last.content, 'Continued after compression.');
    expect(assistant.error, isNull);
    await mouse.removePointer();
  });
}
