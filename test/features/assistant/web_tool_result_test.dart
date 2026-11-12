import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/web_failure.dart';

import 'assistant_test_scope.dart';

void main() {
  for (final entry in {
    'http://example.com': AiWebProblem.unsupportedScheme,
    'https://127.0.0.1/': AiWebProblem.blockedAddress,
  }.entries) {
    test(
      'web failure is retained in history and details: ' + entry.value.name,
      () async {
        final theme = ThemeProvider();
        final language = LanguageProvider();
        final shell = AppShellProvider();
        final split = SplitViewProvider();
        final requests = <Map<String, dynamic>>[];
        final scope = await createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: split,
          client: MockClient((request) async {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': requests.length == 1
                        ? {
                            'content': null,
                            'tool_calls': [
                              {
                                'id': 'web-call',
                                'type': 'function',
                                'function': {
                                  'name': 'read_webpage',
                                  'arguments': jsonEncode({'url': entry.key}),
                                },
                              },
                            ],
                          }
                        : {'content': 'The webpage could not be read.'},
                  },
                ],
              }),
              200,
            );
          }),
        );
        addTearDown(() {
          scope.dispose();
          theme.dispose();
          language.dispose();
          shell.dispose();
          split.dispose();
        });
        await scope.provider.initialized;
        await scope.provider.saveService(
          name: 'Test',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test',
          models: ['test'],
          apiKey: 'key',
        );
        await scope.provider.sendMessage('Read this page');
        expect(requests, hasLength(2));
        final toolResult = (requests.last['messages'] as List)
            .where((message) => message['role'] == 'tool')
            .single;
        final result = jsonDecode(toolResult['content'] as String);
        expect(result['ok'], isFalse);
        expect(result['error_code'], entry.value.name);
        final step = scope.provider.messages.last.processingSteps.single;
        expect(step.succeeded, isFalse);
        expect(step.webFailure?.problem, entry.value);
        final event = scope.provider.messages.last.processEvents
            .where((event) => event.type == AiProcessEventType.action)
            .single;
        expect(event.action?.webFailure?.problem, entry.value);
        expect(event.operationId, isNotNull);
        expect(event.action?.output, toolResult['content']);
      },
    );
  }
}
