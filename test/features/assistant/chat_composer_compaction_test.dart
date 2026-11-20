import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'assistant_test_scope.dart';

void main() {
  testWidgets(
    'context metric shows compaction in place until right-click cancellation',
    (tester) async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient((request) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await responseGate.future;
          return http.Response(
            'data: {"choices":[{"delta":{"content":"summary"}}]}\n\n'
            'data: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final input = TextEditingController();
      final focus = FocusNode();
      final scroll = ScrollController();
      addTearDown(() {
        input.dispose();
        focus.dispose();
        scroll.dispose();
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
        if (!responseGate.isCompleted) responseGate.complete();
      });

      final serviceId = await scope.provider.saveService(
        name: 'Test service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await scope.provider.selectModel(serviceId, 'test-model');
      final transcript = [
        for (var index = 0; index < 16; index++)
          AiMessage(
            id: 'message-$index',
            role: index.isEven ? 'user' : 'assistant',
            content: 'History record $index',
          ),
      ];
      scope.provider.restoreWorkspaceConversation({
        'serviceId': serviceId,
        'model': 'test-model',
        'messages': [
          for (final message in transcript) ConversationCodec.message(message),
        ],
        'history': [
          for (final message in transcript)
            {'role': message.role, 'content': message.content},
        ],
      });

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 820,
                child: ChatComposer(
                  input: input,
                  focusNode: focus,
                  scrollController: scroll,
                  theme: theme.themeData,
                  assistant: scope.provider,
                  ready: true,
                  onSend: (_) {},
                  attachments: const [],
                  onAttachmentsChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final metric = find.byKey(const ValueKey('ai-context-usage-metric'));
      final indicator = find.descendant(
        of: metric,
        matching: find.byType(CircularProgressIndicator),
      );
      final inputSurface = find.byKey(
        const ValueKey('ai-composer-context-layer'),
      );
      final originalInputBounds = tester.getRect(inputSurface);
      final originalRatio = tester
          .widget<CircularProgressIndicator>(indicator)
          .value;
      expect(originalRatio, isNotNull);
      final menuAction = find.byKey(
        const ValueKey('ai-compaction-context-menu-action'),
      );
      await tester.tap(metric, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Compact now'), findsOneWidget);
      await tester.tap(find.text('Compact now'));
      await tester.pump();
      expect(find.text('Compact now'), findsNothing);
      expect(menuAction, findsNothing);
      final pending = scope.provider.compactContext();
      for (
        var attempt = 0;
        attempt < 20 && !requestStarted.isCompleted;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(requestStarted.isCompleted, isTrue);

      final status = find.descendant(
        of: metric,
        matching: find.text('Compacting context…'),
      );
      expect(status, findsOneWidget);
      expect(tester.widget<CircularProgressIndicator>(indicator).value, isNull);
      expect(tester.getRect(inputSurface), originalInputBounds);
      expect(
        find.byTooltip('Right-click to cancel compaction'),
        findsOneWidget,
      );
      expect(find.text('Cancel compaction'), findsNothing);
      await tester.tap(metric, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.descendant(
          of: menuAction,
          matching: find.text('Cancel compaction'),
        ),
        findsOneWidget,
      );
      await tester.tap(menuAction);
      await tester.pump();
      expect(menuAction, findsNothing);
      expect(find.text('Compact now'), findsNothing);
      expect(await pending, AiContextCompactionOutcome.cancelled);
      responseGate.complete();
      await tester.pump();
      expect(status, findsNothing);
      expect(
        tester.widget<CircularProgressIndicator>(indicator).value,
        originalRatio,
      );
      expect(tester.getRect(inputSurface), originalInputBounds);
    },
  );
}
