/*
 * @Description: 验证 AI 的低风险设置工具调用会立即执行并返回结果。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-06 16:30:18
 * @License: GPL 3.0
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
