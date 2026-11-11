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
  late AssistantTestScope scope;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late List<Map<String, dynamic>> requests;
  late List<String> preambles;
  late Completer<void> firstStarted;
  late Completer<void> releaseFirst;
  late Completer<void> followupStarted;
  late Completer<void> releaseFollowup;
  var protocol = AiApiProtocol.openAiChatCompletions;
  var failFollowup = false;
  var toolRounds = 1;
  var streamFirst = false;
  var continuation = false;
  late String finalText;

  Future<void> initialize() async {
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        final number = requests.length;
        if (number == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        if (number == 2) {
          followupStarted.complete();
          await releaseFollowup.future;
        }
        if (number == 2 && failFollowup)
          return http.Response('Invalid key', 401);
        final useTool = number <= toolRounds;
        final text = useTool
            ? preambles[number - 1]
            : continuation
            ? ' continued'
            : finalText;
        final name = number == 1 ? 'get_current_time' : 'set_language';
        final arguments = number == 1 ? '{}' : '{"language":"en"}';
        if (protocol == AiApiProtocol.openAiResponses) {
          return http.Response(
            jsonEncode({
              'output': [
                if (text.isNotEmpty)
                  {
                    'type': 'message',
                    'role': 'assistant',
                    'content': [
                      {'type': 'output_text', 'text': text},
                    ],
                  },
                if (useTool)
                  {
                    'type': 'function_call',
                    'call_id': 'call-$number',
                    'name': name,
                    'arguments': arguments,
                  },
              ],
            }),
            200,
          );
        }
        if (number == 1 && streamFirst) {
          final deltas = [
            {'reasoning_content': 'Check the clock.'},
            {'content': text.substring(0, text.length ~/ 2)},
            {'content': text.substring(text.length ~/ 2)},
            {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call-$number',
                  'function': {'name': name, 'arguments': arguments},
                },
              ],
            },
          ];
          return http.Response(
            '${deltas.map((delta) => 'data: ${jsonEncode({
              'choices': [
                {'delta': delta},
              ],
            })}\n\n').join()}data: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': text,
                  if (number == 1) 'reasoning_content': 'Check the clock.',
                  if (useTool)
                    'tool_calls': [
                      {
                        'id': 'call-$number',
                        'type': 'function',
                        'function': {'name': name, 'arguments': arguments},
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
    await scope.provider.initialized;
    await scope.provider.saveService(
      name: 'Test',
      protocol: protocol,
      baseUrl: 'https://example.test/v1',
      models: ['test-model'],
      apiKey: 'key',
    );
  }

  setUp(() {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    preambles = ['Let me check the time.', 'I will check the language too.'];
    firstStarted = Completer<void>();
    releaseFirst = Completer<void>();
    followupStarted = Completer<void>();
    releaseFollowup = Completer<void>();
    protocol = AiApiProtocol.openAiChatCompletions;
    failFollowup = false;
    toolRounds = 1;
    streamFirst = false;
    continuation = false;
    finalText = 'The current time is 2026.11.11 16:35:20.';
  });
  tearDown(() {
    if (!releaseFirst.isCompleted) releaseFirst.complete();
    if (!releaseFollowup.isCompleted) releaseFollowup.complete();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });
  List<AiMessage> replies() => scope.provider.messages
      .where((message) => message.role == 'assistant')
      .toList();

  for (final api in AiApiProtocol.values) {
    test(
      'preserves preamble and starts separate tool segment for $api',
      () async {
        protocol = api;
        await initialize();
        final send = scope.provider.sendMessage('Check the time');
        await firstStarted.future;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        releaseFirst.complete();
        await followupStarted.future;
        final segments = replies();
        expect(segments, hasLength(2));
        final frozen = segments.first;
        expect(frozen.content, preambles.first);
        expect(frozen.status, AiResponseStatus.completed);
        expect(frozen.processingSteps, isEmpty);
        expect(segments.last.content, isEmpty);
        expect(segments.last.processingSteps.single.name, 'get_current_time');
        expect(
          segments.last.processEvents.first.status,
          AiResponseStatus.preparingTools,
        );
        releaseFollowup.complete();
        await send;
        expect(replies().map((reply) => reply.content), [
          preambles.first,
          finalText,
        ]);
        expect(replies().first.elapsed, frozen.elapsed);
        expect(replies().first.processEvents, frozen.processEvents);
        expect(replies().last.status, AiResponseStatus.completed);
        expect(
          replies().last.processEvents.where(
            (event) => event.type == AiProcessEventType.reasoning,
          ),
          isEmpty,
        );
        expect(
          replies().last.processEvents.first.elapsed,
          lessThan(frozen.elapsed!),
        );
        expect(scope.provider.busy, isFalse);
        final history =
            requests.last[api == AiApiProtocol.openAiChatCompletions
                    ? 'messages'
                    : 'input']
                as List;
        expect(jsonEncode(history), contains(preambles.first));
      },
    );
  }

  test('streamed preamble is kept as body rather than reasoning', () async {
    streamFirst = true;
    await initialize();
    releaseFirst.complete();
    final send = scope.provider.sendMessage('Time');
    await followupStarted.future;
    releaseFollowup.complete();
    await send;
    expect(replies().map((reply) => reply.content), [
      preambles.first,
      finalText,
    ]);
    expect(
      replies().first.processEvents
          .where((event) => event.type == AiProcessEventType.reasoning)
          .single
          .text,
      'Check the clock.',
    );
    expect(replies().last.processingSteps.single.name, 'get_current_time');
  });

  test('consecutive tool calls without body share one segment', () async {
    toolRounds = 2;
    preambles = ['', ''];
    await initialize();
    releaseFirst.complete();
    releaseFollowup.complete();
    await scope.provider.sendMessage('Time and language');
    expect(replies(), hasLength(1));
    expect(replies().single.content, finalText);
    expect(replies().single.processingSteps.map((step) => step.name), [
      'get_current_time',
      'set_language',
    ]);
  });

  test(
    'each preamble creates a new segment only when another tool follows',
    () async {
      toolRounds = 2;
      await initialize();
      releaseFirst.complete();
      releaseFollowup.complete();
      await scope.provider.sendMessage('Time and language');
      expect(replies().map((reply) => reply.content), [
        ...preambles,
        finalText,
      ]);
      expect(replies().map((reply) => reply.processingSteps.length), [0, 1, 1]);
    },
  );

  test('tool followup failure leaves completed preamble unchanged', () async {
    failFollowup = true;
    await initialize();
    releaseFirst.complete();
    final send = scope.provider.sendMessage('Time');
    await followupStarted.future;
    final frozen = replies().first;
    releaseFollowup.complete();
    await send;
    expect(replies().first.content, preambles.first);
    expect(replies().first.status, AiResponseStatus.completed);
    expect(replies().first.elapsed, frozen.elapsed);
    expect(replies().last.status, AiResponseStatus.failed);
    expect(replies().last.requestError, isNotNull);
  });

  test('stop and continue update only the latest segment', () async {
    await initialize();
    releaseFirst.complete();
    final send = scope.provider.sendMessage('Time');
    await followupStarted.future;
    final frozen = replies().first;
    scope.provider.stopGeneration();
    releaseFollowup.complete();
    await send;
    expect(replies().last.status, AiResponseStatus.stopped);
    expect(scope.provider.canContinue, isTrue);
    continuation = true;
    await scope.provider.continueGeneration();
    expect(replies(), hasLength(2));
    expect(replies().first.content, frozen.content);
    expect(replies().first.elapsed, frozen.elapsed);
    expect(replies().last.content, 'continued');
    expect(replies().last.status, AiResponseStatus.completed);
  });
}
