/*
 * @Description: 验证运行中引导的顺序、上下文、取消和失败保留行为。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 20:27:04
 * @LastEditTime: 2026-11-10 21:31:01
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  late Completer<void> started;
  late Completer<void> release;
  late List<Map<String, dynamic>> requests;
  late bool fail;
  late bool tool;
  late bool multipleTools;

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    started = Completer<void>();
    release = Completer<void>();
    requests = [];
    fail = false;
    tool = false;
    multipleTools = false;
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final first = requests.length == 1;
        if (first) {
          started.complete();
          await release.future;
        }
        if (fail) return http.Response('Invalid key', 401);
        if (request.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': first ? 'Initial answer.' : 'Updated answer.',
                    },
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
                'message': first && tool
                    ? {
                        'content': 'I will change the theme.',
                        'tool_calls': [
                          {
                            'id': 'theme',
                            'type': 'function',
                            'function': {
                              'name': 'set_theme',
                              'arguments': '{"theme":"dark"}',
                            },
                          },
                          if (multipleTools)
                            {
                              'id': 'second-theme',
                              'type': 'function',
                              'function': {
                                'name': 'set_theme',
                                'arguments': '{"theme":"light"}',
                              },
                            },
                        ],
                      }
                    : {
                        'content': first
                            ? 'Initial answer.'
                            : 'Updated answer.',
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
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['vision-model'],
      apiKey: 'key',
    );
  });

  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  test(
    'automatically sends queued messages as separate turns in order',
    () async {
      final send = scope.provider.sendMessage('Start');
      await started.future;
      await scope.provider.sendMessage('Use Chinese');
      await scope.provider.sendMessage('Keep it short');
      final image = AiImageAttachment(
        name: 'test.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      await scope.provider.sendMessage('', attachments: [image]);
      expect(requests, hasLength(1));
      expect(
        (requests.first['messages'] as List).where(
          (item) => item['role'] == 'user',
        ),
        hasLength(1),
      );
      expect(scope.provider.pendingGuidance, hasLength(3));
      expect(scope.provider.messages, hasLength(2));
      release.complete();
      await send;
      expect(requests, hasLength(4));
      expect((requests[1]['messages'] as List).last['content'], 'Use Chinese');
      expect(
        (requests[2]['messages'] as List).last['content'],
        'Keep it short',
      );
      final users = (requests.last['messages'] as List)
          .where((item) => item['role'] == 'user')
          .toList();
      expect(users.map((item) => item['content']).take(3), [
        'Start',
        'Use Chinese',
        'Keep it short',
      ]);
      expect(
        users.last['content'][0]['image_url']['url'],
        'data:image/png;base64,AQID',
      );
      final reply = scope.provider.messages.last;
      expect(reply.content, 'Updated answer.');
      expect(reply.status, AiResponseStatus.completed);
      expect(scope.provider.pendingGuidance, isEmpty);
      expect(scope.provider.messages, hasLength(8));
      expect(
        scope.provider.messages
            .where((item) => item.role == 'user')
            .map((item) => item.content),
        ['Start', 'Use Chinese', 'Keep it short', ''],
      );
      final replies = scope.provider.messages
          .where((item) => item.role == 'assistant')
          .toList();
      expect(replies.first.content, 'Initial answer.');
      expect(replies.map((item) => item.id).toSet(), hasLength(4));
      for (final response in replies) {
        expect(response.status, AiResponseStatus.completed);
        expect(
          response.processEvents.where(
            (event) => event.type == AiProcessEventType.guidance,
          ),
          isEmpty,
        );
      }
    },
  );

  test(
    'Responses preserves previous output and replays image guidance as input_image',
    () async {
      await scope.provider.saveService(
        id: scope.provider.selectedService!.id,
        name: 'Responses',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://example.test/v1',
        models: ['vision-model'],
        apiKey: 'key',
      );
      final send = scope.provider.sendMessage('Start');
      await started.future;
      await scope.provider.sendMessage(
        'Look here',
        attachments: [
          AiImageAttachment(
            name: 'test.png',
            bytes: Uint8List.fromList([1]),
            mimeType: 'image/png',
          ),
        ],
      );
      release.complete();
      await send;
      expect(requests, hasLength(2));
      final input = requests.last['input'] as List;
      expect(input.map((item) => item['role']), ['user', 'assistant', 'user']);
      expect(input.last['content'], [
        {'type': 'input_text', 'text': 'Look here'},
        {'type': 'input_image', 'image_url': 'data:image/png;base64,AQ=='},
      ]);
      expect(scope.provider.messages.last.content, 'Updated answer.');
      expect(scope.provider.messages.last.status, AiResponseStatus.completed);
      expect(scope.provider.pendingGuidance, isEmpty);
    },
  );

  test(
    'stop between tools skips later actions and closes their history entries',
    () async {
      tool = true;
      multipleTools = true;
      void stopAfterFirstAction() {
        if (scope.provider.busy &&
            scope.provider.messages.last.processingSteps.length == 1) {
          scope.provider.stopGeneration();
        }
      }

      scope.provider.addListener(stopAfterFirstAction);
      final send = scope.provider.sendMessage('Change theme');
      await started.future;
      release.complete();
      await send;
      scope.provider.removeListener(stopAfterFirstAction);
      expect(requests, hasLength(1));
      expect(theme.currentTheme, ThemeType.dark);
      expect(scope.provider.messages.last.status, AiResponseStatus.stopped);
      expect(scope.provider.messages.last.processingSteps, hasLength(1));
      await scope.provider.sendMessage('Explain');
      final history = requests.last['messages'] as List;
      final tools = history.where((item) => item['role'] == 'tool').toList();
      expect(tools, hasLength(2));
      expect(tools.last['tool_call_id'], 'second-theme');
      expect(tools.last['content'], contains('Cancelled'));
    },
  );

  test('removing pending input prevents it from reaching the model', () async {
    final send = scope.provider.sendMessage('Start');
    await started.future;
    await scope.provider.sendMessage('Discard this');
    scope.provider.removePendingGuidance(
      scope.provider.pendingGuidance.single.id,
    );
    release.complete();
    await send;
    expect(requests, hasLength(1));
    expect(
      scope.provider.messages.last.processEvents.where(
        (event) => event.type == AiProcessEventType.guidance,
      ),
      isEmpty,
    );
  });

  test(
    'continue after stopping before output reuses the turn and requests continuation',
    () async {
      final send = scope.provider.sendMessage('Start');
      await started.future;
      scope.provider.stopGeneration();
      release.complete();
      await send;
      expect(scope.provider.canContinue, isTrue);
      final requestCount = requests.length;
      final continuation = scope.provider.continueGeneration();
      await scope.provider.continueGeneration();
      await continuation;
      expect(requests, hasLength(requestCount + 1));
      expect(
        (requests.last['messages'] as List).last['content'],
        contains('Continue the previous response'),
      );
      expect(
        scope.provider.messages.where((item) => item.role == 'user'),
        hasLength(1),
      );
      expect(scope.provider.messages.last.content, 'Updated answer.');
      expect(
        scope.provider.messages.last.processEvents.any(
          (event) => event.status == AiResponseStatus.stopped,
        ),
        isTrue,
      );
      expect(scope.provider.canContinue, isFalse);
    },
  );

  test(
    'tool replies precede guidance and the original request configuration is retained',
    () async {
      tool = true;
      final send = scope.provider.sendMessage('Change theme');
      await started.future;
      await scope.provider.sendMessage('Then explain it');
      await scope.provider.saveService(
        name: 'Other',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://other.test/v1',
        models: ['other'],
        apiKey: 'other',
      );
      release.complete();
      await send;
      expect(requests, hasLength(3));
      expect((requests[1]['messages'] as List).last['role'], 'tool');
      final history = requests.last['messages'] as List;
      expect(history.map((item) => item['role']), [
        'system',
        'user',
        'assistant',
        'tool',
        'assistant',
        'user',
      ]);
      expect(history.last['content'], 'Then explain it');
      expect(requests.last['model'], 'vision-model');
      expect(theme.currentTheme, ThemeType.dark);
      expect(scope.provider.messages.last.status, AiResponseStatus.completed);
    },
  );

  test(
    'taking a queued message returns text and images without sending it',
    () async {
      final send = scope.provider.sendMessage('Start');
      await started.future;
      final image = AiImageAttachment(
        name: 'test.png',
        bytes: Uint8List(1),
        mimeType: 'image/png',
      );
      await scope.provider.sendMessage('Original', attachments: [image]);
      await scope.provider.sendMessage('Second');
      final queued = scope.provider.pendingGuidance.first;
      final taken = scope.provider.takePendingGuidance(queued.id)!;
      expect(taken.id, queued.id);
      expect(taken.content, 'Original');
      expect(taken.attachments.single, same(image));
      expect(scope.provider.pendingGuidance.single.content, 'Second');
      expect(scope.provider.takePendingGuidance(queued.id), isNull);
      release.complete();
      await send;
      expect(requests, hasLength(2));
      expect((requests.last['messages'] as List).last['content'], 'Second');
      expect(scope.provider.canSendMessage, isTrue);
    },
  );

  test(
    'stop during a pending steer retains the queue and prevents restart',
    () async {
      final send = scope.provider.sendMessage('Start');
      await started.future;
      await scope.provider.sendMessage('Keep this');
      await scope.provider.guidePendingMessage(
        scope.provider.pendingGuidance.single.id,
      );
      scope.provider.stopGeneration();
      release.complete();
      await send;
      expect(requests, hasLength(1));
      expect(scope.provider.pendingGuidance.single.content, 'Keep this');
      expect(scope.provider.error, isNull);
      expect(scope.provider.canContinue, isTrue);
    },
  );

  for (final protocol in AiApiProtocol.values) {
    test(
      'immediate steer cancels streaming and selects only that item: ${protocol.name}',
      () async {
        final cancelled = Completer<void>();
        final stream = StreamController<List<int>>(
          onCancel: () => cancelled.complete(),
        );
        final secondStarted = Completer<void>();
        final secondRelease = Completer<void>();
        final payloads = <Map<String, dynamic>>[];
        final running = await createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: split,
          client: MockClient.streaming((request, body) async {
            payloads.add(
              jsonDecode(utf8.decode(await body.toBytes()))
                  as Map<String, dynamic>,
            );
            if (payloads.length == 1)
              return http.StreamedResponse(stream.stream, 200);
            if (payloads.length == 2) {
              expect(cancelled.isCompleted, isTrue);
              secondStarted.complete();
              await secondRelease.future;
            }
            final result = protocol == AiApiProtocol.openAiResponses
                ? {
                    'output': [
                      {
                        'type': 'message',
                        'role': 'assistant',
                        'content': [
                          {'type': 'output_text', 'text': 'Done'},
                        ],
                      },
                    ],
                  }
                : {
                    'choices': [
                      {
                        'message': {'content': 'Done'},
                      },
                    ],
                  };
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(result))),
              200,
            );
          }),
        );
        addTearDown(running.dispose);
        addTearDown(stream.close);
        await running.provider.initialized;
        await running.provider.saveService(
          name: 'Test',
          protocol: protocol,
          baseUrl: 'https://test.example/v1',
          models: ['test'],
          apiKey: 'key',
        );
        final send = running.provider.sendMessage('Start');
        while (payloads.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        stream.add(
          utf8.encode(
            protocol == AiApiProtocol.openAiResponses
                ? 'event: response.output_text.delta\ndata: {"type":"response.output_text.delta","delta":"Partial"}\n\n'
                : 'data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n',
          ),
        );
        for (
          var i = 0;
          i < 100 && running.provider.messages.last.content.isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(running.provider.messages.last.content, 'Partial');
        await running.provider.sendMessage('Wait for later');
        await running.provider.sendMessage('Guide now');
        final chosen = running.provider.pendingGuidance.last;
        await running.provider.guidePendingMessage(chosen.id);
        await secondStarted.future;
        expect(
          running.provider.pendingGuidance.single.content,
          'Wait for later',
        );
        expect(payloads, hasLength(2));
        final history =
            (payloads[1][protocol == AiApiProtocol.openAiResponses
                    ? 'input'
                    : 'messages']
                as List);
        expect(jsonEncode(history.last), contains('Guide now'));
        expect(jsonEncode(history), isNot(contains('Wait for later')));
        expect(running.provider.error, isNull);
        secondRelease.complete();
        await send;
        expect(payloads, hasLength(3));
        expect(running.provider.pendingGuidance, isEmpty);
        expect(
          running.provider.messages[1].processEvents
              .where((event) => event.type == AiProcessEventType.guidance)
              .map((event) => event.guidance!.content),
          ['Guide now'],
        );
        expect(
          running.provider.messages[1].processEvents.any(
            (event) => event.text == 'Partial',
          ),
          isTrue,
        );
        expect(
          running.provider.messages.last.status,
          AiResponseStatus.completed,
        );
      },
    );
  }

  test(
    'immediate guidance between tools closes skipped calls before restarting',
    () async {
      tool = true;
      multipleTools = true;
      String? queuedId;
      var guided = false;
      void guideAfterFirstAction() {
        if (!guided &&
            queuedId != null &&
            scope.provider.busy &&
            scope.provider.messages.last.processingSteps.length == 1) {
          guided = true;
          unawaited(scope.provider.guidePendingMessage(queuedId!));
        }
      }

      scope.provider.addListener(guideAfterFirstAction);
      final send = scope.provider.sendMessage('Change theme');
      await started.future;
      await scope.provider.sendMessage('Keep the dark theme');
      queuedId = scope.provider.pendingGuidance.single.id;
      release.complete();
      await send;
      scope.provider.removeListener(guideAfterFirstAction);
      expect(requests, hasLength(2));
      expect(theme.currentTheme, ThemeType.dark);
      final history = requests.last['messages'] as List;
      expect(history.map((item) => item['role']), [
        'system',
        'user',
        'assistant',
        'tool',
        'tool',
        'user',
      ]);
      expect(history[4]['content'], contains('Cancelled'));
      expect(history.last['content'], 'Keep the dark theme');
      expect(scope.provider.messages.last.processingSteps, hasLength(1));
      expect(scope.provider.error, isNull);
      expect(scope.provider.canContinue, isFalse);
    },
  );

  test('failed requests retain pending input for explicit resend', () async {
    fail = true;
    final send = scope.provider.sendMessage('Start');
    await started.future;
    await scope.provider.sendMessage('Still needed');
    release.complete();
    await send;
    expect(requests, hasLength(1));
    expect(scope.provider.pendingGuidance.single.content, 'Still needed');
    expect(scope.provider.messages.last.status, AiResponseStatus.failed);
    fail = false;
    await scope.provider.sendMessage('');
    expect(scope.provider.pendingGuidance, isEmpty);
    expect((requests.last['messages'] as List).last['content'], 'Still needed');
    expect(scope.provider.messages[2].content, 'Still needed');
    expect(
      scope.provider.messages.last.processEvents.where(
        (event) => event.type == AiProcessEventType.guidance,
      ),
      isEmpty,
    );
  });

  test(
    'stopping preserves unconsumed guidance without an automatic follow-up',
    () async {
      final send = scope.provider.sendMessage('Start');
      await started.future;
      await scope.provider.sendMessage('Keep this');
      scope.provider.stopGeneration();
      release.complete();
      await send;
      expect(scope.provider.busy, isFalse);
      expect(scope.provider.pendingGuidance.single.content, 'Keep this');
      expect(requests, hasLength(1));
      scope.provider.clearConversation();
      expect(scope.provider.pendingGuidance, isEmpty);
    },
  );

  test(
    'image guidance checks the running model instead of the next selected model',
    () async {
      final serviceId = scope.provider.selectedService!.id;
      await scope.provider.saveService(
        id: serviceId,
        name: 'Text only',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['vision-model'],
        apiKey: 'key',
        imageInputs: {'vision-model': AiImageInput.unsupported},
      );
      final send = scope.provider.sendMessage('Start');
      await started.future;
      await scope.provider.saveService(
        name: 'Vision',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://other.test/v1',
        models: ['other'],
        apiKey: 'other',
      );
      await scope.provider.sendMessage(
        'Look',
        attachments: [
          AiImageAttachment(
            name: 'test.png',
            bytes: Uint8List(1),
            mimeType: 'image/png',
          ),
        ],
      );
      expect(scope.provider.pendingGuidance, isEmpty);
      expect(scope.provider.error, isA<AiConfigurationException>());
      release.complete();
      await send;
      expect(requests, hasLength(1));
    },
  );
}
