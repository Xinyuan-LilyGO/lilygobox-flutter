/*
 * @Description: 验证 AI 的设置工具调用必须经用户批准后才执行。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 14:52:13
 * @License: GPL 3.0
 */

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
  test('applies a proposed setting only after approval', () async {
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

    expect(theme.currentTheme, ThemeType.dark);
    final proposal = scope.provider.messages.last;
    expect(proposal.toolName, 'set_theme');
    expect(proposal.toolDecision, isNull);

    await scope.provider.resolveTool(proposal.id, approve: true);

    expect(theme.currentTheme, ThemeType.light);
    expect(
      scope.provider.messages.last.content,
      'The light theme is now enabled.',
    );
    expect(requests, hasLength(2));
    final followUp = (requests.last['messages'] as List).last as Map;
    expect(followUp['role'], 'tool');
    expect(followUp['tool_call_id'], 'call-theme');
  });

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
}
