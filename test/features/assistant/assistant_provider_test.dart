/*
 * @Description: 验证 AI 的低风险设置工具调用会立即执行并返回结果。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 15:27:53
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

import 'assistant_test_scope.dart';

void main() {
  test(
    'keeps live reasoning, tool results and follow-up phases in order',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final splitView = SplitViewProvider();
      final stream = StreamController<List<int>>();
      final followup = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: splitView,
        client: MockClient.streaming((request, body) async {
          final bytes = await body.toBytes();
          requests.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
          if (requests.length == 1)
            return http.StreamedResponse(stream.stream, 200);
          await followup.future;
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': 'Done.',
                        'reasoning_content': 'Check the tool result.',
                      },
                    },
                  ],
                }),
              ),
            ),
            200,
          );
        }),
      );
      addTearDown(scope.dispose);
      addTearDown(theme.dispose);
      addTearDown(language.dispose);
      addTearDown(shell.dispose);
      addTearDown(splitView.dispose);
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      final send = scope.provider.sendMessage('Switch to dark.');
      void event(Map<String, Object?> delta) => stream.add(
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta},
            ],
          })}\n\n',
        ),
      );
      event({'reasoning_content': 'Inspect '});
      event({'reasoning_content': 'the setting.'});
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final live = scope.provider.messages.last;
      expect(live.createdAt, isNotNull);
      expect(scope.provider.messages.first.createdAt, isNotNull);
      expect(live.content, isEmpty);
      expect(
        live.processEvents.where(
          (event) =>
              event.type == AiProcessEventType.status &&
              event.status == AiResponseStatus.thinking,
        ),
        isEmpty,
      );
      expect(
        live.processEvents
            .where((event) => event.type == AiProcessEventType.reasoning)
            .single
            .text,
        'Inspect the setting.',
      );
      event({'content': 'I will update the theme.'});
      event({
        'tool_calls': [
          {
            'index': 0,
            'id': 'theme-call',
            'function': {'name': 'set_theme', 'arguments': '{"theme":"dark"}'},
          },
        ],
      });
      stream.add(utf8.encode('data: [DONE]\n\n'));
      await stream.close();
      for (var i = 0; i < 100 && requests.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(requests, hasLength(2));
      expect(theme.currentTheme, ThemeType.dark);
      expect(
        scope.provider.messages.last.status,
        AiResponseStatus.awaitingReply,
      );
      final history = requests.last['messages'] as List;
      final toolReply = history.whereType<Map>().firstWhere(
        (message) => message['role'] == 'assistant',
      );
      expect(toolReply['reasoning_content'], 'Inspect the setting.');
      followup.complete();
      await send;
      final reply = scope.provider.messages.last;
      expect(reply.content, 'Done.');
      expect(reply.createdAt, live.createdAt);
      expect(reply.copyWith(content: 'Updated').createdAt, live.createdAt);
      expect(
        reply.processEvents.map((event) => event.type),
        containsAllInOrder([
          AiProcessEventType.reasoning,
          AiProcessEventType.assistant,
          AiProcessEventType.action,
          AiProcessEventType.reasoning,
        ]),
      );
      expect(reply.processEvents.last.status, AiResponseStatus.completed);
      expect(
        reply.processEvents
            .where((event) => event.action != null)
            .single
            .action!
            .succeeded,
        isTrue,
      );
      expect(
        reply.processEvents
            .where((event) => event.type == AiProcessEventType.reasoning)
            .last
            .text,
        'Check the tool result.',
      );
      expect(
        reply.processEvents
            .map((event) => event.elapsed.inMicroseconds)
            .toList(),
        orderedEquals(
          reply.processEvents
              .map((event) => event.elapsed.inMicroseconds)
              .toList()
            ..sort(),
        ),
      );
      final previous = reply.processEvents;
      await scope.provider.sendMessage('Another question');
      expect(scope.provider.messages[1].processEvents, previous);
    },
  );

  for (final mode in [
    'single JSON character',
    'sparse SSE',
    'sparse SSE error',
  ]) {
    test('finishes output without starving the event loop: $mode', () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final splitView = SplitViewProvider();
      var requests = 0;
      Stream<List<int>> sparseStream() async* {
        for (final character in ['不', '能', '。']) {
          yield utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': character},
                },
              ],
            })}\n\n',
          );
          // 让每个单字分别排空，再接收下一次增量。
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (mode == 'sparse SSE error') {
            throw http.ClientException('Stream interrupted');
          }
        }
        yield utf8.encode('data: [DONE]\n\n');
      }

      final client = mode == 'single JSON character'
          ? MockClient((_) async {
              requests++;
              return http.Response.bytes(
                utf8.encode('{"choices":[{"message":{"content":"好"}}]}'),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            })
          : MockClient.streaming((_, body) async {
              await body.drain<void>();
              requests++;
              return http.StreamedResponse(
                sparseStream(),
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            });
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: splitView,
        client: client,
      );
      addTearDown(scope.dispose);
      addTearDown(theme.dispose);
      addTearDown(language.dispose);
      addTearDown(shell.dispose);
      addTearDown(splitView.dispose);
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      await scope.provider.sendMessage('Can you connect?');
      final reply = scope.provider.messages.last;
      expect(scope.provider.busy, isFalse);
      expect(requests, 1);
      expect(
        reply.content,
        mode == 'single JSON character'
            ? '好'
            : mode == 'sparse SSE error'
            ? '不'
            : '不能。',
      );
      expect(
        reply.status,
        mode == 'sparse SSE error'
            ? AiResponseStatus.failed
            : AiResponseStatus.completed,
      );
      expect(
        reply.requestError,
        mode == 'sparse SSE error' ? isA<http.ClientException>() : isNull,
      );
      // 本轮完成后事件循环及下一轮输入仍可工作。
      await Future<void>.delayed(Duration.zero);
      expect(scope.provider.canSendMessage, isTrue);
    });
  }

  test('stops an in-flight completion without surfacing an error', () async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final splitView = SplitViewProvider();
    final requestStarted = Completer<void>();
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      requestStarted.complete();
      final abortable = request as http.Abortable;
      await abortable.abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: client,
    );
    addTearDown(scope.dispose);
    addTearDown(theme.dispose);
    addTearDown(language.dispose);
    addTearDown(shell.dispose);
    addTearDown(splitView.dispose);

    await scope.provider.initialized;
    await scope.provider.saveService(
      name: 'DeepSeek',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.deepseek.com',
      models: ['deepseek-chat'],
      apiKey: 'test-secret',
    );
    final send = scope.provider.sendMessage('Write a long answer.');
    await requestStarted.future;

    scope.provider.stopGeneration();
    await send;

    expect(scope.provider.busy, isFalse);
    expect(scope.provider.error, isNull);
    expect(scope.provider.messages, hasLength(1));
  });

  test(
    'shows complete responses without typing delays and preserves pause',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final splitView = SplitViewProvider();
      final text =
          'A complete response shown without artificial typing delays.';
      final responseGate = Completer<void>();
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: splitView,
        client: MockClient((_) async {
          await responseGate.future;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': text},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(scope.dispose);
      addTearDown(theme.dispose);
      addTearDown(language.dispose);
      addTearDown(shell.dispose);
      addTearDown(splitView.dispose);

      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.test/v1',
        models: ['test-model'],
        apiKey: 'test-key',
      );
      final displayed = <String>[];
      scope.provider.addListener(() {
        if (scope.provider.messages.length > 1) {
          displayed.add(scope.provider.messages.last.content);
        }
      });
      final send = scope.provider.sendMessage('Reply immediately.');
      scope.provider.pauseGeneration();
      final pausedElapsed = scope.provider.messages.last.elapsed;
      responseGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(scope.provider.messages.last.content, isEmpty);
      expect(scope.provider.messages.last.elapsed, pausedElapsed);

      scope.provider.resumeGeneration();
      await send;
      expect(displayed.where((content) => content.isNotEmpty), isNotEmpty);
      expect(
        displayed.where((content) => content.isNotEmpty),
        everyElement(text),
      );
      expect(scope.provider.messages.last.content, text);
      expect(scope.provider.messages.last.elapsed, isNotNull);
    },
  );

  test(
    'applies a supported setting immediately without confirmation',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final splitView = SplitViewProvider();
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final body = requests.length == 1
            ? {
                'choices': [
                  {
                    'message': {
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'call-theme',
                          'type': 'function',
                          'function': {
                            'name': 'set_theme',
                            'arguments': '{"theme":"light"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              }
            : {
                'choices': [
                  {
                    'message': {'content': 'The light theme is now enabled.'},
                  },
                ],
              };
        return http.Response(jsonEncode(body), 200);
      });
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: splitView,
        client: client,
      );
      addTearDown(scope.dispose);
      addTearDown(theme.dispose);
      addTearDown(language.dispose);
      addTearDown(shell.dispose);
      addTearDown(splitView.dispose);

      while (!scope.provider.credentialLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
      await scope.provider.saveService(
        name: 'DeepSeek',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        models: ['deepseek-chat'],
        apiKey: 'test-secret',
      );
      await scope.provider.sendMessage('Please switch to the light theme.');

      expect(theme.currentTheme, ThemeType.light);
      expect(
        scope.provider.messages.last.content,
        'The light theme is now enabled.',
      );
      final reply = scope.provider.messages.last;
      expect(reply.elapsed, isNotNull);
      expect(reply.model, 'deepseek-chat');
      expect(reply.protocol, AiApiProtocol.openAiChatCompletions);
      expect(reply.processingSteps.single.name, 'set_theme');
      expect(reply.processingSteps.single.succeeded, isTrue);
      expect(
        scope.provider.messages.where((message) => message.toolName != null),
        isEmpty,
      );
      expect(requests, hasLength(2));
      final followUp = (requests.last['messages'] as List).last as Map;
      expect(followUp['role'], 'tool');
      expect(followUp['tool_call_id'], 'call-theme');
    },
  );

  test(
    'switching services uses their own keys and models and keeps history',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final splitView = SplitViewProvider();
      final requests = <http.Request>[];
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: splitView,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
          );
        }),
      );
      addTearDown(scope.dispose);
      addTearDown(theme.dispose);
      addTearDown(language.dispose);
      addTearDown(shell.dispose);
      addTearDown(splitView.dispose);
      await scope.provider.initialized;
      final first = await scope.provider.saveService(
        name: 'First',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://first.test',
        models: ['chat-a'],
        apiKey: 'key-a',
      );
      final second = await scope.provider.saveService(
        name: 'Second',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://second.test/v1',
        models: ['chat-b', 'reason-b'],
        apiKey: 'key-b',
      );
      await scope.provider.sendMessage('First message');
      expect(scope.provider.selectedService?.id, first);
      await scope.provider.selectModel(second, 'reason-b');
      expect(scope.provider.messages, hasLength(2));
      await scope.provider.sendMessage('Second message');
      expect(requests.first.url.host, 'first.test');
      expect(requests.first.headers['authorization'], 'Bearer key-a');
      expect(jsonDecode(requests.first.body)['model'], 'chat-a');
      expect(requests.last.url.path, '/v1/chat/completions');
      expect(requests.last.headers['authorization'], 'Bearer key-b');
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['model'], 'reason-b');
      final history = (body['messages'] as List).cast<Map>();
      expect(
        history
            .where((message) => message['role'] == 'user')
            .map((message) => message['content']),
        ['First message', 'Second message'],
      );
      expect(scope.provider.messages, hasLength(4));
    },
  );

  test('service edits during a reply apply to the next message only', () async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final splitView = SplitViewProvider();
    final requestStarted = Completer<void>();
    final releaseFirstResponse = Completer<void>();
    final requests = <http.Request>[];
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          requestStarted.complete();
          await releaseFirstResponse.future;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call-theme',
                        'type': 'function',
                        'function': {
                          'name': 'set_theme',
                          'arguments': '{"theme":"light"}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200);
      }),
    );
    addTearDown(scope.dispose);
    addTearDown(theme.dispose);
    addTearDown(language.dispose);
    addTearDown(shell.dispose);
    addTearDown(splitView.dispose);

    await scope.provider.initialized;
    final serviceId = await scope.provider.saveService(
      name: 'Original',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://original.test/v1',
      models: ['model-original'],
      apiKey: 'key-original',
    );
    final send = scope.provider.sendMessage('Change the theme.');
    await requestStarted.future;

    expect(scope.provider.busy, isTrue);
    expect(scope.provider.canChangeService, isTrue);
    expect(scope.provider.canSendMessage, isFalse);
    await scope.provider.saveService(
      id: serviceId,
      name: 'Updated',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://updated.test/v1',
      models: ['model-updated'],
      apiKey: 'key-updated',
    );
    expect(scope.provider.selectedModel, 'model-updated');

    releaseFirstResponse.complete();
    await send;
    expect(requests, hasLength(2));
    for (final request in requests.take(2)) {
      expect(request.url.host, 'original.test');
      expect(request.headers['authorization'], 'Bearer key-original');
      expect(jsonDecode(request.body)['model'], 'model-original');
    }

    await scope.provider.sendMessage('Use the updated service.');
    final nextRequest = requests.last;
    expect(nextRequest.url.host, 'updated.test');
    expect(nextRequest.headers['authorization'], 'Bearer key-updated');
    expect(jsonDecode(nextRequest.body)['model'], 'model-updated');
  });
}
