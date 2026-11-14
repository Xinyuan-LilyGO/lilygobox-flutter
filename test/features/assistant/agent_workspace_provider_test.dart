import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/agent_link.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/domain/task_canvas_style.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late AssistantTestScope scope;
  late AiWorkspaceProvider workspaces;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late List<Map<String, dynamic>> requests;
  Completer<void>? gate;
  Completer<void>? namingGate;
  var spawnFromMain = false;
  Map<String, Object?> spawnSelection = {};
  var askApproval = false;
  var failNaming = false;
  var parentResponseCount = 0;
  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    gate = null;
    namingGate = null;
    spawnFromMain = false;
    spawnSelection = {};
    askApproval = false;
    failNaming = false;
    parentResponseCount = 0;
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        body['_testAuthorization'] = request.headers['authorization'];
        body['_testUrl'] = request.url.toString();
        requests.add(body);
        final messages = body['messages'] as List;
        if (messages.first['content'].toString().startsWith(
          'Generate a concise task title',
        )) {
          await namingGate?.future;
          if (failNaming) {
            return http.Response(
              jsonEncode({
                'error': {'message': 'Naming unavailable'},
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Generated task name'},
                },
              ],
            }),
            200,
          );
        }
        var user = messages.where((e) => e['role'] == 'user').last['content'];
        if (user is String && user.startsWith('{')) {
          final envelope = jsonDecode(user);
          if (envelope is Map && envelope['type'] == 'connected_task_message') {
            user = envelope['content'];
          }
        }
        final isParent = user == 'Delegate this';
        if (!isParent) await gate?.future;
        final needsTool =
            isParent && spawnFromMain && parentResponseCount++ == 0;
        final needsApproval =
            askApproval && messages.every((m) => m['role'] != 'tool');
        final response = needsTool || needsApproval
            ? {
                'content': '',
                'tool_calls': [
                  {
                    'id': 'call-1',
                    'type': 'function',
                    'function': {
                      'name': needsTool ? 'spawn_agent' : 'list_directory',
                      'arguments': jsonEncode(
                        needsTool
                            ? {
                                'title': 'Review',
                                'task': 'Check child',
                                ...spawnSelection,
                              }
                            : {'path': 'D:/github/lilygobox-flutter'},
                      ),
                    },
                  },
                ],
              }
            : {'content': 'Done: $user'};
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': response},
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
      models: ['gpt-6.1-sol', 'deepseek-flash'],
      apiKey: 'key',
    );
    workspaces = AiWorkspaceProvider(scope.provider);
  });
  tearDown(() {
    if (gate?.isCompleted == false) gate!.complete();
    if (namingGate?.isCompleted == false) namingGate!.complete();
    workspaces.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });
  Future<void> finish(String id) async {
    await workspaces.executeTool('wait_agents', {
      'agent_ids': [id],
      'wait_ms': 100,
    });
  }

  group('Task links and navigation', () {
    test('task URLs round trip exact IDs and reject malformed app links', () {
      for (final id in ['1794640403602043-0', '123-456']) {
        final link = agentLink(id);
        expect(link, startsWith('lilygobox://agent/'));
        expect(isAgentLink(link), isTrue);
        expect(agentIdFromLink(link), id);
      }
      for (final link in [
        null,
        '',
        'https://example.com',
        'lilygobox://agent',
        'lilygobox://agent/a/b',
        'lilygobox://task/123-0',
        'lilygobox://agent/agent-123-0',
        'lilygobox://other/task',
        'lilygobox://agent/id?query=1',
        'lilygobox://agent/id#fragment',
        'lilygobox://user@agent/id',
        'lilygobox://agent:80/id',
        'lilygobox://agent/%ZZ',
      ]) {
        expect(agentIdFromLink(link), isNull, reason: '$link');
      }
      expect(isAgentLink('LILYGOBOX:malformed'), isTrue);
      expect(isAgentLink('https://example.com'), isFalse);
    });

    test(
      'open tool emits exact target and source once per request without executing target',
      () async {
        final root = await workspaces.createPrimary(
          title: 'Root',
          task: 'Plan',
        );
        await finish(root.id);
        final child = await workspaces.create(
          title: 'Same name',
          task: 'Review',
          parentId: root.id,
          startImmediately: false,
        );
        final sibling = await workspaces.create(
          title: 'Same name',
          task: 'Other review',
          parentId: root.id,
          startImmediately: false,
        );
        final schema =
            root.assistant.workspaceToolDefinitions.singleWhere(
                  (item) => (item['function'] as Map)['name'] == 'open_agent',
                )['function']
                as Map;
        expect((schema['parameters'] as Map)['required'], ['agent_id']);
        final requestCount = requests.length;
        workspaces.activeConversationId = root.id;
        final result = await root.assistant.workspaceToolHandler!(
          'open_agent',
          {'agent_id': child.id},
        );
        expect(result['navigation_requested'], isTrue);
        expect(result['url'], agentLink(child.id));
        expect(
          agentIdFromLink(child.toToolResult()['url'] as String),
          child.id,
        );
        expect(workspaces.navigationRequest!.sourceId, root.id);
        expect(workspaces.navigationRequest!.targetId, child.id);
        final revision = workspaces.navigationRequest!.revision;
        await root.assistant.workspaceToolHandler!('open_agent', {
          'agent_id': sibling.id,
        });
        expect(workspaces.navigationRequest!.revision, greaterThan(revision));
        expect(workspaces.navigationRequest!.targetId, sibling.id);
        expect(child.assistant.messages, isEmpty);
        expect(sibling.assistant.messages, isEmpty);
        expect(requests.length, requestCount);
      },
    );

    test(
      'background open returns link without stealing focus and rejects unavailable targets',
      () async {
        final root = await workspaces.createPrimary(
          title: 'Root',
          task: 'Plan',
        );
        await finish(root.id);
        final child = await workspaces.create(
          title: 'Child',
          task: 'Review',
          parentId: root.id,
          startImmediately: false,
        );
        final unrelated = await workspaces.createPrimary(
          title: 'Other root',
          task: 'Other plan',
        );
        await finish(unrelated.id);
        workspaces.activeConversationId = unrelated.id;
        final result = await root.assistant.workspaceToolHandler!(
          'open_agent',
          {'agent_id': child.id},
        );
        expect(result['navigation_requested'], isFalse);
        expect(result['url'], agentLink(child.id));
        expect(workspaces.navigationRequest, isNull);
        for (final id in [unrelated.id, 'missing', root.title]) {
          await expectLater(
            root.assistant.workspaceToolHandler!('open_agent', {
              'agent_id': id,
            }),
            throwsStateError,
          );
        }
        workspaces.remove(child.id);
        await expectLater(
          root.assistant.workspaceToolHandler!('open_agent', {
            'agent_id': child.id,
          }),
          throwsStateError,
        );
        expect(workspaces.navigationRequest, isNull);
      },
    );
  });

  group('Automatic task names', () {
    test('creates and executes immediately while naming is pending', () async {
      namingGate = Completer<void>();
      final task = await workspaces
          .createPrimary(title: '', task: 'Inspect configuration now')
          .timeout(const Duration(seconds: 2));
      expect(workspaces.find(task.id), same(task));
      expect(task.title, 'Inspect configuration now');
      await finish(task.id);
      expect(task.assistant.messages.last.content, contains('Done:'));
      namingGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(task.title, 'Generated task name');
    });

    test('pending generated name does not overwrite a manual rename', () async {
      namingGate = Completer<void>();
      final task = await workspaces.createPrimary(
        title: '',
        task: 'Inspect configuration',
      );
      workspaces.rename(task.id, 'My edited name');
      namingGate!.complete();
      await finish(task.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(task.title, 'My edited name');
    });

    test('deleting a task discards a pending generated name', () async {
      namingGate = Completer<void>();
      final task = await workspaces.createPrimary(
        title: '',
        task: 'Inspect configuration',
      );
      workspaces.remove(task.id);
      namingGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(workspaces.find(task.id), isNull);
      expect(task.title, 'Inspect configuration');
    });

    test(
      'should name an unnamed task with its selected model without polluting execution history',
      () async {
        final task = await workspaces.createPrimary(
          title: '',
          task: 'Inspect the build configuration',
          model: 'deepseek-flash',
        );
        await finish(task.id);
        expect(task.title, 'Generated task name');
        expect(requests.first['model'], 'deepseek-flash');
        expect(requests.first['tools'] ?? [], isEmpty);
        expect(
          task.assistant.messages.any(
            (m) => m.content.contains('Generated task name'),
          ),
          isFalse,
        );
        expect(
          task.assistant.messages.first.content,
          'Inspect the build configuration',
        );
        expect(
          requests.last['messages'].toString(),
          isNot(contains('Generate a concise task title')),
        );
        await workspaces.flush();
        workspaces.dispose();
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        expect(workspaces.find(task.id)!.title, 'Generated task name');
      },
    );

    test(
      'should keep task creation working when naming fails and preserve explicit names',
      () async {
        failNaming = true;
        final unnamed = await workspaces.createPrimary(
          title: '  ',
          task: 'Inspect configuration now',
        );
        await finish(unnamed.id);
        expect(unnamed.title, 'Inspect configuration now');
        final count = requests.length;
        final named = await workspaces.createPrimary(
          title: 'My name',
          task: 'Execute this',
        );
        await finish(named.id);
        expect(named.title, 'My name');
        expect(requests.length, count + 1);
      },
    );
  });

  group('Task duplication', () {
    test(
      'should fork conversation and configuration into an idle independent sibling without descendants',
      () async {
        final parent = await workspaces.createPrimary(
          title: 'Root',
          task: 'Coordinate',
        );
        await finish(parent.id);
        final source = await workspaces.create(
          title: 'Original',
          task: 'Original instructions',
          parentId: parent.id,
        );
        await finish(source.id);
        await source.assistant.setReasoningEffort(AiReasoningEffort.high);
        final descendant = await workspaces.create(
          title: 'Descendant',
          task: 'Own instructions',
          parentId: source.id,
        );
        await finish(descendant.id);
        final requestCount = requests.length;
        final copy = await workspaces.duplicate(
          source.id,
          title: 'Original copy',
        );
        expect(copy.id, isNot(source.id));
        expect(copy.title, 'Original copy');
        expect(copy.task, source.task);
        expect(copy.kind, source.kind);
        expect(copy.parentId, parent.id);
        expect(copy.assistant, isNot(same(source.assistant)));
        expect(copy.assistant.permissions, same(source.assistant.permissions));
        expect(copy.assistant.reasoningEffort, AiReasoningEffort.high);
        expect(copy.model, source.model);
        expect(copy.serviceId, source.serviceId);
        expect(copy.busy, isFalse);
        expect(
          copy.assistant.messages.map((m) => m.content),
          source.assistant.messages.map((m) => m.content),
        );
        expect(copy.assistant.messages, isNotEmpty);
        expect(
          copy.assistant.messages.first,
          isNot(same(source.assistant.messages.first)),
        );
        expect(workspaces.childrenOf(copy.id), isEmpty);
        expect(workspaces.find(descendant.id)!.parentId, source.id);
        expect(requests.length, requestCount);
        await workspaces.flush();
        workspaces.dispose();
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        final restored = workspaces.find(copy.id)!;
        expect(restored.task, 'Original instructions');
        expect(
          restored.assistant.messages.map((m) => m.content),
          contains('Original instructions'),
        );
        expect(restored.busy, isFalse);
        expect(requests.length, requestCount);
      },
    );
  });

  test(
    'fork continues with inherited context and leaves original history unchanged',
    () async {
      final source = await workspaces.createPrimary(
        title: 'Source',
        task: 'Remember the initial context',
      );
      await finish(source.id);
      final snapshot = workspaces.copyCards([source.id]);
      final oldContents = source.assistant.messages
          .map((m) => m.content)
          .toList();
      await source.assistant.sendMessage('Only the original sees this');
      final copies = await workspaces.pasteCards(
        snapshot,
        titleForCopy: (title) => title,
      );
      final copy = copies.single;
      expect(copy.assistant.messages.map((m) => m.content), oldContents);
      await copy.assistant.sendMessage('Continue the branch');
      final history = requests.last['messages'] as List;
      expect(
        history.where((m) => m['role'] == 'user').map((m) => m['content']),
        ['Remember the initial context', 'Continue the branch'],
      );
      expect(history.any((m) => m['role'] == 'assistant'), isTrue);
      expect(
        source.assistant.messages.map((m) => m.content),
        isNot(contains('Continue the branch')),
      );
      final ids = copy.assistant.messages.map((m) => m.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    },
  );

  test(
    'fork waiting on approval closes pending tool context without copying approval',
    () async {
      askApproval = true;
      final source = await workspaces.createPrimary(
        title: 'Source',
        task: 'Inspect a folder',
      );
      for (var i = 0; i < 30 && source.assistant.pendingApproval == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(source.assistant.pendingApproval, isNotNull);
      final count = requests.length;
      final copy = await workspaces.duplicate(source.id, title: 'Branch');
      expect(requests, hasLength(count));
      expect(copy.busy, isFalse);
      expect(copy.assistant.pendingApproval, isNull);
      expect(copy.assistant.pendingUserInput, isNull);
      expect(copy.assistant.messages.last.status, AiResponseStatus.stopped);
      expect(copy.assistant.messages.last.processEvents, isNotEmpty);
      askApproval = false;
      await copy.assistant.sendMessage('Continue after branching');
      final history = requests.last['messages'] as List;
      final calls = history
          .where((m) => m['tool_calls'] != null)
          .expand((m) => m['tool_calls'] as List);
      final outputs = history.where((m) => m['role'] == 'tool').toList();
      expect(calls, isNotEmpty);
      for (final call in calls) {
        expect(
          outputs.where((m) => m['tool_call_id'] == call['id']),
          hasLength(1),
        );
      }
      expect(source.assistant.pendingApproval, isNotNull);
      await source.assistant.resolveTool(
        source.assistant.pendingApproval!.id,
        approve: false,
      );
      await finish(source.id);
    },
  );

  test(
    'disconnect preserves child type through persistence and permits explicit root conversion',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Root task',
      );
      await finish(root.id);
      final child = await workspaces.create(
        title: 'Child',
        task: 'Child task',
        parentId: root.id,
      );
      await finish(child.id);
      workspaces.reparent(child.id, null, preserveKind: true);
      expect(child.kind, AiWorkspaceKind.permanent);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      final restored = workspaces.find(child.id)!;
      expect(restored.parentId, isNull);
      expect(restored.kind, AiWorkspaceKind.permanent);
      workspaces.reparent(restored.id, null);
      expect(restored.kind, AiWorkspaceKind.primary);
    },
  );

  test(
    'card clipboard snapshots survive edits and deletion and preserve selected parent links',
    () async {
      final parent = await workspaces.createPrimary(
        title: 'Clipboard root',
        task: 'Complete root instructions',
      );
      await finish(parent.id);
      final child = await workspaces.create(
        title: 'Clipboard child',
        task: 'Complete child instructions',
        parentId: parent.id,
      );
      await finish(child.id);
      final permissions = child.assistant.permissions;
      final snapshot = workspaces.copyCards([child.id, parent.id]);
      workspaces.rename(parent.id, 'Changed');
      workspaces.removeMany([parent.id, child.id]);
      final count = requests.length;
      final copies = await workspaces.pasteCards(
        snapshot,
        titleForCopy: (title) => title,
      );
      expect(copies, hasLength(2));
      expect(copies[0].title, 'Clipboard child');
      expect(copies[1].title, 'Clipboard root');
      expect(copies[0].parentId, copies[1].id);
      expect(copies[1].kind, AiWorkspaceKind.primary);
      expect(copies[0].task, 'Complete child instructions');
      expect(copies[0].assistant.permissions, same(permissions));
      expect(
        copies.every(
          (copy) => copy.assistant.messages.isNotEmpty && !copy.busy,
        ),
        isTrue,
      );
      expect(requests.length, count);
    },
  );

  group('Task names', () {
    test(
      'should persist renamed display titles without changing task identity or conversation',
      () async {
        final rootTask = await workspaces.createPrimary(
          title: 'Root',
          task: 'Coordinate',
        );
        await finish(rootTask.id);
        final child = await workspaces.create(
          title: 'Old name',
          task: 'Keep history',
          parentId: rootTask.id,
        );
        await finish(child.id);
        final assistant = child.assistant;
        final permissions = assistant.permissions;
        final requestCount = requests.length;
        workspaces.rename(child.id, '  New name  ');
        expect(child.title, 'New name');
        expect(child.assistant, same(assistant));
        expect(child.assistant.permissions, same(permissions));
        expect(child.parentId, rootTask.id);
        expect(child.result, 'Done: Keep history');
        expect(child.toToolResult()['title'], 'New name');
        for (final invalid in ['', '   ', List.filled(201, 'x').join()]) {
          expect(
            () => workspaces.rename(child.id, invalid),
            throwsFormatException,
          );
          expect(child.title, 'New name');
        }
        expect(() => workspaces.rename('missing', 'Name'), throwsStateError);
        await workspaces.flush();
        workspaces.dispose();
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        final restored = workspaces.find(child.id)!;
        expect(restored.title, 'New name');
        expect(restored.parentId, rootTask.id);
        expect(restored.result, 'Done: Keep history');
        expect(requests.length, requestCount);
      },
    );
  });

  group('Child model selection', () {
    test(
      'should list exact configured choices without exposing credentials',
      () async {
        await scope.provider.saveService(
          name: 'Another provider',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://other.test/v1',
          models: ['deepseek-flash'],
          apiKey: 'another-secret',
        );
        final result = await workspaces.executeTool('list_agent_models', {});
        final services = result['services'] as List;
        expect(services, hasLength(2));
        expect(services.map((s) => s['service_id']).toSet(), hasLength(2));
        expect(
          services.map((s) => s['service_name']),
          containsAll(['Test', 'Another provider']),
        );
        expect(
          services.every(
            (s) => (s['models'] as List).contains('deepseek-flash'),
          ),
          isTrue,
        );
        expect(jsonEncode(result), isNot(contains('another-secret')));
        expect(jsonEncode(result), isNot(contains('base_url')));
        expect(jsonEncode(result), isNot(contains('api_key')));
      },
    );

    test(
      'should use the exact external service for both child kinds on the first request',
      () async {
        final original = scope.provider.selectedService!.id;
        await scope.provider.saveService(
          name: 'External provider',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://other.test/v1',
          models: ['external-deepseek'],
          apiKey: 'external-secret',
        );
        final external = scope.provider.services.last.id;
        await scope.provider.selectModel(original, 'gpt-6.1-sol');
        final parent = await workspaces.createPrimary(
          title: 'Parent',
          task: 'Coordinate',
        );
        await finish(parent.id);
        for (final kind in ['first', 'second']) {
          final result =
              await parent.assistant.workspaceToolHandler!('spawn_agent', {
                'title': 'External $kind',
                'task': 'External $kind',
                'service_id': external,
                'model': 'external-deepseek',
              });
          final child = workspaces.find(result['agent_id'] as String)!;
          await finish(child.id);
          expect(result['service_id'], external);
          expect(result['service_name'], 'External provider');
          expect(result['model'], 'external-deepseek');
          expect(
            child.assistant.permissions,
            same(parent.assistant.permissions),
          );
          final request = requests.last;
          expect(request['model'], 'external-deepseek');
          expect(request['_testUrl'], startsWith('https://other.test/'));
          expect(request['_testAuthorization'], 'Bearer external-secret');
          expect(parent.model, 'gpt-6.1-sol');
          expect(scope.provider.selectedService!.id, original);
        }
      },
    );

    test(
      'should reject incomplete, unknown or mismatched selections without spawning or fallback',
      () async {
        final service = scope.provider.selectedService!.id;
        final count = workspaces.sessions.length;
        for (final selection in <Map<String, Object?>>[
          {'service_id': service},
          {'model': 'deepseek-flash'},
          {'service_id': 'missing', 'model': 'deepseek-flash'},
          {'service_id': service, 'model': 'missing'},
          {'service_id': service, 'model': 'DeepSeek'},
        ]) {
          await expectLater(
            workspaces.executeTool('spawn_agent', {
              'title': 'Invalid',
              'task': 'Must not run',
              ...selection,
            }),
            throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
          );
          expect(workspaces.sessions, hasLength(count));
        }
        expect(requests, isEmpty);
      },
    );

    test(
      'should execute model selection through a real parent tool-call response',
      () async {
        final service = scope.provider.selectedService!.id;
        spawnFromMain = true;
        spawnSelection = {'service_id': service, 'model': 'deepseek-flash'};
        await scope.provider.sendMessage('Delegate this');
        final child = workspaces.sessions.single;
        await finish(child.id);
        expect(child.kind, AiWorkspaceKind.permanent);
        expect(child.model, 'deepseek-flash');
        expect(
          requests.any((request) => request['model'] == 'deepseek-flash'),
          isTrue,
        );
        final tools = (requests.first['tools'] as List).map(
          (s) => s['function']['name'],
        );
        expect(tools, contains('list_agent_models'));
        final messages = requests
            .expand((r) => r['messages'] as List)
            .where((m) => m['role'] == 'tool');
        expect(
          messages.any(
            (m) => jsonDecode(m['content'])['model'] == 'deepseek-flash',
          ),
          isTrue,
        );
      },
    );
  });

  test(
    'child keeps an independent conversation and inherited model snapshot',
    () async {
      final child = await workspaces.create(
        title: 'Review',
        task: 'Child only',
      );
      await finish(child.id);
      expect(scope.provider.messages, isEmpty);
      expect(child.assistant.messages.first.content, 'Child only');
      expect(child.result, 'Done: Child only');
      expect(child.assistant.selectedModel, 'gpt-6.1-sol');
      expect(
        child.assistant.workspaceToolDefinitions.map(
          (spec) => (spec['function'] as Map)['name'],
        ),
        contains('spawn_agent'),
      );
      await scope.provider.selectModel(
        scope.provider.selectedService!.id,
        'deepseek-flash',
      );
      expect(child.assistant.selectedModel, 'gpt-6.1-sol');
      await child.assistant.selectModel(child.serviceId, 'gpt-6.1-sol');
      await child.assistant.setReasoningEffort(AiReasoningEffort.high);
      expect(scope.provider.selectedModel, 'deepseek-flash');
      await workspaces.send(child.id, 'Follow-up');
      await finish(child.id);
      expect(
        child.assistant.messages
            .where((m) => m.role == 'user')
            .map((m) => m.content),
        ['Child only', 'Follow-up'],
      );
      final tools = (requests.first['tools'] as List).map(
        (t) => t['function']['name'],
      );
      expect(tools, contains('spawn_agent'));
    },
  );
  test(
    'main model tool creates a real child and retrieves its result',
    () async {
      spawnFromMain = true;
      await scope.provider.sendMessage('Delegate this');
      final child = workspaces.sessions.single;
      await finish(child.id);
      expect(child.parentId, 'main');
      expect(child.result, 'Done: Check child');
      expect(
        scope.provider.messages.any(
          (m) => m.role == 'user' && m.content == 'Check child',
        ),
        isFalse,
      );
      final toolResult =
          (requests.lastWhere(
                        (r) => (r['messages'] as List).any(
                          (m) => m['role'] == 'tool',
                        ),
                      )['messages']
                      as List)
                  .firstWhere((m) => m['role'] == 'tool')['content']
              as String;
      expect(jsonDecode(toolResult)['agent_id'], child.id);
    },
  );
  test(
    'more than three children run independently and root stop preserves them',
    () async {
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(title: 'Task $i', task: 'Work $i');
      }
      expect(workspaces.runningCount, 3);
      await workspaces.create(title: 'Extra', task: 'Extra');
      expect(workspaces.runningCount, 4);
      scope.provider.stopGeneration();
      expect(workspaces.runningCount, 4);
      final id = workspaces.sessions.first.id;
      workspaces.stop(id);
      await finish(id);
      expect(workspaces.find(id)!.status, 'stopped');
      gate!.complete();
      gate = null;
      for (final child in workspaces.sessions) {
        await finish(child.id);
      }
    },
  );
  test(
    'more than 128 agents can be created copied saved and restored',
    () async {
      final content = List.filled(20000, 'x').join();
      for (var i = 0; i < 129; i++) {
        await workspaces.create(
          title: 'Agent $i',
          task: '$content $i',
          startImmediately: false,
        );
      }
      final source = workspaces.sessions.last;
      final copies = await workspaces.pasteCards(
        workspaces.copyCards([source.id]),
        titleForCopy: (title) => '$title (2)',
      );
      expect(copies, hasLength(1));
      expect(workspaces.sessions, hasLength(130));
      await workspaces.flush();
      expect(workspaces.persistenceError, isNull);
      expect(
        utf8
            .encode(
              scope.preferences.stringValue(AiWorkspaceProvider.storageKey, ''),
            )
            .length,
        greaterThan(2 * 1024 * 1024),
      );
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.sessions, hasLength(130));
      expect(workspaces.find(copies.single.id), isNotNull);
      expect(workspaces.sessions.every((agent) => !agent.busy), isTrue);
    },
  );

  test(
    'model spawning and agent messages can start beyond three running children',
    () async {
      final idle = await workspaces.create(title: 'Idle', task: 'First');
      await finish(idle.id);
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(title: 'Busy $i', task: 'Hold $i');
      }
      final spawned = await workspaces.executeTool('spawn_agent', {
        'title': 'Fourth',
        'task': 'Hold fourth',
      });
      expect(workspaces.find(spawned['agent_id'] as String)!.busy, isTrue);
      expect(workspaces.runningCount, 4);
      final delivered = await workspaces.executeTool('send_agent_message', {
        'agent_id': idle.id,
        'message': 'Start fifth',
      });
      expect(delivered['delivered'], isTrue);
      expect(workspaces.runningCount, 5);
      gate!.complete();
      gate = null;
      for (final agent in workspaces.sessions) {
        await finish(agent.id);
      }
    },
  );

  test(
    'transfer events follow actual messages in both directions and expire',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Root work',
      );
      await finish(root.id);
      expect(workspaces.transfers.value, isEmpty);
      final spawned = await root.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Child', 'task': 'Child work'},
      );
      final child = workspaces.find(spawned['agent_id'] as String)!;
      await finish(child.id);
      expect(workspaces.transfers.value.single.fromId, root.id);
      expect(workspaces.transfers.value.single.toId, child.id);
      await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': root.id,
        'message': 'Actual return',
      });
      await finish(root.id);
      expect(workspaces.transfers.value.last.fromId, child.id);
      expect(workspaces.transfers.value.last.toId, root.id);
      final count = workspaces.transfers.value.length;
      await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': root.id,
        'message': 'Actual return',
      });
      expect(workspaces.transfers.value, hasLength(count));
      await expectLater(
        child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': 'missing',
          'message': 'Invalid',
        }),
        throwsStateError,
      );
      expect(workspaces.transfers.value, hasLength(count));
      await Future<void>.delayed(
        AiAgentTransfer.duration + const Duration(milliseconds: 50),
      );
      expect(workspaces.transfers.value, isEmpty);
    },
  );

  test(
    'retrieving a new child result records one reverse transfer per reply',
    () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Root');
      await finish(root.id);
      final child = await workspaces.create(
        title: 'Child',
        task: 'Child',
        parentId: root.id,
      );
      await finish(child.id);
      expect(workspaces.transfers.value, isEmpty);
      await root.assistant.workspaceToolHandler!('wait_agents', {
        'agent_ids': [child.id],
        'wait_ms': 0,
      });
      expect(workspaces.transfers.value.single.fromId, child.id);
      expect(workspaces.transfers.value.single.toId, root.id);
      await root.assistant.workspaceToolHandler!('wait_agents', {
        'agent_ids': [child.id],
        'wait_ms': 0,
      });
      expect(workspaces.transfers.value, hasLength(1));
      await root.assistant.workspaceToolHandler!('list_agents', {});
      expect(workspaces.transfers.value, hasLength(1));
      await workspaces.send(child.id, 'New reply');
      await finish(child.id);
      await root.assistant.workspaceToolHandler!('wait_agents', {
        'agent_ids': [child.id],
        'wait_ms': 0,
      });
      expect(workspaces.transfers.value, hasLength(2));
      expect(workspaces.transfers.value.last.fromId, child.id);
      expect(workspaces.transfers.value.last.toId, root.id);
    },
  );

  test(
    'creation applies selected reasoning effort before the first model request',
    () async {
      final original = scope.provider.reasoningEffort;
      for (final primary in [true, false]) {
        final agent = primary
            ? await workspaces.createPrimary(
                title: 'Primary effort',
                task: 'Check effort',
                reasoningEffort: AiReasoningEffort.high,
              )
            : await workspaces.create(
                title: 'Child effort',
                task: 'Check child effort',
                reasoningEffort: AiReasoningEffort.high,
              );
        await finish(agent.id);
        expect(agent.assistant.reasoningEffort, AiReasoningEffort.high);
        expect(requests.last['reasoning_effort'], 'high');
        expect(scope.provider.reasoningEffort, original);
      }
    },
  );

  test('child approvals remain in its independent conversation', () async {
    askApproval = true;
    final child = await workspaces.create(title: 'Folder', task: 'Inspect');
    for (var i = 0; i < 20 && child.assistant.pendingApproval == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(child.needsAttention, isTrue);
    expect(scope.provider.pendingApproval, isNull);
    expect(child.status, 'waiting');
    await child.assistant.resolveTool(
      child.assistant.pendingApproval!.id,
      approve: false,
    );
    await finish(child.id);
    expect(child.assistant.pendingApproval, isNull);
  });
  test('removing a child leaves the parent HTTP client usable', () async {
    final child = await workspaces.create(title: 'Review', task: 'Check');
    await finish(child.id);
    workspaces.remove(child.id);
    expect(workspaces.sessions, isEmpty);
    await scope.provider.sendMessage('Parent still works');
    expect(scope.provider.messages.last.content, 'Done: Parent still works');
  });
  test(
    'direct child followup starts while more than three children are busy',
    () async {
      final idle = await workspaces.create(title: 'Idle', task: 'First');
      await finish(idle.id);
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(title: 'Busy $i', task: 'Working $i');
      }
      final sending = idle.assistant.sendMessage('Try fourth direct turn');
      expect(workspaces.runningCount, 4);
      expect(idle.assistant.busy, isTrue);
      expect(idle.assistant.error, isNull);
      expect(
        idle.assistant.messages.where(
          (m) => m.content == 'Try fourth direct turn',
        ),
        hasLength(1),
      );
      gate!.complete();
      gate = null;
      await sending;
      for (final child in workspaces.sessions) {
        await finish(child.id);
      }
    },
  );

  test(
    'wait observes busy state despite queued followups and closes safely',
    () async {
      gate = Completer<void>();
      final child = await workspaces.create(title: 'Busy', task: 'Initial');
      await workspaces.send(child.id, 'Queued');
      var completed = false;
      final waiting = workspaces
          .executeTool('wait_agents', {
            'agent_ids': [child.id],
            'wait_ms': 5000,
          })
          .then((value) {
            completed = true;
            return value;
          });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completed, isFalse);
      workspaces.remove(child.id);
      final result = await waiting;
      expect((result['agents'] as List).single['status'], 'closed');
      gate!.complete();
      gate = null;
    },
  );

  test(
    'list reflects current child-local model and caps returned content',
    () async {
      final child = await workspaces.create(
        title: 'Local model',
        task: 'Check',
      );
      await finish(child.id);
      await child.assistant.selectModel(child.serviceId, 'deepseek-flash');
      final snapshot = await workspaces.executeTool('list_agents', {});
      expect((snapshot['agents'] as List).single['model'], 'deepseek-flash');
      expect(scope.provider.selectedModel, 'gpt-6.1-sol');
    },
  );
  test('busy children do not disable another agent input', () async {
    final idle = await workspaces.create(title: 'Idle', task: 'Complete first');
    await finish(idle.id);
    expect(idle.assistant.canSendMessage, isTrue);
    gate = Completer<void>();
    for (var index = 0; index < 3; index++) {
      await workspaces.create(title: 'Busy $index', task: 'Working $index');
    }
    expect(idle.assistant.canSendMessage, isTrue);
    expect(idle.assistant.workspaceTurnAllowed!(), isTrue);
    expect(workspaces.sessions.last.assistant.canSendMessage, isTrue);
    final busyId = workspaces.sessions.last.id;
    workspaces.remove(busyId);
    expect(idle.assistant.canSendMessage, isTrue);
    gate!.complete();
    gate = null;
    for (final session in workspaces.sessions) {
      await finish(session.id);
    }
  });

  test(
    'stopping the main turn releases a pending workspace tool immediately',
    () async {
      spawnFromMain = true;
      final entered = Completer<void>();
      final pending = Completer<Map<String, Object?>>();
      scope.provider.workspaceToolHandler = (_, _) {
        entered.complete();
        return pending.future;
      };
      final turn = scope.provider.sendMessage('Delegate this');
      await entered.future;
      scope.provider.stopGeneration();
      await turn.timeout(const Duration(seconds: 1));
      expect(scope.provider.busy, isFalse);
      expect(scope.provider.messages.last.status, AiResponseStatus.stopped);
      pending.complete({'completed_after_parent_stop': true});
    },
  );
  test(
    'child endpoint and key stay paired when the shared service is edited',
    () async {
      final child = await workspaces.create(title: 'Snapshot', task: 'First');
      await finish(child.id);
      await scope.provider.saveService(
        id: child.serviceId,
        name: 'Changed endpoint',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://new-origin.test/v1',
        models: ['gpt-6.1-sol'],
        apiKey: 'new-origin-key',
      );
      await workspaces.send(child.id, 'Use original snapshot');
      await finish(child.id);
      expect(requests.last['_testUrl'], startsWith('https://example.test/'));
      expect(requests.last['_testAuthorization'], 'Bearer key');
      await child.assistant.selectModel(child.serviceId, 'gpt-6.1-sol');
      await workspaces.send(
        child.id,
        'Use explicitly selected updated service',
      );
      await finish(child.id);
      expect(requests.last['_testUrl'], startsWith('https://new-origin.test/'));
      expect(requests.last['_testAuthorization'], 'Bearer new-origin-key');
    },
  );
  test(
    'visible child tools permit owned stop and deletion but reject unrelated tasks',
    () async {
      final first = await workspaces.createPrimary(
        title: 'First primary',
        task: 'Plan one',
      );
      final second = await workspaces.createPrimary(
        title: 'Second primary',
        task: 'Plan two',
      );
      await finish(first.id);
      await finish(second.id);
      final spawnTool =
          first.assistant.workspaceToolDefinitions.singleWhere(
                (spec) => (spec['function'] as Map)['name'] == 'spawn_agent',
              )['function']
              as Map;
      expect(
        ((spawnTool['parameters'] as Map)['properties'] as Map).containsKey(
          'kind',
        ),
        isFalse,
      );
      final advertised = first.assistant.workspaceToolDefinitions.map(
        (spec) => (spec['function'] as Map)['name'],
      );
      expect(advertised, contains('delete_agent'));
      expect(advertised, isNot(contains('close_agent')));
      final spawned = await first.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Visible child', 'task': 'Work once'},
      );
      final child = workspaces.find(spawned['agent_id'] as String)!;
      await finish(child.id);
      expect(child.kind, AiWorkspaceKind.permanent);
      expect(child.parentId, first.id);
      final nested = await child.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Nested', 'task': 'Nested work'},
      );
      final nestedId = nested['agent_id'] as String;
      await finish(nestedId);
      for (final action in ['stop_agent', 'delete_agent']) {
        for (final target in [first.id, second.id]) {
          await expectLater(
            first.assistant.workspaceToolHandler!(action, {'agent_id': target}),
            throwsStateError,
          );
        }
        await expectLater(
          second.assistant.workspaceToolHandler!(action, {
            'agent_id': child.id,
          }),
          throwsStateError,
        );
      }
      final visible = await second.assistant.workspaceToolHandler!(
        'list_agents',
        {},
      );
      expect(visible['agents'], isEmpty);
      gate = Completer<void>();
      final running = child.assistant.sendMessage('Long child operation');
      await Future<void>.delayed(Duration.zero);
      expect(child.busy, isTrue);
      await first.assistant.workspaceToolHandler!('stop_agent', {
        'agent_id': child.id,
      });
      expect(workspaces.find(child.id), same(child));
      expect(child.assistant.stopRequested, isTrue);
      gate!.complete();
      await running;
      gate = null;
      final retained = workspaces.captureTopologyEdit();
      gate = Completer<void>();
      final nestedTask = workspaces.find(nestedId)!;
      final nestedRunning = nestedTask.assistant.sendMessage(
        'Nested running during deletion',
      );
      await Future<void>.delayed(Duration.zero);
      expect(nestedTask.busy, isTrue);
      await first.assistant.workspaceToolHandler!('delete_agent', {
        'agent_id': child.id,
      });
      expect(workspaces.find(child.id), isNull);
      expect(workspaces.find(nestedId), isNull);
      expect(nestedTask.assistant.stopRequested, isTrue);
      gate!.complete();
      await nestedRunning;
      gate = null;
      workspaces.releaseTopologyEdit(retained);
      expect(workspaces.find(first.id), same(first));
      expect(workspaces.find(second.id), same(second));
      await expectLater(
        first.assistant.workspaceToolHandler!('spawn_agent', {
          'title': 'Unsupported temporary agent',
          'task': 'Rejected',
          'kind': 'temporary',
        }),
        throwsFormatException,
      );
      await expectLater(
        first.assistant.workspaceToolHandler!('close_agent', {
          'agent_id': second.id,
        }),
        throwsStateError,
      );
    },
  );

  test(
    'v1 data is ignored and v2 rejects legacy IDs and temporary records',
    () async {
      final root = await workspaces.createPrimary(title: 'Main', task: 'Plan');
      await finish(root.id);
      expect(root.id, matches(RegExp(r'^\d+-\d+$')));
      await workspaces.flush();
      final snapshot = scope.preferences.stringValue(
        AiWorkspaceProvider.storageKey,
        '',
      );
      expect((jsonDecode(snapshot) as Map)['version'], 2);
      workspaces.dispose();
      scope.preferences.setValue('ai.taskTopology.v1', snapshot);
      scope.preferences.setValue(AiWorkspaceProvider.storageKey, '');
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.sessions, isEmpty);
      expect(scope.provider.services, isNotEmpty);
      workspaces.dispose();
      for (final corruption in ['version', 'id', 'kind']) {
        final saved = jsonDecode(snapshot) as Map;
        if (corruption == 'version') saved['version'] = 1;
        final record = (saved['sessions'] as List).single as Map;
        if (corruption == 'id') record['id'] = 'agent-123-0';
        if (corruption == 'kind') record['kind'] = 'temporary';
        scope.preferences.setValue(
          AiWorkspaceProvider.storageKey,
          jsonEncode(saved),
        );
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        expect(workspaces.sessions, isEmpty, reason: corruption);
        expect(workspaces.persistenceError, isNotNull, reason: corruption);
        workspaces.dispose();
      }
      scope.preferences.setValue(AiWorkspaceProvider.storageKey, '');
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
    },
  );

  test(
    'manual model selection applies before the first turn and primary turns do not consume child slots',
    () async {
      final child = await workspaces.create(
        title: 'Other model',
        task: 'First on DeepSeek',
        model: 'deepseek-flash',
      );
      await finish(child.id);
      expect(requests.last['model'], 'deepseek-flash');
      final chosenPrimary = await workspaces.createPrimary(
        title: 'Chosen primary',
        task: 'First primary on DeepSeek',
        model: 'deepseek-flash',
      );
      await finish(chosenPrimary.id);
      expect(requests.last['model'], 'deepseek-flash');
      expect(scope.provider.selectedModel, 'gpt-6.1-sol');
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(title: 'Busy $i', task: 'Busy $i');
      }
      final primary = await workspaces.createPrimary(
        title: 'Primary with busy children',
        task: 'Independent primary',
      );
      expect(primary.busy, isTrue);
      expect(workspaces.runningCount, 3);
      expect(primary.assistant.canSendMessage, isTrue);
      gate!.complete();
      gate = null;
      for (final item in workspaces.sessions) {
        await finish(item.id);
      }
    },
  );
  test(
    'missing saved services preserve nodes and text until an explicit local reselection',
    () async {
      final primary = await workspaces.createPrimary(
        title: 'Unavailable saved task',
        task: 'Keep my context',
      );
      await finish(primary.id);
      final originalId = primary.serviceId;
      await workspaces.flush();
      workspaces.dispose();
      await scope.provider.removeService(originalId);
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      final restored = workspaces.find(primary.id)!;
      expect(restored.status, 'unavailable');
      expect(restored.serviceId, originalId);
      expect(restored.result, 'Done: Keep my context');
      expect(restored.assistant.canSendMessage, isFalse);
      expect(restored.assistant.hasApiKey, isFalse);
      await workspaces.flush();
      final retained =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map;
      expect((retained['sessions'] as List).single['id'], primary.id);
      final replacement = await scope.provider.saveService(
        name: 'Replacement',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://replacement.test/v1',
        models: ['deepseek-flash'],
        apiKey: 'replacement-key',
      );
      await restored.assistant.selectModel(replacement, 'deepseek-flash');
      expect(restored.assistant.canSendMessage, isTrue);
      await workspaces.send(restored.id, 'Continue with explicit replacement');
      await finish(restored.id);
      expect(
        requests.last['_testUrl'],
        startsWith('https://replacement.test/'),
      );
      expect(requests.last['_testAuthorization'], 'Bearer replacement-key');
    },
  );
  test(
    'connected tasks can message in both directions with explicit source identities',
    () async {
      final primary = await workspaces.createPrimary(
        title: 'Coordinator',
        task: 'Coordinate',
      );
      await finish(primary.id);
      final child = await workspaces.create(
        title: 'Worker',
        task: 'Work',
        parentId: primary.id,
      );
      await finish(child.id);
      final sent = await primary.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': child.id, 'message': 'Check details'},
      );
      expect(sent['delivered'], isTrue);
      await finish(child.id);
      final received = child.assistant.messages
          .where((m) => m.content == 'Check details')
          .single;
      expect(received.toolName, 'agent_message');
      expect(received.toolArguments!['source_agent_id'], primary.id);
      final historyContent =
          (requests.last['messages'] as List)
                  .where((m) => m['role'] == 'user')
                  .last['content']
              as String;
      expect(jsonDecode(historyContent)['type'], 'connected_task_message');
      expect(jsonDecode(historyContent)['source_id'], primary.id);
      await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': primary.id,
        'message': 'Details checked',
      });
      await finish(primary.id);
      expect(
        primary.assistant.messages
            .where((m) => m.content == 'Details checked')
            .single
            .toolArguments!['source_agent_id'],
        child.id,
      );
      final unrelated = await workspaces.createPrimary(
        title: 'Other graph',
        task: 'Unrelated',
      );
      await finish(unrelated.id);
      await expectLater(
        child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': unrelated.id,
          'message': 'Not connected',
        }),
        throwsStateError,
      );
    },
  );

  test(
    'automatic messages suppress duplicates and exhaust a bounded collaboration chain',
    () async {
      final primary = await workspaces.createPrimary(
        title: 'Coordinator',
        task: 'Coordinate',
      );
      await finish(primary.id);
      final child = await workspaces.create(
        title: 'Worker',
        task: 'Work',
        parentId: primary.id,
      );
      await finish(child.id);
      for (
        var index = 0;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        final source = index.isEven ? primary : child;
        final target = index.isEven ? child : primary;
        await source.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': target.id,
          'message': 'Exchange $index',
        });
        await finish(target.id);
      }
      final duplicate = await primary.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': child.id, 'message': 'Exchange 0'},
      );
      expect(duplicate['delivered'], isFalse);
      expect(duplicate['duplicate'], isTrue);
      await expectLater(
        primary.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': child.id,
          'message': 'Over budget',
        }),
        throwsStateError,
      );
      final spawned =
          await primary.assistant.workspaceToolHandler!('spawn_agent', {
            'title': 'New temporary worker',
            'task': 'Do not reset the collaboration budget',
          });
      final temporary = workspaces.find(spawned['agent_id'] as String)!;
      await finish(temporary.id);
      expect(temporary.assistant.messages.first.toolName, 'agent_message');
      expect(
        temporary.assistant.messages.first.toolArguments!['source_agent_id'],
        primary.id,
      );
      await expectLater(
        primary.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': temporary.id,
          'message': 'Still over budget after spawning',
        }),
        throwsStateError,
      );
      await workspaces.send(primary.id, 'Human asks to continue');
      await finish(primary.id);
      final resumed = await primary.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': child.id, 'message': 'New authorized chain'},
      );
      expect(resumed['delivered'], isTrue);
      await finish(child.id);
    },
  );

  test('agent messages queue without dismissing target approval', () async {
    askApproval = true;
    final primary = await workspaces.createPrimary(
      title: 'Waiting coordinator',
      task: 'Inspect',
    );
    for (
      var index = 0;
      index < 30 && primary.assistant.pendingApproval == null;
      index++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final approvalId = primary.assistant.pendingApproval!.id;
    askApproval = false;
    final child = await workspaces.create(
      title: 'Worker',
      task: 'Work',
      parentId: primary.id,
    );
    await finish(child.id);
    await child.assistant.workspaceToolHandler!('send_agent_message', {
      'agent_id': primary.id,
      'message': 'Queued report',
    });
    expect(primary.assistant.pendingApproval!.id, approvalId);
    expect(
      primary
          .assistant
          .pendingGuidance
          .single
          .toolArguments!['source_agent_id'],
      child.id,
    );
    await primary.assistant.resolveTool(approvalId, approve: false);
    await finish(primary.id);
    expect(
      primary.assistant.messages.where((m) => m.content == 'Queued report'),
      hasLength(1),
    );
  });
  test(
    'long-term descendants delegate with direct-edge isolation and recursive removal',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Root task',
      );
      await finish(root.id);
      final middleResult = await root.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Middle', 'task': 'Middle task'},
      );
      final middle = workspaces.find(middleResult['agent_id'] as String)!;
      await finish(middle.id);
      final leafResult = await middle.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Leaf', 'task': 'Leaf task'},
      );
      final leaf = workspaces.find(leafResult['agent_id'] as String)!;
      await finish(leaf.id);
      expect(
        middle.assistant.messages.first.toolArguments!['source_agent_id'],
        root.id,
      );
      expect(
        leaf.assistant.messages.first.toolArguments!['source_agent_id'],
        middle.id,
      );
      await expectLater(
        root.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': leaf.id,
          'message': 'Skip parent',
        }),
        throwsStateError,
      );
      await expectLater(
        leaf.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': root.id,
          'message': 'Skip parent',
        }),
        throwsStateError,
      );
      await leaf.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': middle.id,
        'message': 'Report to parent',
      });
      await finish(middle.id);
      final temporaryResult = await leaf.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Temporary', 'task': 'Temporary task'},
      );
      final temporary = workspaces.find(temporaryResult['agent_id'] as String)!;
      await finish(temporary.id);
      final further = await temporary.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Recursive visible child', 'task': 'Continue delegation'},
      );
      final furtherId = further['agent_id'] as String;
      await finish(furtherId);
      expect(workspaces.find(furtherId)!.parentId, temporary.id);
      workspaces.remove(middle.id);
      expect(workspaces.sessions.map((s) => s.id), [root.id]);
      expect(workspaces.find(leaf.id), isNull);
      expect(workspaces.find(temporary.id), isNull);
      expect(workspaces.find(furtherId), isNull);
    },
  );

  test(
    'restore sorts arbitrary nested records and rejects invalid graphs without rewriting',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Root task',
      );
      await finish(root.id);
      final middle = await workspaces.create(
        title: 'Middle',
        task: 'Middle task',
        parentId: root.id,
      );
      await finish(middle.id);
      final leaf = await workspaces.create(
        title: 'Leaf',
        task: 'Leaf task',
        parentId: middle.id,
      );
      await finish(leaf.id);
      await workspaces.flush();
      workspaces.dispose();
      final data =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map<String, dynamic>;
      data['sessions'] = (data['sessions'] as List).reversed.toList();
      scope.preferences.setValue(
        AiWorkspaceProvider.storageKey,
        jsonEncode(data),
      );
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.find(leaf.id)!.parentId, middle.id);
      expect(workspaces.sessions, hasLength(3));
      workspaces.dispose();
      for (final invalidParent in [leaf.id, 'missing-parent']) {
        (data['sessions'] as List).firstWhere(
          (r) => r['id'] == middle.id,
        )['parentId'] = invalidParent;
        final invalid = jsonEncode(data);
        scope.preferences.setValue(AiWorkspaceProvider.storageKey, invalid);
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        expect(workspaces.persistenceError, isNotNull);
        expect(workspaces.sessions, isEmpty);
        await workspaces.flush();
        expect(
          scope.preferences.stringValue(AiWorkspaceProvider.storageKey, ''),
          invalid,
        );
        workspaces.dispose();
      }
      scope.preferences.setValue(AiWorkspaceProvider.storageKey, '');
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
    },
  );

  test(
    'nested automatic deliveries and both spawned kinds share the root budget',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Root task',
      );
      await finish(root.id);
      final middle = await workspaces.create(
        title: 'Middle',
        task: 'Middle task',
        parentId: root.id,
      );
      await finish(middle.id);
      final leaf = await workspaces.create(
        title: 'Leaf',
        task: 'Leaf task',
        parentId: middle.id,
      );
      await finish(leaf.id);
      for (
        var index = 0;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        final source = index.isEven ? root : leaf;
        await source.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': middle.id,
          'message': 'Delivery $index',
        });
        await finish(middle.id);
      }
      for (final kind in ['permanent', 'temporary']) {
        final result = await middle.assistant.workspaceToolHandler!(
          'spawn_agent',
          {'title': 'Spawn $kind', 'task': 'Keep budget'},
        );
        final spawned = workspaces.find(result['agent_id'] as String)!;
        await finish(spawned.id);
        expect(
          spawned.assistant.messages.first.toolArguments!['source_agent_id'],
          middle.id,
        );
        await expectLater(
          spawned.assistant.workspaceToolHandler!('send_agent_message', {
            'agent_id': middle.id,
            'message': 'Budget bypass $kind',
          }),
          throwsStateError,
        );
      }
      await workspaces.send(leaf.id, 'Human input resets entire root');
      await finish(leaf.id);
      final resumed = await root.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': middle.id, 'message': 'New collaboration'},
      );
      expect(resumed['delivered'], isTrue);
      await finish(middle.id);
    },
  );
  test(
    'explicit task permissions apply to root and long-term first turns without changing the parent',
    () async {
      final original = scope.provider.permissions;
      final selected = AiPermissions(
        mode: AiApprovalMode.custom,
        fullFiles: true,
      );
      askApproval = true;
      final root = await workspaces.createPrimary(
        title: 'Authorized root',
        task: 'Inspect with selected permissions',
        permissions: selected,
      );
      await finish(root.id);
      expect(root.assistant.permissions, same(selected));
      expect(root.assistant.pendingApproval, isNull);
      expect(root.result, 'Done: Inspect with selected permissions');
      expect(
        (requests.last['messages'] as List).where((m) => m['role'] == 'tool'),
        isNotEmpty,
      );
      expect(scope.provider.permissions, same(original));
      root.assistant.setPermissions(original);
      final child = await workspaces.create(
        title: 'Authorized long-term',
        task: 'Inspect long-term',
        parentId: root.id,
        permissions: selected,
      );
      await finish(child.id);
      expect(child.assistant.permissions, same(selected));
      expect(child.assistant.pendingApproval, isNull);
      expect(child.result, 'Done: Inspect long-term');
      expect(root.assistant.permissions, same(original));
      expect(scope.provider.permissions, same(original));
    },
  );

  test(
    'model-spawned tasks inherit permissions and reject explicit override',
    () async {
      final inherited = AiPermissions(
        mode: AiApprovalMode.custom,
        network: false,
        execution: false,
      );
      final elevated = AiPermissions(
        mode: AiApprovalMode.custom,
        fullFiles: true,
        execution: true,
        commandNoApproval: true,
      );
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Coordinate',
        permissions: inherited,
      );
      await finish(root.id);
      for (final kind in ['permanent', 'temporary']) {
        final result = await root.assistant.workspaceToolHandler!(
          'spawn_agent',
          {'title': 'Inherited $kind', 'task': 'Inherit only'},
        );
        final child = workspaces.find(result['agent_id'] as String)!;
        await finish(child.id);
        expect(child.assistant.permissions, same(inherited));
        expect(child.assistant.permissions.execution, isFalse);
        expect(child.assistant.permissions.fullFiles, isFalse);
        await expectLater(
          workspaces.create(
            title: 'Invalid $kind',
            task: 'No model override',
            parentId: root.id,
            kind: AiWorkspaceKind.permanent,
            permissions: elevated,
            modelInitiated: true,
          ),
          throwsStateError,
        );
      }
      final inheritedManual = await workspaces.create(
        title: 'Default inheritance',
        task: 'No explicit permissions',
        parentId: root.id,
      );
      await finish(inheritedManual.id);
      expect(inheritedManual.assistant.permissions, same(inherited));
      final spawn = root.assistant.workspaceToolDefinitions.singleWhere(
        (spec) => (spec['function'] as Map)['name'] == 'spawn_agent',
      );
      expect(
        ((spawn['function'] as Map)['parameters'] as Map)['properties'],
        isNot(contains('permissions')),
      );
      expect(root.assistant.permissions, same(inherited));
    },
  );
  test(
    'canvas style persists independently while restored tasks have no authorization',
    () async {
      await workspaces.initialized;
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.dots);
      var changes = 0;
      workspaces.addListener(() => changes++);
      workspaces.setCanvasStyle(AiTaskCanvasStyle.grid);
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.grid);
      expect(changes, 1);
      workspaces.setCanvasStyle(AiTaskCanvasStyle.grid);
      expect(changes, 1);
      final root = await workspaces.createPrimary(
        title: 'Saved task',
        task: 'Keep text only',
        permissions: AiPermissions(
          mode: AiApprovalMode.custom,
          fullFiles: true,
          execution: true,
          commandNoApproval: true,
        ),
      );
      await finish(root.id);
      await workspaces.flush();
      final topology =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map;
      expect(topology, isNot(contains('canvasStyle')));
      expect(
        scope.preferences.stringValue(
          AiWorkspaceProvider.canvasStyleStorageKey,
          '',
        ),
        'grid',
      );
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.grid);
      final restored = workspaces.find(root.id)!;
      expect(restored.assistant.permissions.mode, AiApprovalMode.onRequest);
      expect(restored.assistant.permissions.fullFiles, isFalse);
      expect(restored.assistant.permissions.execution, isFalse);
      expect(restored.assistant.permissions.commandNoApproval, isFalse);
      workspaces.setCanvasStyle(AiTaskCanvasStyle.plain);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.plain);
    },
  );

  test(
    'unknown saved canvas style falls back to dots without changing task storage',
    () async {
      await workspaces.initialized;
      scope.preferences.setValue(
        AiWorkspaceProvider.canvasStyleStorageKey,
        'future-style',
      );
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.dots);
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.canvasStyle, AiTaskCanvasStyle.dots);
      expect(workspaces.persistenceError, isNull);
    },
  );
  test(
    'root removal promotes latest direct long-term child and preserves other branches intact',
    () async {
      final permissions = AiPermissions(
        mode: AiApprovalMode.custom,
        execution: true,
      );
      final root = await workspaces.createPrimary(
        title: 'Old root',
        task: 'Coordinate',
      );
      await finish(root.id);
      final first = await workspaces.create(
        title: 'First branch',
        task: 'First',
        parentId: root.id,
      );
      await finish(first.id);
      final nested = await workspaces.create(
        title: 'Nested permanent',
        task: 'Nested',
        parentId: first.id,
      );
      await finish(nested.id);
      final replacement = await workspaces.create(
        title: 'Latest branch',
        task: 'Latest',
        parentId: root.id,
        permissions: permissions,
      );
      await finish(replacement.id);
      final keptTemp = await workspaces.create(
        title: 'Branch temporary',
        task: 'Keep',
        parentId: replacement.id,
        kind: AiWorkspaceKind.permanent,
      );
      await finish(keptTemp.id);
      final removedTemp = await workspaces.create(
        title: 'Sibling branch',
        task: 'Remove',
        parentId: root.id,
        kind: AiWorkspaceKind.permanent,
      );
      await finish(removedTemp.id);
      final assistant = replacement.assistant;
      final history = [...assistant.messages];
      final model = replacement.model;
      workspaces.remove(removedTemp.id);
      expect(workspaces.replacementRootFor(root.id), same(replacement));
      workspaces.select(root.id);
      workspaces.remove(root.id);
      expect(workspaces.find(root.id), isNull);
      expect(workspaces.find(removedTemp.id), isNull);
      expect(replacement.kind, AiWorkspaceKind.primary);
      expect(replacement.parentId, isNull);
      expect(first.parentId, replacement.id);
      expect(nested.parentId, first.id);
      expect(keptTemp.parentId, replacement.id);
      expect(workspaces.selected, same(replacement));
      expect(replacement.assistant, same(assistant));
      expect(replacement.assistant.messages, history);
      expect(replacement.assistant.permissions, same(permissions));
      expect(replacement.model, model);
      expect(workspaces.primaries, [replacement]);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.find(replacement.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(first.id)!.parentId, replacement.id);
      workspaces.remove(first.id);
      expect(workspaces.find(nested.id), isNull);
      expect(workspaces.find(replacement.id), isNotNull);
      expect(workspaces.find(keptTemp.id), isNotNull);
    },
  );

  test(
    'promoted task keeps automatic budget and dedupe and gains root capacity',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root',
        task: 'Coordinate',
      );
      await finish(root.id);
      final first = await workspaces.create(
        title: 'First',
        task: 'First',
        parentId: root.id,
      );
      await finish(first.id);
      final replacement = await workspaces.create(
        title: 'Replacement',
        task: 'Second',
        parentId: root.id,
      );
      await finish(replacement.id);
      for (
        var index = 0;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        await replacement.assistant.workspaceToolHandler!(
          'send_agent_message',
          {'agent_id': root.id, 'message': 'Original $index'},
        );
        await finish(root.id);
      }
      final retainedChild = await workspaces.create(
        title: 'Retained child',
        task: 'Retained',
        parentId: replacement.id,
      );
      await finish(retainedChild.id);
      // Retain a delivery between nodes that both survive promotion for dedupe.
      await workspaces.send(first.id, 'User permits fresh chain');
      await finish(first.id);
      await retainedChild.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': replacement.id, 'message': 'Retained delivery'},
      );
      await finish(replacement.id);
      for (
        var index = 1;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        await first.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': root.id,
          'message': 'Exhaust $index',
        });
        await finish(root.id);
      }
      workspaces.remove(root.id);
      final duplicate = await retainedChild.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': replacement.id, 'message': 'Retained delivery'},
      );
      expect(duplicate['duplicate'], isTrue);
      expect(duplicate['delivered'], isFalse);
      await expectLater(
        replacement.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': first.id,
          'message': 'Cannot reset by promotion',
        }),
        throwsStateError,
      );
      gate = Completer<void>();
      final childA = await workspaces.create(
        title: 'Busy A',
        task: 'Wait A',
        parentId: replacement.id,
      );
      final childB = await workspaces.create(
        title: 'Busy B',
        task: 'Wait B',
        parentId: replacement.id,
      );
      await workspaces.send(first.id, 'Wait first');
      expect(workspaces.runningCount, 3);
      expect(replacement.assistant.canSendMessage, isTrue);
      await workspaces.send(replacement.id, 'Root runs without child slot');
      expect(replacement.busy, isTrue);
      gate!.complete();
      for (final item in [childA, childB, first, replacement]) {
        await finish(item.id);
      }
      final spawned = await replacement.assistant.workspaceToolHandler!(
        'spawn_agent',
        {'title': 'Still delegates', 'task': 'Child after promotion'},
      );
      await finish(spawned['agent_id'] as String);
    },
  );

  test('root with a single visible child promotes that child', () async {
    final root = await workspaces.createPrimary(
      title: 'Root',
      task: 'Coordinate',
    );
    await finish(root.id);
    final temp = await workspaces.create(
      title: 'Temporary',
      task: 'Work',
      parentId: root.id,
      kind: AiWorkspaceKind.permanent,
    );
    await finish(temp.id);
    expect(workspaces.replacementRootFor(root.id), same(temp));
    workspaces.remove(root.id);
    expect(workspaces.sessions, [temp]);
    expect(temp.kind, AiWorkspaceKind.primary);
    expect(temp.parentId, isNull);
  });
  test(
    'manual reconnect preserves task state, enforces one parent and persists acyclic roles',
    () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Root');
      await finish(root.id);
      final other = await workspaces.createPrimary(
        title: 'Other root',
        task: 'Other',
      );
      await finish(other.id);
      final child = await workspaces.create(
        title: 'Long-term',
        task: 'Work',
        parentId: root.id,
      );
      await finish(child.id);
      final temporary = await workspaces.create(
        title: 'Temporary',
        task: 'Work',
        parentId: child.id,
        kind: AiWorkspaceKind.permanent,
      );
      await finish(temporary.id);
      final assistant = child.assistant;
      final permissions = assistant.permissions;
      final history = [...assistant.messages];
      workspaces.reparent(child.id, other.id);
      expect(workspaces.childrenOf(root.id), isEmpty);
      expect(workspaces.childrenOf(other.id), [child]);
      expect(child.assistant, same(assistant));
      expect(child.assistant.permissions, same(permissions));
      expect(child.assistant.messages, history);
      expect(temporary.parentId, child.id);
      expect(() => workspaces.reparent(child.id, child.id), throwsStateError);
      expect(() => workspaces.reparent(other.id, child.id), throwsStateError);
      workspaces.reparent(temporary.id, null);
      expect(temporary.kind, AiWorkspaceKind.primary);
      workspaces.reparent(temporary.id, child.id);
      expect(
        () => workspaces.reparent(child.id, temporary.id),
        throwsStateError,
      );
      expect(() => workspaces.reparent(child.id, 'missing'), throwsStateError);
      workspaces.reparent(child.id, null);
      expect(child.kind, AiWorkspaceKind.primary);
      expect(child.parentId, isNull);
      workspaces.reparent(other.id, child.id);
      expect(other.kind, AiWorkspaceKind.permanent);
      expect(other.parentId, child.id);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.find(child.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(other.id)!.parentId, child.id);
      expect(workspaces.find(temporary.id)!.parentId, child.id);
      final toolNames = workspaces
          .find(child.id)!
          .assistant
          .workspaceToolDefinitions
          .map((spec) => (spec['function'] as Map)['name']);
      expect(toolNames, isNot(contains('reparent')));
      expect(toolNames, isNot(contains('removeMany')));
    },
  );

  test(
    'detaching and merging trees preserves exhausted budgets and dedupe in both branches',
    () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Root');
      await finish(root.id);
      final child = await workspaces.create(
        title: 'Child',
        task: 'Child',
        parentId: root.id,
      );
      await finish(child.id);
      final grandchild = await workspaces.create(
        title: 'Grandchild',
        task: 'Grandchild',
        parentId: child.id,
      );
      await finish(grandchild.id);
      final other = await workspaces.createPrimary(
        title: 'Other',
        task: 'Other',
      );
      await finish(other.id);
      for (
        var index = 0;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        await grandchild.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': child.id,
          'message': 'Budget $index',
        });
        await finish(child.id);
      }
      workspaces.reparent(child.id, null);
      final duplicate = await grandchild.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': child.id, 'message': 'Budget 0'},
      );
      expect(duplicate['duplicate'], isTrue);
      await expectLater(
        grandchild.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': child.id,
          'message': 'After detach',
        }),
        throwsStateError,
      );
      workspaces.reparent(child.id, other.id);
      await expectLater(
        other.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': child.id,
          'message': 'After merge',
        }),
        throwsStateError,
      );
      workspaces.reparent(child.id, root.id);
      await expectLater(
        root.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': child.id,
          'message': 'Original branch retained',
        }),
        throwsStateError,
      );
    },
  );

  test(
    'same-tree reconnect does not duplicate automatic delivery counts',
    () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Root');
      await finish(root.id);
      final child = await workspaces.create(
        title: 'Child',
        task: 'Child',
        parentId: root.id,
      );
      await finish(child.id);
      final grandchild = await workspaces.create(
        title: 'Grandchild',
        task: 'Grandchild',
        parentId: child.id,
      );
      await finish(grandchild.id);
      for (var index = 0; index < 4; index++) {
        await child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': root.id,
          'message': 'First $index',
        });
        await finish(root.id);
      }
      workspaces.reparent(grandchild.id, root.id);
      workspaces.reparent(grandchild.id, child.id);
      for (
        var index = 4;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        await child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': root.id,
          'message': 'Next $index',
        });
        await finish(root.id);
      }
      await expectLater(
        child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': root.id,
          'message': 'Thirteenth',
        }),
        throwsStateError,
      );
    },
  );

  test(
    'batch deletion excludes selected branches from promotion and deduplicates descendants',
    () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Root');
      await finish(root.id);
      final kept = await workspaces.create(
        title: 'Kept',
        task: 'Kept',
        parentId: root.id,
      );
      await finish(kept.id);
      final selected = await workspaces.create(
        title: 'Selected latest',
        task: 'Delete',
        parentId: root.id,
      );
      await finish(selected.id);
      final descendant = await workspaces.create(
        title: 'Selected descendant',
        task: 'Delete too',
        parentId: selected.id,
      );
      await finish(descendant.id);
      final nestedSelected = await workspaces.create(
        title: 'Selected below survivor',
        task: 'Delete',
        parentId: kept.id,
      );
      await finish(nestedSelected.id);
      workspaces.removeMany([
        root.id,
        selected.id,
        descendant.id,
        nestedSelected.id,
        selected.id,
        'missing',
      ]);
      expect(workspaces.sessions, [kept]);
      expect(kept.kind, AiWorkspaceKind.primary);
      expect(kept.parentId, isNull);
      workspaces.removeMany([kept.id, kept.id]);
      expect(workspaces.sessions, isEmpty);
    },
  );
  test(
    'whole-tree merge retires old budget so human reset survives a later detach',
    () async {
      final root = await workspaces.createPrimary(
        title: 'Root A',
        task: 'Root A',
      );
      await finish(root.id);
      final merged = await workspaces.createPrimary(
        title: 'Root B',
        task: 'Root B',
      );
      await finish(merged.id);
      final child = await workspaces.create(
        title: 'Child B',
        task: 'Child B',
        parentId: merged.id,
      );
      await finish(child.id);
      for (
        var index = 0;
        index < AiWorkspaceProvider.maximumAutomaticMessages;
        index++
      ) {
        await child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': merged.id,
          'message': 'Repeat $index',
        });
        await finish(merged.id);
      }
      workspaces.reparent(merged.id, root.id);
      await expectLater(
        child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': merged.id,
          'message': 'Exhausted after merge',
        }),
        throwsStateError,
      );
      await workspaces.send(root.id, 'Human continues the merged tree');
      await finish(root.id);
      workspaces.reparent(merged.id, null);
      final delivered = await child.assistant.workspaceToolHandler!(
        'send_agent_message',
        {'agent_id': merged.id, 'message': 'Repeat 0'},
      );
      expect(delivered['delivered'], isTrue);
      expect(delivered['duplicate'], isNull);
      await finish(merged.id);
    },
  );
}
