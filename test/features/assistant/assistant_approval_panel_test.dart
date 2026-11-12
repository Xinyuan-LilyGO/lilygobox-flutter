import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

import 'assistant_test_scope.dart';

void main() {
  for (final dark in [false, true]) {
    for (final locale in ['en', 'zh']) {
      testWidgets(
        'approval replaces composer and preserves draft ($dark/$locale)',
        (tester) async {
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('approval-panel-'),
          ))!;
          final theme = ThemeProvider()
            ..setTheme(dark ? ThemeType.dark : ThemeType.light);
          final language = LanguageProvider();
          final shell = AppShellProvider();
          final split = SplitViewProvider();
          final awaiting = Completer<void>();
          final finalResponse = Completer<http.Response>();
          final written = List.generate(100, (i) => 'line $i').join('\n');
          var calls = 0;
          final scope = await createAssistantTestScope(
            theme: theme,
            language: language,
            shell: shell,
            splitView: split,
            client: MockClient((_) async {
              if (++calls > 1) return finalResponse.future;
              return http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': '',
                        'tool_calls': [
                          {
                            'id': 'write',
                            'type': 'function',
                            'function': {
                              'name': 'write_file',
                              'arguments': jsonEncode({
                                'path': '${root.path}/output.txt',
                                'content': written,
                                'expected_content': null,
                              }),
                            },
                          },
                        ],
                      },
                    },
                  ],
                }),
                200,
              );
            }),
          );
          final input = TextEditingController(text: 'unsent draft');
          final focus = FocusNode();
          final scroll = ScrollController();
          final attachment = AiImageAttachment(
            name: 'draft.png',
            mimeType: 'image/png',
            bytes: (await tester.runAsync(
              () => File(
                'assets/images/branding/lilygobox_app_icon.png',
              ).readAsBytes(),
            ))!,
          );
          addTearDown(() async {
            scope.dispose();
            theme.dispose();
            language.dispose();
            shell.dispose();
            split.dispose();
            input.dispose();
            focus.dispose();
            scroll.dispose();
            await tester.runAsync(() => root.delete(recursive: true));
          });
          await scope.provider.initialized;
          await scope.provider.saveService(
            name: 'Test',
            protocol: AiApiProtocol.openAiChatCompletions,
            baseUrl: 'https://example.test/v1',
            models: ['test'],
            apiKey: 'key',
          );
          scope.provider.addListener(() {
            if (scope.provider.pendingApproval != null && !awaiting.isCompleted)
              awaiting.complete();
          });
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              scrollBehavior: const AppScrollBehavior(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: 450,
                    child: ListenableBuilder(
                      listenable: scope.provider,
                      builder: (context, _) => ChatComposer(
                        input: input,
                        focusNode: focus,
                        scrollController: scroll,
                        theme: theme.themeData,
                        assistant: scope.provider,
                        ready: true,
                        onSend: (_) {},
                        attachments: [attachment],
                        onAttachmentsChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          focus.requestFocus();
          await tester.pump();
          final sending = scope.provider.sendMessage('Write file');
          for (var i = 0; !awaiting.isCompleted && i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          expect(awaiting.isCompleted, isTrue);
          await scope.provider.sendMessage('queued message');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final approvalFade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('ai-approval-panel')),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(approvalFade.opacity.value, inExclusiveRange(0, 1));
          expect(focus.hasFocus, isFalse);
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(TextField), findsNothing);
          expect(
            find.byKey(const ValueKey('ai-approval-panel')),
            findsOneWidget,
          );
          expect(focus.hasFocus, isFalse);
          expect(
            scope.provider.pendingGuidance.single.content,
            'queued message',
          );
          expect(
            scope.provider.messages.where((m) => m.toolName != null),
            isEmpty,
          );
          final allow = find.byKey(const ValueKey('ai-approval-allow'));
          final deny = find.byKey(const ValueKey('ai-approval-deny'));
          expect(tester.getRect(allow).bottom, lessThanOrEqualTo(600));
          expect(tester.getRect(deny).bottom, lessThanOrEqualTo(600));
          await tester.tap(dark ? allow : deny);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final inputFade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('ai-composer-context-layer')),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(inputFade.opacity.value, inExclusiveRange(0, 1));
          expect(focus.hasFocus, isFalse);
          // 交替推进界面事件和真实文件 IO，等待下一轮模型请求。
          for (var i = 0; calls < 2 && i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          expect(calls, 2);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const ValueKey('ai-approval-panel')), findsNothing);
          expect(find.byType(TextField), findsOneWidget);
          expect(input.text, 'unsent draft');
          expect(focus.hasFocus, isFalse);
          final composer = tester.widget<ChatComposer>(
            find.byType(ChatComposer),
          );
          expect(composer.attachments.single, same(attachment));
          expect(
            scope.provider.pendingGuidance.single.content,
            'queued message',
          );
          expect(scope.provider.pendingApproval, isNull);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            expect(await File('${root.path}/output.txt').exists(), dark);
            scope.provider.stopGeneration();
            finalResponse.complete(
              http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'message': {'content': 'done'},
                    },
                  ],
                }),
                200,
              ),
            );
          });
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          unawaited(sending);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
