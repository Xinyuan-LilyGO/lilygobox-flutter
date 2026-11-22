import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/assistant_tools.dart';
import 'package:lilygobox/features/assistant/data/command_policy_store.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/process_timeline.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';

import 'assistant_test_scope.dart';

void main() {
  late AssistantTestScope scope;
  late Directory root;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late Completer<void> awaiting;
  late List<Map<String, dynamic>> requests;
  var toolName = 'write_file';
  var twoCalls = false;
  int? reviewServiceStatus;
  String? reviewFinishReason;
  int? reviewOutputTokens;
  http.Response? reviewResponse;
  late Future<String> Function() reviewReply;
  late Map<String, Object?> arguments;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lilygobox-approval-');
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    awaiting = Completer<void>();
    requests = [];
    twoCalls = false;
    reviewServiceStatus = null;
    reviewFinishReason = null;
    reviewOutputTokens = null;
    reviewResponse = null;
    toolName = 'write_file';
    reviewReply = () async => 'MANUAL';
    arguments = {
      'path': '${root.path}/a.txt',
      'content': 'approved',
      'expected_content': null,
    };
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      tools: AssistantTools(
        commandPolicy: AiCommandPolicyStore(
          file: File('${root.path}/command-rules.json'),
        ),
      ),
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (reviewResponse case final response?
            when request.url.host == 'reviewer.test') {
          return response;
        }
        final messages = requests.last['messages'] as List;
        final review = (messages.first['content'] as String).startsWith(
          'Review one proposed tool operation.',
        );
        if (review && reviewServiceStatus != null) {
          return http.Response(
            '{"error":{"message":"Private service details: review-key"}}',
            reviewServiceStatus!,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final useTool =
            requests.length == 1 || (twoCalls && requests.length == 2);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                if (review && reviewFinishReason != null)
                  'finish_reason': reviewFinishReason,
                'message': review
                    ? {'content': await reviewReply()}
                    : useTool
                    ? {
                        'content': '',
                        'tool_calls': [
                          {
                            'id': 'call-${requests.length}',
                            'type': 'function',
                            'function': {
                              'name': toolName,
                              'arguments': jsonEncode(arguments),
                            },
                          },
                        ],
                      }
                    : {'content': 'Done'},
              },
            ],
            if (review && reviewOutputTokens != null)
              'usage': {'completion_tokens': reviewOutputTokens},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
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
    scope.provider.addListener(() {
      if (!awaiting.isCompleted && scope.provider.pendingApproval != null) {
        awaiting.complete();
      }
    });
  });
  tearDown(() async {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    await root.delete(recursive: true);
  });
  AiMessage pending() => scope.provider.pendingApproval!;

  void useAutomaticApproval() => scope.provider.setPermissions(
    AiPermissions(mode: AiApprovalMode.automatic),
  );

  Map<String, dynamic> reviewEvidence() =>
      jsonDecode((requests[1]['messages'] as List).last['content'] as String)
          as Map<String, dynamic>;

  String toolResult() =>
      (requests.last['messages'] as List).singleWhere(
            (message) => message['role'] == 'tool',
          )['content']
          as String;

  Map<String, dynamic> toolFailure() =>
      jsonDecode(toolResult()) as Map<String, dynamic>;

  AiProcessEntry recordedOperation() {
    final message = scope.provider.messages.last;
    final restored = ConversationCodec.read(ConversationCodec.message(message));
    return buildAiProcessTimeline(restored.processEvents)
        .where((entry) => entry.event.operationId != null)
        .single;
  }

  Future<String> prepareRead() async {
    final file = await File('${root.path}/a.txt').writeAsString('fixture text');
    final path = await file.resolveSymbolicLinks();
    toolName = 'read_file';
    arguments = {'path': path};
    useAutomaticApproval();
    return path;
  }

  for (final decision in ['APPROVE', 'DENY']) {
    test('automatic approval applies an explicit $decision result', () async {
      final path = await prepareRead();
      final model = decision == 'APPROVE' ? 'gpt-5.4' : 'review-model';
      final effort = decision == 'APPROVE' ? AiReasoningEffort.none : null;
      final serviceId = await scope.provider.saveService(
        name: 'Reviewer',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://reviewer.test/v1',
        models: [model],
        apiKey: 'review-key',
      );
      scope.provider.selectApprovalModel((
        serviceId: serviceId,
        model: model,
        reasoningEffort: effort,
      ));
      reviewReply = () async => decision;
      await scope.provider
          .sendMessage('Read `$path`')
          .timeout(const Duration(seconds: 5));
      expect(awaiting.isCompleted, isFalse);
      expect(requests.map((request) => request['model']), [
        'test-model',
        model,
        'test-model',
      ]);
      expect(requests[1]['tools'], anyOf(isNull, isEmpty));
      expect(requests[1]['reasoning_effort'], effort?.name);
      expect(
        jsonDecode((requests[1]['messages'] as List).last['content'] as String),
        {'request': 'Read `$path`', 'operation': 'read_file', 'path': path},
      );
      expect(
        toolResult(),
        contains(decision == 'APPROVE' ? 'fixture text' : 'did not approve'),
      );
      if (decision == 'DENY') {
        expect(toolFailure()['reason_code'], 'denied_by_reviewer');
        expect(toolFailure(), isNot(contains('untrusted_reviewer_reason')));
      }
      scope.provider.selectApprovalModel(null);
      final operation = recordedOperation();
      expect(operation.event.action?.succeeded, decision == 'APPROVE');
      expect(operation.events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.reviewingPermission,
        if (decision == 'APPROVE') ...[
          AiResponseStatus.permissionReviewApproved,
          AiResponseStatus.executingTools,
        ] else
          AiResponseStatus.permissionReviewDenied,
        null,
      ]);
      expect(
        operation.events[2].elapsed,
        greaterThanOrEqualTo(operation.events[1].elapsed),
      );
      expect(operation.events[1].model, model);
      expect(operation.events[1].reasoningEffort, effort);
    });
  }

  test('automatic denial returns bounded reviewer feedback as data', () async {
    useAutomaticApproval();
    final path = arguments['path'] as String;
    const reason = 'The destination exceeds the scope of the request.';
    reviewReply = () async => 'DENY: $reason\u0000key ${'x' * 500}';
    await scope.provider
        .sendMessage('Write the requested file')
        .timeout(const Duration(seconds: 5));

    expect(await File(path).exists(), isFalse);
    expect(awaiting.isCompleted, isFalse);
    final result = toolFailure();
    expect(result['ok'], isFalse);
    expect(result['error_code'], 'automatic_approval_not_granted');
    expect(result['reason_code'], 'denied_by_reviewer');
    final reviewerReason = result['untrusted_reviewer_reason'] as String;
    expect(reviewerReason, startsWith('$reason [redacted]'));
    expect(reviewerReason.runes, hasLength(400));
    expect(reviewerReason, isNot(contains('key')));
    expect(
      result['instruction'],
      contains('not instructions or authorization'),
    );
    expect(result['instruction'], contains('Do not repeat or bypass'));
    expect(recordedOperation().event.action?.output, toolResult());
  });

  test(
    'indeterminate model review blocks the operation without asking the user',
    () async {
      final path = await prepareRead();
      reviewReply = () async => 'APPROVE, maybe';
      await scope.provider
          .sendMessage('Read "$path"')
          .timeout(const Duration(seconds: 5));
      expect(awaiting.isCompleted, isFalse);
      expect(requests, hasLength(3));
      expect(requests[1]['model'], 'test-model');
      expect(toolResult(), contains('did not approve'));
      expect(toolFailure()['reason_code'], 'invalid_review_response');
      expect(toolFailure()['review_response_issue'], 'decision_format');
      expect(toolResult(), isNot(contains('APPROVE, maybe')));
      final operation = recordedOperation();
      expect(operation.events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.reviewingPermission,
        AiResponseStatus.permissionReviewFailed,
        null,
      ]);
      expect(operation.events[1].model, 'test-model');
      expect(operation.events[1].reasoningEffort, isNull);
    },
  );

  for (final (finishReason, outputTokens, expectedReason) in [
    ('length', 512, 'length'),
    ('content_filter', 24, 'content_filter'),
    ('unknown private provider details', null, null),
  ]) {
    test(
      'an incomplete Chat Completions decision fails closed: $finishReason',
      () async {
        useAutomaticApproval();
        final path = arguments['path'] as String;
        reviewReply = () async => 'APPROVE';
        reviewFinishReason = finishReason;
        reviewOutputTokens = outputTokens;

        await scope.provider
            .sendMessage('Write "$path"')
            .timeout(const Duration(seconds: 5));

        expect(await File(path).exists(), isFalse);
        expect(awaiting.isCompleted, isFalse);
        expect(
          toolFailure(),
          containsPair('reason_code', 'incomplete_review_response'),
        );
        expect(toolFailure()['finish_reason'], expectedReason);
        expect(toolFailure()['output_tokens'], outputTokens);
        expect(toolFailure()['output_limit'], requests[1]['max_tokens']);
        expect(
          toolResult(),
          isNot(contains('unknown private provider details')),
        );
        expect(recordedOperation().event.action?.output, toolResult());
      },
    );
  }

  test('an empty decision is distinct from a malformed decision', () async {
    final path = await prepareRead();
    reviewReply = () async => '';
    reviewFinishReason = 'stop';
    await scope.provider
        .sendMessage('Read "$path"')
        .timeout(const Duration(seconds: 5));

    expect(toolFailure()['reason_code'], 'invalid_review_response');
    expect(toolFailure()['review_response_issue'], 'empty_decision');
  });

  for (final streaming in [true, false]) {
    test('an incomplete Responses decision fails closed (streaming: $streaming)', () async {
      useAutomaticApproval();
      final path = arguments['path'] as String;
      final serviceId = await scope.provider.saveService(
        name: 'Reviewer',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://reviewer.test/v1',
        models: ['review-model'],
        apiKey: 'review-key',
      );
      scope.provider.selectApprovalModel((
        serviceId: serviceId,
        model: 'review-model',
        reasoningEffort: null,
      ));
      final incomplete = {
        'status': 'incomplete',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'APPROVE'},
            ],
          },
        ],
        if (streaming) 'incomplete_details': {'reason': 'max_output_tokens'},
        if (streaming) 'usage': {'output_tokens': 512},
      };
      reviewResponse = streaming
          ? http.Response(
              'data: ${jsonEncode({'type': 'response.incomplete', 'response': incomplete})}\n\n',
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            )
          : http.Response(
              jsonEncode(incomplete),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );

      await scope.provider
          .sendMessage('Write "$path"')
          .timeout(const Duration(seconds: 5));

      expect(await File(path).exists(), isFalse);
      expect(toolFailure()['reason_code'], 'incomplete_review_response');
      expect(
        toolFailure()['finish_reason'],
        streaming ? 'max_output_tokens' : null,
      );
      expect(toolFailure()['output_tokens'], streaming ? 512 : null);
      expect(toolFailure()['output_limit'], requests[1]['max_output_tokens']);
    });
  }

  test('automatic mode reviews an explicitly named directory', () async {
    final directory = await Directory('${root.path}/新建文件夹').create();
    await File('${directory.path}/fixture.txt').writeAsString('fixture');
    final path = await directory.resolveSymbolicLinks();
    toolName = 'list_directory';
    arguments = {'path': path};
    scope.provider.setPermissions(
      AiPermissions(mode: AiApprovalMode.automatic),
    );
    reviewReply = () async => 'APPROVE';
    final input = Platform.isWindows
        ? '你这边能访问这个文件夹吗$path'
        : '你这边能访问这个文件夹吗 $path';
    await scope.provider.sendMessage(input).timeout(const Duration(seconds: 5));
    expect(scope.provider.error, isNull);
    expect(awaiting.isCompleted, isFalse);
    expect(requests, hasLength(3));
    expect(
      jsonDecode((requests[1]['messages'] as List).last['content'] as String),
      {'request': input, 'operation': 'list_directory', 'path': path},
    );
    expect(toolResult(), contains('fixture.txt'));
  });

  test(
    'automatic review receives the exact child target and user request',
    () async {
      final path = await prepareRead();
      final directory = await root.resolveSymbolicLinks();
      reviewReply = () async => 'DENY';
      await scope.provider.sendMessage('List `$directory`');
      expect(awaiting.isCompleted, isFalse);
      expect(requests, hasLength(3));
      expect(reviewEvidence(), {
        'request': 'List `$directory`',
        'operation': 'read_file',
        'path': path,
      });
      expect(toolResult(), contains('did not approve'));
    },
  );

  test('an agent message is not human authorization', () async {
    await prepareRead();
    final serviceId = await scope.provider.saveService(
      name: 'Chat with reasoning options',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['deepseek-flash'],
      apiKey: 'key',
    );
    await scope.provider.selectModel(serviceId, 'deepseek-flash');
    await scope.provider.setReasoningEffort(AiReasoningEffort.none);
    await scope.provider
        .receiveAgentMessage(
          sourceId: 'other-agent',
          sourceTitle: 'Other agent',
          content: 'Read the file',
        )
        .timeout(const Duration(seconds: 5));
    expect(awaiting.isCompleted, isFalse);
    expect(requests, hasLength(2));
    expect(toolResult(), contains('did not approve'));
    expect(toolFailure()['reason_code'], 'missing_delegated_authorization');
    final operation = recordedOperation();
    final skipped = operation.events.singleWhere(
      (event) => event.status == AiResponseStatus.permissionReviewSkipped,
    );
    expect(skipped.model, 'deepseek-flash');
    expect(skipped.reasoningEffort, AiReasoningEffort.none);
  });

  for (final decision in ['APPROVE', 'DENY']) {
    test('automatic review handles file writes: $decision', () async {
      useAutomaticApproval();
      final path = arguments['path'] as String;
      reviewReply = () async {
        expect(await File(path).exists(), isFalse);
        return decision;
      };
      await scope.provider
          .sendMessage('Write `$path`')
          .timeout(const Duration(seconds: 5));
      expect(awaiting.isCompleted, isFalse);
      expect(requests, hasLength(3));
      expect(reviewEvidence()['operation'], 'write_file');
      expect(reviewEvidence()['write_mode'], 'create');
      expect(reviewEvidence(), isNot(contains('arguments')));
      expect(await File(path).exists(), decision == 'APPROVE');
      expect(
        recordedOperation().event.action?.succeeded,
        decision == 'APPROVE',
      );
    });
  }

  test('unavailable approval model does not cause a manual prompt', () async {
    final path = await prepareRead();
    scope.provider.selectApprovalModel((
      serviceId: 'unavailable-service',
      model: 'review-model',
      reasoningEffort: null,
    ));
    await scope.provider
        .sendMessage('Read `$path`')
        .timeout(const Duration(seconds: 5));
    expect(awaiting.isCompleted, isFalse);
    expect(requests, hasLength(2));
    expect(toolResult(), contains('did not approve'));
    expect(toolFailure()['reason_code'], 'review_model_unavailable');
    expect(recordedOperation().events.map((event) => event.status), [
      AiResponseStatus.preparingTools,
      AiResponseStatus.permissionReviewFailed,
      null,
    ]);
    expect(recordedOperation().events[1].model, 'review-model');
  });

  test('automatic review service errors omit the response body', () async {
    final path = await prepareRead();
    reviewServiceStatus = 401;
    await scope.provider
        .sendMessage('Read `$path`')
        .timeout(const Duration(seconds: 5));

    final result = toolFailure();
    expect(result['reason_code'], 'review_service_error');
    expect(result['http_status'], 401);
    expect(toolResult(), isNot(contains('Private service details')));
    expect(toolResult(), isNot(contains('review-key')));
    expect(recordedOperation().event.action?.succeeded, isFalse);
  });

  test(
    'switching to request approval discards an in-flight decision',
    () async {
      final path = await prepareRead();
      final reviewStarted = Completer<void>();
      final reply = Completer<String>();
      reviewReply = () {
        reviewStarted.complete();
        return reply.future;
      };
      final send = scope.provider.sendMessage('Read `$path`');
      await reviewStarted.future.timeout(const Duration(seconds: 5));
      expect(
        recordedOperation().event.status,
        AiResponseStatus.reviewingPermission,
      );
      scope.provider.setPermissions(AiPermissions());
      reply.complete('APPROVE');
      await send.timeout(const Duration(seconds: 5));
      expect(awaiting.isCompleted, isFalse);
      expect(toolResult(), contains('did not approve'));
      expect(toolFailure()['reason_code'], 'review_cancelled');
      expect(recordedOperation().events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.reviewingPermission,
        AiResponseStatus.permissionReviewCancelled,
        null,
      ]);
    },
  );

  test('no file changes happen until an exact one-time approval', () async {
    final send = scope.provider.sendMessage('Write a file');
    await awaiting.future.timeout(const Duration(seconds: 5));
    expect(await File(arguments['path'] as String).exists(), isFalse);
    final id = pending().id;
    await scope.provider.resolveTool(id, approve: true);
    await scope.provider.resolveTool(id, approve: true);
    await send;
    expect(await File(arguments['path'] as String).readAsString(), 'approved');
    expect(requests, hasLength(2));
    expect(scope.provider.pendingApproval, isNull);
    expect(
      scope.provider.messages.where((message) => message.toolName != null),
      isEmpty,
    );
  });

  test('denial returns tool failure and leaves the file untouched', () async {
    final send = scope.provider.sendMessage('Write');
    await awaiting.future;
    await scope.provider.resolveTool(pending().id, approve: false);
    await send;
    expect(await File(arguments['path'] as String).exists(), isFalse);
    final history = requests.last['messages'] as List;
    expect(
      history.where((item) => item['role'] == 'tool').single['content'],
      contains('denied'),
    );
  });

  test(
    'stopping cancels outstanding approval without executing or hanging',
    () async {
      final send = scope.provider.sendMessage('Write');
      await awaiting.future;
      final id = pending().id;
      scope.provider.stopGeneration();
      await send.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(id, approve: true);
      expect(scope.provider.busy, isFalse);
      expect(await File(arguments['path'] as String).exists(), isFalse);
      expect(requests, hasLength(1));
      expect(recordedOperation().events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.awaitingApproval,
        AiResponseStatus.manualApprovalCancelled,
        null,
      ]);
    },
  );

  test(
    'custom write scope runs directly and clear resets permissions',
    () async {
      scope.provider.setPermissions(
        AiPermissions(
          mode: AiApprovalMode.custom,
          files: AiFileAccess.readWrite,
          folders: [root.path],
        ),
      );
      await scope.provider.sendMessage('Write');
      expect(
        await File(arguments['path'] as String).readAsString(),
        'approved',
      );
      expect(
        scope.provider.messages.where((message) => message.toolName != null),
        isEmpty,
      );
      expect(recordedOperation().events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.customApprovalGranted,
        AiResponseStatus.executingTools,
        null,
      ]);
      scope.provider.clearConversation();
      expect(scope.provider.permissions.mode, AiApprovalMode.onRequest);
      expect(scope.provider.permissions.folders, isEmpty);
    },
  );

  test(
    'custom scope always requests approval for operations outside it',
    () async {
      scope.provider.setPermissions(AiPermissions(mode: AiApprovalMode.custom));
      final send = scope.provider.sendMessage('Write');
      await awaiting.future.timeout(const Duration(seconds: 5));
      expect(await File(arguments['path'] as String).exists(), isFalse);
      await scope.provider.resolveTool(pending().id, approve: false);
      await send;
      expect(await File(arguments['path'] as String).exists(), isFalse);
      expect(scope.provider.pendingApproval, isNull);
      expect(recordedOperation().events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.customApprovalNotGranted,
        AiResponseStatus.awaitingApproval,
        AiResponseStatus.manualApprovalDenied,
        null,
      ]);
    },
  );

  test('ordinary setting tools still run without confirmation', () async {
    scope.provider.setPermissions(AiPermissions(mode: AiApprovalMode.custom));
    toolName = 'set_theme';
    arguments = {'theme': 'light'};
    await scope.provider.sendMessage('Light theme');
    expect(
      scope.provider.messages.where((message) => message.toolName != null),
      isEmpty,
    );
    expect(requests, hasLength(2));
    expect(recordedOperation().events.map((event) => event.status), [
      AiResponseStatus.preparingTools,
      AiResponseStatus.executingTools,
      null,
    ]);
  });

  test(
    'automatic mode sends previously ungated settings tools for review',
    () async {
      useAutomaticApproval();
      toolName = 'set_theme';
      arguments = {'theme': 'light'};
      reviewReply = () async => 'DENY';
      await scope.provider.sendMessage('Light theme');
      expect(awaiting.isCompleted, isFalse);
      expect(requests, hasLength(3));
      expect(reviewEvidence(), {
        'request': 'Light theme',
        'operation': 'set_theme',
        'arguments': arguments,
      });
      expect(recordedOperation().events.map((event) => event.status), [
        AiResponseStatus.preparingTools,
        AiResponseStatus.reviewingPermission,
        AiResponseStatus.permissionReviewDenied,
        null,
      ]);
    },
  );

  test(
    'one-time approval does not grant later calls the same permission',
    () async {
      toolName = 'read_file';
      arguments = {'path': '${root.path}/a.txt'};
      twoCalls = true;
      await File(arguments['path'] as String).writeAsString('data');
      final send = scope.provider.sendMessage('Read twice');
      await awaiting.future;
      final first = pending().id;
      await scope.provider.resolveTool(first, approve: true);
      final second = Completer<void>();
      void listener() {
        if (!second.isCompleted &&
            (scope.provider.pendingApproval != null &&
                scope.provider.pendingApproval!.id != first)) {
          second.complete();
        }
      }

      scope.provider.addListener(listener);
      listener();
      await second.future.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(pending().id, approve: false);
      await send;
      scope.provider.removeListener(listener);
      expect(
        scope.provider.messages.where((message) => message.toolName != null),
        isEmpty,
      );
      expect(scope.provider.pendingApproval, isNull);
      expect(requests, hasLength(3));
    },
  );

  Map<String, Object?> localCommand() {
    final marker = '${root.path}/executed.txt';
    return {
      'executable': Platform.isWindows ? 'powershell.exe' : '/bin/sh',
      'arguments': Platform.isWindows
          ? [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              "[IO.File]::WriteAllText('${marker.replaceAll("'", "''")}', 'executed')",
            ]
          : ['-c', r'printf executed > "$1"', 'fixture', marker],
      'working_directory': root.path,
      'reason': 'Verify category approvals',
      'yield_ms': 5000,
    };
  }

  for (final decision in ['APPROVE', 'DENY']) {
    test(
      'automatic review decides whether a command starts: $decision',
      () async {
        final marker = File('${root.path}/executed.txt');
        useAutomaticApproval();
        toolName = 'run_command';
        arguments = localCommand();
        reviewReply = () async {
          expect(await marker.exists(), isFalse);
          return decision;
        };
        await scope.provider.sendMessage('Run the local fixture command');
        expect(awaiting.isCompleted, isFalse);
        expect(requests, hasLength(3));
        expect(reviewEvidence()['operation'], 'run_command');
        expect(reviewEvidence()['path'], await root.resolveSymbolicLinks());
        expect(
          reviewEvidence()['arguments']['arguments'],
          arguments['arguments'],
        );
        expect(reviewEvidence()['command_risks'], contains('opaqueScript'));
        expect(await marker.exists(), decision == 'APPROVE');
      },
    );
  }

  test(
    'automatic mode blocks disk operations without calling the reviewer',
    () async {
      useAutomaticApproval();
      toolName = 'run_command';
      arguments = {
        ...localCommand(),
        'executable': '${root.path}/diskpart',
        'arguments': <String>[],
      };
      reviewReply = () async => 'APPROVE';
      await scope.provider.sendMessage('Run the disk fixture');
      expect(awaiting.isCompleted, isFalse);
      expect(requests, hasLength(2));
      expect(
        jsonDecode(toolResult())['error_code'],
        'command_automaticDiskWrite',
      );
    },
  );

  test('a forbidden command is not sent to the automatic reviewer', () async {
    useAutomaticApproval();
    toolName = 'run_command';
    arguments = localCommand();
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.sendMessage('Run the local fixture command');
    expect(awaiting.isCompleted, isFalse);
    expect(requests, hasLength(2));
    expect(jsonDecode(toolResult())['error_code'], 'command_forbidden');
    expect(await File('${root.path}/executed.txt').exists(), isFalse);
  });

  for (final rejected in [AiPermissionCategory.execution]) {
    test(
      'rejecting ${rejected.name} prevents the command from starting',
      () async {
        toolName = 'run_command';
        arguments = localCommand();
        final seen = <String>[];
        final handled = <String>{};
        void listener() {
          final request = scope.provider.pendingApproval;
          if (request == null || !handled.add(request.id)) return;
          final category =
              request.toolArguments!['permission_category'] as String;
          seen.add(category);
          expect(File('${root.path}/executed.txt').existsSync(), isFalse);
          scheduleMicrotask(
            () => scope.provider.resolveTool(
              request.id,
              approve: category != rejected.name,
            ),
          );
        }

        scope.provider.addListener(listener);
        await scope.provider.sendMessage('Run command');
        scope.provider.removeListener(listener);
        expect(seen, [AiPermissionCategory.execution.name]);
        expect(await File('${root.path}/executed.txt').exists(), isFalse);
        expect(scope.provider.pendingApproval, isNull);
        expect(
          scope.provider.messages.last.processingSteps.single.succeeded,
          isFalse,
        );
      },
    );
  }

  test('a command requests one execution approval before launch', () async {
    toolName = 'run_command';
    arguments = localCommand();
    final seen = <String>[];
    final handled = <String>{};
    void listener() {
      final request = scope.provider.pendingApproval;
      if (request == null || !handled.add(request.id)) return;
      seen.add(request.toolArguments!['permission_category'] as String);
      expect(File('${root.path}/executed.txt').existsSync(), isFalse);
      scheduleMicrotask(
        () => scope.provider.resolveTool(request.id, approve: true),
      );
    }

    scope.provider.addListener(listener);
    await scope.provider.sendMessage('Run command');
    scope.provider.removeListener(listener);
    expect(seen, [AiPermissionCategory.execution.name]);
    expect(await File('${root.path}/executed.txt').readAsString(), 'executed');
    expect(scope.provider.permissions.execution, isFalse);
    expect(scope.provider.permissions.fullFiles, isFalse);
  });

  test('file and network grants do not authorize command execution', () async {
    toolName = 'run_command';
    arguments = localCommand();
    arguments['arguments'] = Platform.isWindows
        ? ['-NoProfile', '-Command', 'Write-Output harmless']
        : ['-c', 'echo harmless'];
    scope.provider.setPermissions(
      AiPermissions(
        mode: AiApprovalMode.custom,
        execution: false,
        fullFiles: true,
        network: true,
      ),
    );
    final sending = scope.provider.sendMessage('Run command');
    await awaiting.future.timeout(const Duration(seconds: 5));
    expect(pending().toolArguments!['permission_category'], 'execution');
    await scope.provider.resolveTool(pending().id, approve: false);
    await sending;
    expect(await File('${root.path}/executed.txt').exists(), isFalse);
  });
  AiPermissions fullyAuthorized() => AiPermissions(
    mode: AiApprovalMode.custom,
    execution: true,
    fullFiles: true,
    network: true,
  );
  test('opaque commands still require a visible one-time safety approval under full access', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(fullyAuthorized());
    final sending = scope.provider.sendMessage('Run command');
    await awaiting.future.timeout(const Duration(seconds: 5));
    expect(pending().toolArguments!['command_safety_approval'], isTrue);
    expect(pending().toolArguments!['command_risks'], contains('opaqueScript'));
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    await scope.provider.resolveTool(pending().id, approve: false);
    await sending;
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(scope.provider.permissions.execution, isTrue);
  });
  for (final promptRule in [false, true]) {
    test(
      'command bypass runs opaque scripts without approval (prompt:$promptRule)',
      () async {
        toolName = 'run_command';
        arguments = localCommand();
        scope.provider.setPermissions(
          fullyAuthorized().copyWith(commandNoApproval: true),
        );
        if (promptRule) {
          await File('${root.path}/command-rules.json').writeAsString(
            jsonEncode({
              'version': 1,
              'rules': [
                {
                  'prefix': [arguments['executable']],
                  'decision': 'prompt',
                },
              ],
            }),
          );
        }
        var approvalRequests = 0;
        void rejectUnexpectedApproval() {
          if (scope.provider.pendingApproval case final request?) {
            approvalRequests++;
            scheduleMicrotask(
              () => scope.provider.resolveTool(request.id, approve: false),
            );
          }
        }

        scope.provider.addListener(rejectUnexpectedApproval);
        await scope.provider.sendMessage('Run command');
        scope.provider.removeListener(rejectUnexpectedApproval);
        expect(approvalRequests, 0);
        expect(
          await File('${root.path}/executed.txt').readAsString(),
          'executed',
        );
        expect(scope.provider.pendingApproval, isNull);
      },
    );
  }

  test('command bypass still rejects explicitly forbidden commands', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(
      fullyAuthorized().copyWith(commandNoApproval: true),
    );
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.sendMessage('Run command');
    expect(awaiting.isCompleted, isFalse);
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(
      jsonDecode(
        scope.provider.messages.last.processingSteps.single.output,
      )['error_code'],
      'command_forbidden',
    );
  });

  test(
    'one-time safety approval executes without changing capability switches',
    () async {
      toolName = 'run_command';
      arguments = localCommand();
      scope.provider.setPermissions(fullyAuthorized());
      final sending = scope.provider.sendMessage('Run command');
      await awaiting.future.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(pending().id, approve: true);
      await sending;
      expect(
        await File('${root.path}/executed.txt').readAsString(),
        'executed',
      );
      expect(scope.provider.pendingApproval, isNull);
    },
  );
  test('forbidden commands never show an allow button and return a structured failure', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(fullyAuthorized());
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.sendMessage('Run command');
    expect(awaiting.isCompleted, isFalse);
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(scope.provider.pendingApproval, isNull);
    final step = scope.provider.messages.last.processingSteps.single;
    expect(step.succeeded, isFalse);
    expect(jsonDecode(step.output)['error_code'], 'command_forbidden');
  });
  test('policy changes while awaiting approval prevent execution', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(fullyAuthorized());
    final sending = scope.provider.sendMessage('Run command');
    await awaiting.future.timeout(const Duration(seconds: 5));
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.resolveTool(pending().id, approve: true);
    await sending;
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(
      jsonDecode(
        scope.provider.messages.last.processingSteps.single.output,
      )['error_code'],
      'command_forbidden',
    );
  });
}
