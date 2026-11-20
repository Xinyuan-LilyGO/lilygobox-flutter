import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/chat_history_search.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

import 'assistant_test_scope.dart';

void main() {
  test('searches and reads original messages removed from model context', () async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final splitView = SplitViewProvider();
    final requests = <Map<String, dynamic>>[];
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        if (requests.length == 1) {
          return http.Response(
            '{"choices":[{"message":{"content":"Earlier conversation summary."}}]}',
            200,
          );
        }
        if (requests.length == 2 || requests.length == 3) {
          final reading = requests.length == 3;
          final messages = (body['messages'] as List).cast<Map>();
          final id = reading
              ? (jsonDecode(messages.last['content'] as String)['matches']
                        as List)
                    .single['message_id']
              : null;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'id': reading
                            ? 'history-read-call'
                            : 'history-search-call',
                        'type': 'function',
                        'function': {
                          'name': reading
                              ? ChatHistorySearch.readTool
                              : ChatHistorySearch.searchTool,
                          'arguments': jsonEncode(
                            reading
                                ? {'message_id': id}
                                : {
                                    'role': 'user',
                                    'order': 'oldest',
                                    'limit': 1,
                                  },
                          ),
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
        return http.Response(
          '{"choices":[{"message":{"content":"Found the original message."}}]}',
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
    final serviceId = await scope.provider.saveService(
      name: 'Test',
      protocol: .openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test'],
      apiKey: 'key',
    );
    const original = 'The original needle is important.';
    final transcript = [
      for (var index = 0; index < 16; index++)
        AiMessage(
          id: 'message-$index',
          role: index.isEven ? 'user' : 'assistant',
          content: index == 0 ? original : 'Record $index',
        ),
    ];
    scope.provider.restoreWorkspaceConversation({
      'serviceId': serviceId,
      'model': 'test',
      'messages': transcript.map(ConversationCodec.message).toList(),
      'history': [
        for (final message in transcript)
          {'role': message.role, 'content': message.content},
      ],
    });
    await scope.provider.compactContext();
    await scope.provider.sendMessage('Look up my first message.');

    expect(requests, hasLength(4));
    expect(jsonEncode(requests[1]['messages']), isNot(contains(original)));
    expect(
      jsonEncode(requests[1]['messages']),
      contains('Earlier conversation summary.'),
    );
    final definitions = (requests[1]['tools'] as List).cast<Map>();
    expect(
      definitions.map((definition) => definition['function']['name']),
      containsAll([ChatHistorySearch.searchTool, ChatHistorySearch.readTool]),
    );
    final toolReply = (requests.last['messages'] as List)
        .whereType<Map>()
        .lastWhere((message) => message['role'] == 'tool');
    final result = jsonDecode(toolReply['content'] as String) as Map;
    expect(result['message']['content'], original);
    expect(result['message']['message_id'], 'message-0');
    expect(scope.provider.messages.last.content, 'Found the original message.');
    expect(
      scope.provider.messages.last.processingSteps.map((step) => step.name),
      [ChatHistorySearch.searchTool, ChatHistorySearch.readTool],
    );
  });
}
