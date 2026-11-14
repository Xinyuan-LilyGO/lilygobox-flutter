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

Future<void> waitUntil(bool Function() condition) async {
  final timeout = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(timeout))
      fail('Expected asynchronous state was not reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Map<String, Object?> answer(AiApiProtocol protocol, String text) =>
    protocol == AiApiProtocol.openAiResponses
    ? {
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
      }
    : {
        'choices': [
          {
            'message': {'content': text},
          },
        ],
      };

String textDelta(AiApiProtocol protocol, String text) =>
    protocol == AiApiProtocol.openAiResponses
    ? 'event: response.output_text.delta\ndata: ${jsonEncode({'type': 'response.output_text.delta', 'delta': text})}\n\n'
    : 'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n';

Map<String, Object?> toolAnswer(
  AiApiProtocol protocol,
  String name,
  Map<String, Object?> arguments,
) => protocol == AiApiProtocol.openAiResponses
    ? {
        'output': [
          {
            'type': 'reasoning',
            'id': 'reasoning-snapshot',
            'summary': [],
            'encrypted_content': 'opaque-reasoning',
          },
          {
            'type': 'function_call',
            'id': 'function-snapshot',
            'call_id': 'call-snapshot',
            'name': name,
            'arguments': jsonEncode(arguments),
          },
        ],
      }
    : {
        'choices': [
          {
            'message': {
              'content': '',
              'tool_calls': [
                {
                  'id': 'call-snapshot',
                  'type': 'function',
                  'function': {
                    'name': name,
                    'arguments': jsonEncode(arguments),
                  },
                },
              ],
            },
          },
        ],
      };

List<dynamic> contextOf(Map<String, dynamic> request, AiApiProtocol protocol) =>
    request[protocol == AiApiProtocol.openAiResponses ? 'input' : 'messages']
        as List;

void main() {
  for (final protocol in AiApiProtocol.values) {
    group(protocol.name, () {
      late AssistantTestScope scope;
      late ThemeProvider theme;
      late LanguageProvider language;
      late AppShellProvider shell;
      late SplitViewProvider split;
      late List<Map<String, dynamic>> requests;

      setUp(() {
        theme = ThemeProvider();
        language = LanguageProvider();
        shell = AppShellProvider();
        split = SplitViewProvider();
        requests = [];
      });

      Future<void> initialize(http.Client client) async {
        scope = await createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: split,
          client: client,
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
          name: 'Fork test',
          protocol: protocol,
          baseUrl: 'https://example.test/v1',
          models: ['test'],
          apiKey: 'key',
          imageInputs: {'test': AiImageInput.supported},
        );
      }

      test(
        'busy streaming fork keeps snapshot partial and excludes later source changes',
        () async {
          final stream = StreamController<List<int>>();
          addTearDown(stream.close);
          await initialize(
            MockClient.streaming((request, body) async {
              requests.add(
                jsonDecode(utf8.decode(await body.toBytes()))
                    as Map<String, dynamic>,
              );
              if (requests.length == 1)
                return http.StreamedResponse(stream.stream, 200);
              return http.StreamedResponse(
                Stream.value(utf8.encode(jsonEncode(answer(protocol, 'Done')))),
                200,
              );
            }),
          );
          final source = scope.provider;
          final running = source.sendMessage('Original prompt');
          await waitUntil(() => requests.isNotEmpty);
          stream.add(utf8.encode(textDelta(protocol, 'Snapshot partial')));
          await waitUntil(
            () => source.messages.last.content == 'Snapshot partial',
          );
          expect(source.busy, isTrue);
          final snapshot = source.snapshotConversationFork();
          stream.add(
            utf8.encode(textDelta(protocol, ' plus later source output')),
          );
          if (protocol == AiApiProtocol.openAiResponses) {
            stream.add(
              utf8.encode(
                'event: response.completed\ndata: ${jsonEncode({'type': 'response.completed', 'response': answer(protocol, 'Snapshot partial plus later source output')})}\n\n',
              ),
            );
          } else {
            stream.add(utf8.encode('data: [DONE]\n\n'));
          }
          await stream.close();
          await running;
          await source.sendMessage('Later source-only prompt');
          final fork = source.forkForWorkspace();
          addTearDown(fork.dispose);
          final beforeRestore = requests.length;
          fork.restoreConversationFork(snapshot);
          expect(fork.busy, isFalse);
          expect(fork.pendingApproval, isNull);
          expect(fork.pendingUserInput, isNull);
          expect(fork.messages.last.content, 'Snapshot partial');
          expect(fork.messages.last.status, AiResponseStatus.stopped);
          expect(requests, hasLength(beforeRestore));
          await fork.sendMessage('Continue branch');
          final history = contextOf(requests.last, protocol);
          final assistants = history
              .where((m) => m['role'] == 'assistant')
              .toList();
          expect(assistants, hasLength(1));
          expect(assistants.single['content'], 'Snapshot partial');
          expect(
            jsonEncode(history),
            isNot(contains('plus later source output')),
          );
          expect(
            jsonEncode(history),
            isNot(contains('Later source-only prompt')),
          );
          expect(source.messages.last.content, 'Done');
          expect(
            source.messages.where((m) => m.content == 'Continue branch'),
            isEmpty,
          );
        },
      );

      test(
        'image bytes and model history are independent at both copy boundaries',
        () async {
          await initialize(
            MockClient((request) async {
              requests.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(
                jsonEncode(answer(protocol, 'Image described')),
                200,
              );
            }),
          );
          final bytes = Uint8List.fromList([1, 2, 3, 4]);
          await scope.provider.sendMessage(
            'Describe image',
            attachments: [
              AiImageAttachment(
                name: 'sample.png',
                bytes: bytes,
                mimeType: 'image/png',
              ),
            ],
          );
          final snapshot = scope.provider.snapshotConversationFork();
          bytes[0] = 99;
          final first = scope.provider.forkForWorkspace();
          final second = scope.provider.forkForWorkspace();
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          first.restoreConversationFork(snapshot);
          first.messages.first.attachments.single.bytes[1] = 88;
          second.restoreConversationFork(snapshot);
          expect(second.messages.first.attachments.single.bytes, [1, 2, 3, 4]);
          expect(scope.provider.messages.first.attachments.single.bytes, [
            99,
            2,
            3,
            4,
          ]);
          expect(requests, hasLength(1));
          await second.sendMessage('Continue with image');
          final history = jsonEncode(contextOf(requests.last, protocol));
          expect(history, contains('data:image/png;base64,AQIDBA=='));
          expect(history, contains('Describe image'));
          expect(history, contains('Image described'));
        },
      );

      test(
        'completed tool details and Responses replay items survive without re-execution',
        () async {
          await initialize(
            MockClient((request) async {
              requests.add(jsonDecode(request.body) as Map<String, dynamic>);
              final result = requests.length == 1
                  ? toolAnswer(protocol, 'get_current_time', {})
                  : answer(protocol, 'Clock checked');
              return http.Response(jsonEncode(result), 200);
            }),
          );
          await scope.provider.sendMessage('Check time');
          final original = scope.provider.messages
              .expand((m) => m.processingSteps)
              .single;
          final snapshot = scope.provider.snapshotConversationFork();
          final fork = scope.provider.forkForWorkspace();
          addTearDown(fork.dispose);
          fork.restoreConversationFork(snapshot);
          expect(requests, hasLength(2));
          final copied = fork.messages.expand((m) => m.processingSteps).single;
          expect(copied.name, original.name);
          expect(copied.output, original.output);
          expect(copied.succeeded, isTrue);
          expect(
            fork.messages
                .expand((m) => m.processEvents)
                .where((e) => e.action != null),
            isNotEmpty,
          );
          await fork.sendMessage('Use earlier result');
          final history = contextOf(requests.last, protocol);
          if (protocol == AiApiProtocol.openAiResponses) {
            expect(
              history
                  .where((m) => m['type'] == 'reasoning')
                  .single['encrypted_content'],
              'opaque-reasoning',
            );
            expect(
              history
                  .where((m) => m['type'] == 'function_call')
                  .single['call_id'],
              'call-snapshot',
            );
            expect(
              history
                  .where((m) => m['type'] == 'function_call_output')
                  .single['output'],
              original.output,
            );
          } else {
            expect(
              history.where((m) => m['role'] == 'tool').single['content'],
              original.output,
            );
          }
          expect(requests, hasLength(3));
        },
      );

      test(
        'pending approval becomes cancelled history without a live approval in the fork',
        () async {
          await initialize(
            MockClient((request) async {
              requests.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(
                jsonEncode(
                  requests.length == 1
                      ? toolAnswer(protocol, 'list_directory', {
                          'path': 'D:/not-executed',
                        })
                      : answer(protocol, 'No operation'),
                ),
                200,
              );
            }),
          );
          final source = scope.provider;
          final running = source.sendMessage('List directory');
          await waitUntil(() => source.pendingApproval != null);
          final snapshot = source.snapshotConversationFork();
          final fork = source.forkForWorkspace();
          addTearDown(fork.dispose);
          fork.restoreConversationFork(snapshot);
          expect(fork.pendingApproval, isNull);
          expect(fork.busy, isFalse);
          expect(requests, hasLength(1));
          await fork.sendMessage('Continue safely');
          final history = contextOf(requests.last, protocol);
          final cancelled = protocol == AiApiProtocol.openAiResponses
              ? history
                    .where((m) => m['type'] == 'function_call_output')
                    .single['output']
              : history.where((m) => m['role'] == 'tool').single['content'];
          expect(jsonDecode(cancelled as String)['cancelled'], isTrue);
          expect(source.pendingApproval, isNotNull);
          await source.resolveTool(source.pendingApproval!.id, approve: false);
          await running;
        },
      );
    });
  }
}
