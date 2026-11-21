import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/chat_completion_client.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

import 'assistant_test_scope.dart';

List<int> _sse(Object event) => utf8.encode('data: ${jsonEncode(event)}\n\n');

Map<String, Object?> _chatDelta(Map<String, Object?> delta) => {
  'choices': [
    {'delta': delta},
  ],
};

void main() {
  for (final protocol in AiApiProtocol.values) {
    test('$protocol uses arrival times of output chunks only', () async {
      final started = Completer<void>();
      final stream = StreamController<List<int>>(onListen: started.complete);
      final client = ChatCompletionClient(
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      addTearDown(client.close);
      final future = client.complete(
        configuration: AiServiceConfiguration(
          protocol: protocol,
          baseUrl: 'https://example.test/v1',
          model: 'test',
        ),
        apiKey: 'key',
        tools: const [],
        messages: const [],
      );
      await started.future;
      final responses = protocol == AiApiProtocol.openAiResponses;
      final wall = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      stream.add(
        _sse(
          responses
              ? {'type': 'response.reasoning_text.delta', 'delta': 'R'}
              : _chatDelta({'reasoning_content': 'R'}),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      stream.add(
        _sse(
          responses
              ? {'type': 'response.output_text.delta', 'delta': 'A'}
              : _chatDelta({'content': 'A'}),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 45));
      stream.add(
        _sse(
          responses
              ? {
                  'type': 'response.completed',
                  'response': {
                    'output': [],
                    'usage': {'output_tokens': 15},
                  },
                }
              : {
                  'choices': [],
                  'usage': {'completion_tokens': 15},
                },
        ),
      );
      await stream.close();
      final result = await future;
      expect(result.usage?.outputTokens, 15);
      expect(result.streamedOutputChunks, 2);
      expect(
        result.streamedOutputDuration.inMilliseconds,
        greaterThanOrEqualTo(10),
      );
      expect(
        wall.elapsed - result.streamedOutputDuration,
        greaterThanOrEqualTo(const Duration(milliseconds: 70)),
      );
    });
  }

  test(
    'publishes once per completed turn and isolates model and service',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      var requestCount = 0;
      final lastStarted = Completer<void>();
      final endReply = Completer<void>();
      final sampledTime = Stopwatch();
      Stream<List<int>> respond(int index) async* {
        if (index == 1) {
          yield _sse(
            _chatDelta({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'one',
                  'function': {'name': 'search_chat_history', 'arguments': '{'},
                },
              ],
            }),
          );
          await Future<void>.delayed(const Duration(milliseconds: 15));
          yield _sse(
            _chatDelta({
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '"query":"fixture"}'},
                },
              ],
            }),
          );
        } else if (index == 2) {
          lastStarted.complete();
          await endReply.future;
          sampledTime.start();
          yield _sse(_chatDelta({'content': 'A'}));
          await Future<void>.delayed(const Duration(milliseconds: 550));
          yield _sse(_chatDelta({'content': 'B'}));
          await Future<void>.delayed(const Duration(milliseconds: 550));
          sampledTime.stop();
          yield _sse(_chatDelta({'content': 'C'}));
        } else if (index == 4) {
          for (final part in ['Short', ' buffered', ' burst']) {
            yield _sse(_chatDelta({'content': part}));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } else if (index == 5) {
          yield _sse(_chatDelta({'content': 'First chunk'}));
          await Future<void>.delayed(const Duration(milliseconds: 1050));
          yield _sse(_chatDelta({'content': 'Second chunk'}));
        } else {
          yield [
            ..._sse(_chatDelta({'content': 'Batch'})),
            ..._sse(_chatDelta({'content': 'ed'})),
          ];
        }
        yield _sse({
          'choices': [],
          'usage': {'completion_tokens': index == 1 ? 200 : 5},
        });
      }

      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(respond(++requestCount), 200);
        }),
      );
      addTearDown(() {
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
      });
      final provider = scope.provider;
      await provider.initialized;
      for (final name in ['First', 'Second']) {
        await provider.saveService(
          name: name,
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test/v1',
          models: ['test', 'other'],
          apiKey: 'key',
        );
      }
      final first = provider.services.first.id;
      final second = provider.services.last.id;
      await provider.selectModel(first, 'test');
      final observed = <double?>[null];
      provider.addListener(() {
        final value = provider.latestReplySpeed;
        if (value != observed.last) {
          expect(provider.busy, isFalse);
          observed.add(value);
        }
      });
      final pending = provider.sendMessage('Test');
      await lastStarted.future;
      expect(provider.latestReplySpeed, isNull);
      endReply.complete();
      await pending;
      final rate = provider.latestReplySpeed;
      final expectedRate = 5 * Duration.microsecondsPerSecond / sampledTime.elapsedMicroseconds;
      expect(rate, closeTo(expectedRate, expectedRate * .35));
      expect(observed, [null, rate]);
      await provider.selectModel(first, 'other');
      expect(provider.latestReplySpeed, isNull);
      await provider.selectModel(second, 'test');
      expect(provider.latestReplySpeed, isNull);
      await provider.selectModel(first, 'test');
      expect(provider.latestReplySpeed, rate);
      await provider.sendMessage('One buffered chunk');
      expect(provider.latestReplySpeed, isNull);
      await provider.sendMessage('Short buffered burst');
      expect(provider.latestReplySpeed, isNull);
      await provider.sendMessage('Only two chunks');
      expect(provider.latestReplySpeed, isNull);
    },
  );
}
