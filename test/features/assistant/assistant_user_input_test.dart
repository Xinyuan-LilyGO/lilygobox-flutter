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
import 'package:lilygobox/features/assistant/domain/user_input.dart';

import 'assistant_test_scope.dart';
import 'user_input_test.dart' show questionArguments;

void main() {
  group('AiAssistantProvider user input', () {
    late AssistantTestScope scope;
    late ThemeProvider theme;
    late LanguageProvider language;
    late AppShellProvider shell;
    late SplitViewProvider split;
    late List<Map<String, dynamic>> requests;
    late Map<String, Object?> arguments;
    var questionCalls = 1;
    var disposed = false;

    setUp(() async {
      theme = ThemeProvider();
      language = LanguageProvider();
      shell = AppShellProvider();
      split = SplitViewProvider();
      requests = [];
      arguments = questionArguments();
      questionCalls = 1;
      disposed = false;
      scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (request.url.path.endsWith('/responses')) {
            return http.Response(
              jsonEncode({
                'output': requests.length <= questionCalls
                    ? [
                        {
                          'type': 'function_call',
                          'id': 'item-1',
                          'call_id': 'question-1',
                          'name': 'request_user_input',
                          'arguments': jsonEncode(arguments),
                        },
                      ]
                    : [
                        {
                          'type': 'message',
                          'id': 'item-2',
                          'role': 'assistant',
                          'content': [
                            {'type': 'output_text', 'text': 'Done'},
                          ],
                        },
                      ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': requests.length <= questionCalls
                      ? {
                          'content': '',
                          'tool_calls': [
                            {
                              'id': 'question-${requests.length}',
                              'type': 'function',
                              'function': {
                                'name': 'request_user_input',
                                'arguments': jsonEncode(arguments),
                              },
                            },
                          ],
                        }
                      : {'content': 'Done'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test-model'],
        apiKey: 'key',
      );
    });

    tearDown(() {
      if (!disposed) scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
    });

    Future<AiUserInputRequest> waitForQuestion({String? afterId}) {
      final ready = Completer<AiUserInputRequest>();
      void listener() {
        final request = scope.provider.pendingUserInput;
        if (!ready.isCompleted && request != null && request.id != afterId) {
          ready.complete(request);
        }
      }

      scope.provider.addListener(listener);
      listener();
      return ready.future.timeout(const Duration(seconds: 5)).whenComplete(() {
        scope.provider.removeListener(listener);
      });
    }

    Map<String, dynamic> toolResult() {
      final messages = requests.last['messages'] as List;
      return Map<String, dynamic>.from(
        messages.lastWhere((dynamic m) => m['role'] == 'tool') as Map,
      );
    }

    test(
      'should suspend the model and resume with the exact tool call answers',
      () async {
        final permissions = scope.provider.permissions;
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        expect(scope.provider.busy, isTrue);
        expect(requests, hasLength(1));
        expect(scope.provider.pendingApproval, isNull);
        final specs = requests.first['tools'] as List;
        expect(
          specs.any(
            (dynamic spec) => spec['function']['name'] == 'request_user_input',
          ),
          isTrue,
        );
        scope.provider.resolveUserInput(pending.id, {
          'format': ['JSON', 'Keep Unicode'],
        });
        await send.timeout(const Duration(seconds: 5));
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.busy, isFalse);
        expect(scope.provider.permissions, same(permissions));
        expect(toolResult()['tool_call_id'], 'question-1');
        expect(jsonDecode(toolResult()['content'] as String), {
          'cancelled': false,
          'answers': {
            'format': {
              'answers': ['JSON', 'Keep Unicode'],
            },
          },
        });
        expect(scope.provider.messages.last.content, 'Done');
      },
    );

    test(
      'should ignore stale answers and reject incomplete ones without dismissing',
      () async {
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        scope.provider.resolveUserInput('stale', {
          'format': ['Text'],
        });
        scope.provider.cancelUserInput('stale');
        expect(
          () => scope.provider.resolveUserInput(pending.id, {}),
          throwsFormatException,
        );
        expect(scope.provider.pendingUserInput, same(pending));
        scope.provider.resolveUserInput(pending.id, {
          'format': ['Custom CSV'],
        });
        scope.provider.resolveUserInput(pending.id, {
          'format': ['Text'],
        });
        await send;
        expect(
          jsonDecode(
            toolResult()['content'] as String,
          )['answers']['format']['answers'],
          ['Custom CSV'],
        );
        expect(requests, hasLength(2));
      },
    );

    test(
      'should return cancellation without granting permissions or leaving a waiter',
      () async {
        final permissions = scope.provider.permissions;
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        scope.provider.cancelUserInput(pending.id);
        await send.timeout(const Duration(seconds: 5));
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.permissions, same(permissions));
        expect(jsonDecode(toolResult()['content'] as String), {
          'cancelled': true,
          'answers': {},
        });
        expect(scope.provider.busy, isFalse);
      },
    );

    test(
      'should unblock stopping without starting another model request',
      () async {
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        scope.provider.stopGeneration();
        await send.timeout(const Duration(seconds: 5));
        scope.provider.resolveUserInput(pending.id, {
          'format': ['JSON'],
        });
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.busy, isFalse);
        expect(requests, hasLength(1));
        scope.provider.clearConversation();
        expect(scope.provider.messages, isEmpty);
      },
    );

    test(
      'should cancel a pending question when the provider is disposed',
      () async {
        final send = scope.provider.sendMessage('Ask me');
        await waitForQuestion();
        scope.dispose();
        disposed = true;
        await send.timeout(const Duration(seconds: 5));
        expect(requests, hasLength(1));
      },
    );

    test(
      'should serialize repeated questions and ignore answers for an older card',
      () async {
        questionCalls = 2;
        final send = scope.provider.sendMessage('Ask twice');
        final first = await waitForQuestion();
        scope.provider.resolveUserInput(first.id, {
          'format': ['JSON'],
        });
        final second = await waitForQuestion(afterId: first.id);
        scope.provider.resolveUserInput(first.id, {
          'format': ['Text'],
        });
        expect(scope.provider.pendingUserInput, same(second));
        scope.provider.resolveUserInput(second.id, {
          'format': ['Text'],
        });
        await send.timeout(const Duration(seconds: 5));
        expect(requests, hasLength(3));
        expect(toolResult()['tool_call_id'], 'question-2');
      },
    );

    test(
      'should resume Responses with the original call id and structured answer',
      () async {
        final serviceId = await scope.provider.saveService(
          name: 'Responses',
          protocol: AiApiProtocol.openAiResponses,
          baseUrl: 'https://example.test/v1',
          models: ['test-model'],
          apiKey: 'key',
        );
        await scope.provider.selectModel(serviceId, 'test-model');
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        scope.provider.resolveUserInput(pending.id, {
          'format': ['JSON'],
        });
        await send.timeout(const Duration(seconds: 5));
        final input = requests.last['input'] as List;
        final result =
            input.singleWhere(
                  (dynamic item) => item['type'] == 'function_call_output',
                )
                as Map;
        expect(result['call_id'], 'question-1');
        expect(jsonDecode(result['output'] as String), {
          'cancelled': false,
          'answers': {
            'format': {
              'answers': ['JSON'],
            },
          },
        });
        expect(scope.provider.messages.last.content, 'Done');
      },
    );

    test(
      'should cancel the pending question before applying queued guidance',
      () async {
        final send = scope.provider.sendMessage('Ask me');
        final pending = await waitForQuestion();
        await scope.provider.sendMessage('Use the existing defaults');
        final queuedId = scope.provider.pendingGuidance.single.id;
        await scope.provider.guidePendingMessage(queuedId);
        await send.timeout(const Duration(seconds: 5));
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.busy, isFalse);
        expect(requests, hasLength(2));
        scope.provider.resolveUserInput(pending.id, {
          'format': ['JSON'],
        });
        expect(scope.provider.pendingUserInput, isNull);
        expect(scope.provider.messages.last.content, 'Done');
      },
    );

    test(
      'should return malformed arguments as a tool failure without waiting',
      () async {
        arguments = {'questions': []};
        await scope.provider
            .sendMessage('Ask me')
            .timeout(const Duration(seconds: 5));
        expect(scope.provider.pendingUserInput, isNull);
        expect(requests, hasLength(2));
        expect(toolResult()['content'], contains('Tool failed:'));
        expect(scope.provider.busy, isFalse);
      },
    );
  });
}
