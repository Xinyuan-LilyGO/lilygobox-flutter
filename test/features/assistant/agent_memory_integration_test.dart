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
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/agent_package_progress.dart';
import 'package:lilygobox/features/assistant/domain/memory_conflict.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/process_timeline.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';
import 'package:sqlite3/sqlite3.dart';

import 'assistant_test_scope.dart';

void main() {
  late Directory directory;
  late AgentStorage storage;
  late AssistantTestScope scope;
  late AiWorkspaceProvider workspaces;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late String service;
  final requests = <Map<String, dynamic>>[];
  final routes = <({String host, String? authorization})>[];
  var summary = 'Retained goals and unresolved work.';
  var consolidation = '{"memories":[]}';
  var consolidationStatus = 200;
  var replyStatus = 200;
  var reply = 'Done';
  var requestMemoryTool = false;
  var contextErrorOnce = false;
  var topologyRounds = 0;
  Completer<void>? consolidationGate;
  Completer<void>? consolidationStarted;
  Completer<void>? summaryGate;
  Completer<void>? summaryStarted;
  http.Response? summaryResponse;
  var retrySummaryOnce = false;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lilygobox-memory-');
    storage = AgentStorage(path: '${directory.path}/main.db');
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests.clear();
    routes.clear();
    summary = 'Retained goals and unresolved work.';
    consolidation = '{"memories":[]}';
    consolidationStatus = 200;
    replyStatus = 200;
    reply = 'Done';
    requestMemoryTool = false;
    contextErrorOnce = false;
    topologyRounds = 0;
    consolidationGate = null;
    consolidationStarted = null;
    summaryGate = null;
    summaryStarted = null;
    summaryResponse = null;
    retrySummaryOnce = false;
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        routes.add((
          host: request.url.host,
          authorization: request.headers['authorization'],
        ));
        final messages = body['messages'] as List;
        final consolidating = (messages.first['content'] as String).startsWith(
          'Consolidate durable',
        );
        if (consolidating) {
          consolidationStarted?.complete();
          await consolidationGate?.future;
        }
        if (!consolidating && contextErrorOnce) {
          contextErrorOnce = false;
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'context_length_exceeded',
                'message': 'context window is full',
              },
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        if ((messages.first['content'] as String).startsWith('Summarize')) {
          if (summaryStarted case final started? when !started.isCompleted) {
            started.complete();
          }
          await summaryGate?.future;
          if (retrySummaryOnce) {
            retrySummaryOnce = false;
            return http.Response('Busy', 429, headers: {'retry-after': '0'});
          }
          if (summaryResponse case final response?) return response;
        }
        if (!consolidating && topologyRounds > 0) {
          topologyRounds--;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'topology-$topologyRounds',
                        'type': 'function',
                        'function': {
                          'name': 'get_agent_topology',
                          'arguments': '{}',
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
        if (!consolidating && requestMemoryTool) {
          requestMemoryTool = false;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'memory-call',
                        'type': 'function',
                        'function': {
                          'name': 'save_memory',
                          'arguments': jsonEncode({
                            'content': 'Use filled icons',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      (messages.first['content'] as String).startsWith(
                        'Summarize',
                      )
                      ? summary
                      : consolidating
                      ? consolidation
                      : reply,
                },
              },
            ],
          }),
          consolidating ? consolidationStatus : replyStatus,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await scope.provider.initialized;
    service = await scope.provider.saveService(
      name: 'Fixture',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6.1-sol'],
      apiKey: 'private-test-key',
    );
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  });
  tearDown(() async {
    await workspaces.flush();
    workspaces.dispose();
    scope.dispose();
    await storage.close();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    await directory.delete(recursive: true);
  });
  Future<AiAgentWorkspace> create(String title, {String? parent}) =>
      workspaces.create(
        title: title,
        task: 'Fixture task',
        kind: parent == null
            ? AiWorkspaceKind.primary
            : AiWorkspaceKind.permanent,
        parentId: parent,
        serviceId: service,
        model: 'gpt-6.1-sol',
        startImmediately: false,
      );
  List<Map<String, dynamic>> consolidationRequests() => requests
      .where(
        (r) => ((r['messages'] as List).first['content'] as String).startsWith(
          'Consolidate durable',
        ),
      )
      .toList();

  test(
    'automatic memory retrieval is reused across tool continuations',
    () async {
      final agent = await create('Cached memory');
      agent.assistant.autoSaveMemory = false;
      topologyRounds = 3;
      await agent.assistant.sendMessage('Inspect the task group');
      int retrievals() => agent.assistant.messages
          .expand((message) => message.processEvents)
          .where((event) => event.action?.name == 'search_memory')
          .length;
      expect(retrievals(), 1);
      await agent.assistant.sendMessage('Check again');
      expect(retrievals(), 2);
      requestMemoryTool = true;
      await agent.assistant.sendMessage('Remember filled icons');
      expect(retrievals(), 4);
    },
  );

  test('automatic long-term memory is enabled by default and saves only bounded deduplicated candidates', () async {
    final agent = await create('Automatic memory');
    expect(agent.assistant.autoSaveMemory, isTrue);
    await storage.putMemory(
      id: 'existing',
      owner: agent.id,
      content: 'Use filled icons',
    );
    consolidation = jsonEncode({
      'memories': [
        'Use filled icons',
        'Reply in Chinese',
        ' Reply in Chinese ',
      ],
    });
    await agent.assistant.sendMessage(
      'For future conversations, reply in Chinese and use filled icons.',
    );
    await agent.assistant.pendingMemoryConsolidation;
    final saved = await storage.memories(agent.id);
    expect(saved.map((m) => m['content']).toSet(), {
      'Use filled icons',
      'Reply in Chinese',
    });
    final extraction = consolidationRequests().single;
    expect(
      extraction['reasoning_effort'],
      agent.assistant.reasoningEffort?.name,
    );
    expect(
      extraction['tools'] == null || (extraction['tools'] as List).isEmpty,
      isTrue,
    );
    expect(jsonEncode(extraction['messages']), contains('Use filled icons'));
    expect(agent.assistant.messages.last.content, 'Done');
    final action = agent.assistant.messages.last.processEvents
        .where((e) => e.action?.name == 'consolidate_memory')
        .single
        .action!;
    expect(action.succeeded, isTrue);
    expect(action.arguments['saved'], 1);
    expect(action.arguments['duplicates'], 2);
    await agent.assistant.sendMessage('Remember those same preferences.');
    await agent.assistant.pendingMemoryConsolidation;
    expect(await storage.memories(agent.id), hasLength(2));
  });

  test('automatic extraction runs once after the complete tool chain and deduplicates tool-saved facts', () async {
    final agent = await create('Tool chain memory');
    requestMemoryTool = true;
    consolidation = '{"memories":["Use filled icons"]}';
    await agent.assistant.sendMessage('Always use filled icons');
    await agent.assistant.pendingMemoryConsolidation;
    expect(consolidationRequests(), hasLength(1));
    expect(requests, hasLength(3));
    expect(await storage.memories(agent.id), hasLength(1));
    expect(agent.assistant.messages.last.content, 'Done');
    final event = agent.assistant.messages.last.processEvents
        .where((e) => e.action?.name == 'consolidate_memory')
        .single;
    expect(event.action!.arguments['saved'], 0);
    expect(event.action!.arguments['duplicates'], 1);
    expect(event.operationId, isNotNull);
  });

  test('automatic memory preference persists in snapshots, copies and reopened workflows', () async {
    final agent = await create('Memory preference');
    agent.assistant.autoSaveMemory = false;
    expect(
      agent.assistant.snapshotWorkspaceConversation()['autoSaveMemory'],
      isFalse,
    );
    final duplicate = await workspaces.duplicate(agent.id, title: 'Copy');
    expect(duplicate.assistant.autoSaveMemory, isFalse);
    await workspaces.flush();
    workspaces.dispose();
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.find(agent.id)!.assistant.autoSaveMemory, isFalse);
    expect(workspaces.find(duplicate.id)!.assistant.autoSaveMemory, isFalse);
  });

  test('either memory switch suppresses automatic extraction without changing reply', () async {
    final agent = await create('Disabled automatic memory');
    agent.assistant.autoSaveMemory = false;
    await agent.assistant.sendMessage('One');
    expect(consolidationRequests(), isEmpty);
    agent.assistant.autoSaveMemory = true;
    agent.assistant.useMemory = false;
    await agent.assistant.sendMessage('Two');
    expect(consolidationRequests(), isEmpty);
    expect(agent.assistant.autoSaveMemory, isTrue);
    expect(agent.assistant.messages.last.content, 'Done');
  });

  for (final malformed in [
    'not JSON',
    '{"memories":[42]}',
    '{"memories":["${'a' * 1001}"]}',
  ]) {
    test(
      'invalid automatic memory output leaves completed reply intact: ${malformed.length}',
      () async {
        final agent = await create('Invalid extraction');
        consolidation = malformed;
        await agent.assistant.sendMessage('A durable preference');
        expect(agent.assistant.error, isNull);
        expect(agent.assistant.messages.last.content, 'Done');
        expect(await storage.memories(agent.id), isEmpty);
        final action = agent.assistant.messages.last.processEvents
            .where((event) => event.action?.name == 'consolidate_memory')
            .single
            .action!;
        expect(action.succeeded, isFalse);
      },
    );
  }

  test(
    'automatic extraction service failure does not fail the ordinary reply',
    () async {
      final agent = await create('Extraction unavailable');
      consolidationStatus = 400;
      await agent.assistant.sendMessage('A durable preference');
      await agent.assistant.pendingMemoryConsolidation;
      expect(agent.assistant.error, isNull);
      expect(agent.assistant.messages.last.content, 'Done');
      expect(await storage.memories(agent.id), isEmpty);
    },
  );

  for (final interrupt in [
    'stop',
    'automatic off',
    'memory off',
    'delete agent',
  ]) {
    test('pending automatic memory cannot save after $interrupt', () async {
      final agent = await create('Cancelled extraction');
      consolidation = '{"memories":["Do not save this stale fact"]}';
      consolidationGate = Completer<void>();
      consolidationStarted = Completer<void>();
      final pending = agent.assistant.sendMessage('A durable preference');
      await consolidationStarted!.future;
      switch (interrupt) {
        case 'stop':
          agent.assistant.stopGeneration();
        case 'automatic off':
          agent.assistant.autoSaveMemory = false;
        case 'memory off':
          agent.assistant.useMemory = false;
        case 'delete agent':
          workspaces.removeMany([agent.id]);
      }
      consolidationGate!.complete();
      await pending;
      await agent.assistant.pendingMemoryConsolidation;
      expect(await storage.memories(agent.id), isEmpty);
      expect(agent.assistant.messages.last.content, 'Done');
      expect(agent.assistant.error, isNull);
    });
  }

  test('failed normal replies never begin automatic extraction', () async {
    final agent = await create('Failed reply');
    replyStatus = 400;
    await agent.assistant.sendMessage('A durable preference');
    expect(agent.assistant.error, isNotNull);
    expect(consolidationRequests(), isEmpty);
  });

  test(
    'guidance during background memory consolidation runs without waiting',
    () async {
      final agent = await create('Guided extraction');
      consolidation = '{"memories":[]}';
      final gate = Completer<void>();
      consolidationGate = gate;
      consolidationStarted = Completer<void>();
      final pending = agent.assistant.sendMessage('Initial task');
      await consolidationStarted!.future;
      await pending.timeout(const Duration(seconds: 2));
      expect(agent.assistant.busy, isFalse);
      await agent.assistant.receiveAgentMessage(
        sourceId: 'parent-id',
        sourceTitle: 'Parent',
        sourceKind: 'primary',
        content: 'Use the revised task',
        steer: true,
      );
      consolidationStarted = null;
      consolidationGate = null;
      gate.complete();
      await agent.assistant.pendingMemoryConsolidation;
      expect(agent.assistant.busy, isFalse);
      expect(
        agent.assistant.messages.any(
          (message) => message.content == 'Use the revised task',
        ),
        isTrue,
      );
      expect(await storage.memories(agent.id), isEmpty);
      expect(agent.assistant.error, isNull);
    },
  );

  test(
    'exports exclude recycled agents and their memory and transcript',
    () async {
      final active = await create('Active conversation');
      await storage.putMemory(
        id: 'active-memory',
        owner: active.id,
        content: 'Export this active fact',
      );
      final deleted = await create('Deleted conversation');
      await deleted.assistant.sendMessage('Private recycled transcript');
      await storage.putMemory(
        id: 'recycled-memory',
        owner: deleted.id,
        content: 'Private recycled fact',
      );
      workspaces.removeMany([deleted.id]);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.recycledAgents.single.id, deleted.id);
      final controller = AgentStorageController(workspaces)..owner = active.id;
      addTearDown(controller.dispose);
      for (final type in ['workflow', 'agent', 'chat', 'memory']) {
        final path = '${directory.path}/$type.tar.zst';
        await controller.export(path, type);
        final package = await controller.inspect(path);
        final serialized = jsonEncode(package);
        expect(serialized, isNot(contains(deleted.id)));
        expect(serialized, isNot(contains('Private recycled fact')));
        expect(serialized, isNot(contains('Private recycled transcript')));
        if (type != 'memory') {
          final workflow = package['workflow'] as Map;
          expect(workflow.containsKey('recycleBin'), isFalse);
          expect((workflow['sessions'] as List).map((s) => s['id']), [
            active.id,
          ]);
        }
        if (type != 'chat') {
          expect(
            (package['memories'] as List).single['content'],
            'Export this active fact',
          );
        }
      }
      controller.owner = deleted.id;
      for (final type in ['agent', 'chat', 'memory']) {
        await expectLater(
          controller.export('${directory.path}/deleted-$type.tar.zst', type),
          throwsStateError,
        );
      }
      await expectLater(
        controller.export('${directory.path}/backup.tar.zst', 'backup'),
        throwsArgumentError,
      );
      expect(workspaces.recycledAgents.single.id, deleted.id);
      expect(
        (await storage.memories(deleted.id)).single['content'],
        'Private recycled fact',
      );
    },
  );
  test(
    'deleted agent restores its original identity, conversation and memory',
    () async {
      final agent = await create('Restore me');
      await agent.assistant.sendMessage('Remember this conversation');
      await storage.putMemory(
        id: 'recycle-memory',
        owner: agent.id,
        content: 'Persistent fact',
      );
      final before = agent.assistant.snapshotWorkspaceConversation();
      workspaces.removeMany([agent.id]);
      await workspaces.flush();
      expect(workspaces.find(agent.id), isNull);
      expect(workspaces.recycledAgents.single.id, agent.id);
      final persisted = await storage.request('readWorkflowData') as Map;
      expect((persisted['recycleBin'] as List).length, 1);
      await workspaces.restoreRecycledAgent(agent.id);
      final restored = workspaces.find(agent.id)!;
      expect(restored.title, 'Restore me');
      expect(
        restored.assistant.snapshotWorkspaceConversation()['messages'],
        before['messages'],
      );
      expect(
        (await storage.memories(agent.id)).single['content'],
        'Persistent fact',
      );
      expect(workspaces.recycledAgents, isEmpty);
    },
  );
  test(
    'restore reconnects a surviving parent and otherwise becomes a main agent',
    () async {
      final parent = await create('Parent');
      final child = await create('Child', parent: parent.id);
      workspaces.removeMany([child.id]);
      await workspaces.restoreRecycledAgent(child.id);
      expect(workspaces.find(child.id)!.parentId, parent.id);
      workspaces.removeMany([child.id]);
      workspaces.removeMany([parent.id]);
      await workspaces.restoreRecycledAgent(child.id);
      expect(workspaces.find(child.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(child.id)!.parentId, isNull);
    },
  );
  test(
    'permanent deletion removes current memory and rejects old undo',
    () async {
      final agent = await create('Delete me');
      final other = await create('Keep me');
      await storage.putMemory(
        id: 'purge-memory',
        owner: agent.id,
        content: 'First',
      );
      await storage.putMemory(
        id: 'purge-memory',
        owner: agent.id,
        content: 'Second',
      );
      await storage.putMemory(
        id: 'keep-memory',
        owner: other.id,
        content: 'Retain',
      );
      final undo = workspaces.captureTopologyEdit();
      workspaces.removeMany([agent.id]);
      await workspaces.permanentlyDeleteRecycledAgents([agent.id]);
      expect(await storage.memories(agent.id), isEmpty);
      expect(await storage.memories(other.id), hasLength(1));
      await expectLater(workspaces.restoreTopologyEdit(undo), throwsStateError);
      workspaces.releaseTopologyEdit(undo);
    },
  );
  test('retention expires agents and never mode keeps them', () async {
    final agent = await create('Expires');
    workspaces.removeMany([agent.id]);
    await workspaces.purgeExpiredRecycledAgents(
      now: DateTime.now().add(const Duration(days: 31)),
    );
    expect(workspaces.recycledAgents, isEmpty);
    final kept = await create('Never expires');
    await workspaces.setRecycleRetentionDays(0);
    workspaces.removeMany([kept.id]);
    await workspaces.purgeExpiredRecycledAgents(
      now: DateTime.now().add(const Duration(days: 1000)),
    );
    expect(workspaces.recycledAgents.single.id, kept.id);
  });
  test('deletion undo and redo synchronize the recycle bin', () async {
    final agent = await create('Undo');
    final before = workspaces.captureTopologyEdit();
    workspaces.removeMany([agent.id]);
    final after = workspaces.captureTopologyEdit();
    await workspaces.restoreTopologyEdit(before, previous: after);
    expect(workspaces.find(agent.id), isNotNull);
    expect(workspaces.recycledAgents, isEmpty);
    await workspaces.restoreTopologyEdit(after, previous: before);
    expect(workspaces.find(agent.id), isNull);
    expect(workspaces.recycledAgents.single.id, agent.id);
    workspaces.releaseTopologyEdit(before);
    workspaces.releaseTopologyEdit(after);
  });
  test(
    'cancelled transfer stops before import and leaves existing data intact',
    () async {
      final agent = await create('Existing');
      await storage.putMemory(
        id: 'kept',
        owner: agent.id,
        content: 'Keep this fact',
      );
      final controller = AgentStorageController(workspaces)..owner = agent.id;
      addTearDown(controller.dispose);
      await expectLater(
        controller.runTransfer(() async {
          expect(controller.transferActive, isTrue);
          expect(controller.canCancelTransfer, isTrue);
          controller.cancelTransfer();
          expect(controller.canCancelTransfer, isFalse);
          await controller.import({'type': 'memory', 'memories': []});
        }),
        throwsA(isA<AgentPackageCancelled>()),
      );
      expect(controller.transferActive, isFalse);
      expect(controller.transferProgress, isNull);
      expect(
        (await storage.memories(agent.id)).single['content'],
        'Keep this fact',
      );
    },
  );

  test(
    'memory import cannot be cancelled after atomic commit begins',
    () async {
      final agent = await create('Target');
      final controller = AgentStorageController(workspaces)..owner = agent.id;
      addTearDown(controller.dispose);
      var observedCommit = false;
      controller.addListener(() {
        if (controller.transferProgress?.stage ==
            AgentPackageStage.committing) {
          observedCommit = true;
          expect(controller.canCancelTransfer, isFalse);
          controller.cancelTransfer();
        }
      });
      await controller.import({
        'type': 'memory',
        'memories': [
          {'id': 'incoming', 'owner': 'source', 'content': 'Imported fact'},
        ],
      });
      expect(observedCommit, isTrue);
      expect(
        (await storage.memories(agent.id)).single['content'],
        'Imported fact',
      );
      expect(controller.transferActive, isFalse);
    },
  );

  test('failed transfer releases its state and permits retry', () async {
    final controller = AgentStorageController(workspaces);
    addTearDown(controller.dispose);
    await expectLater(
      controller.runTransfer<void>(() async => throw StateError('Fixture')),
      throwsStateError,
    );
    expect(controller.transferActive, isFalse);
    expect(await controller.runTransfer(() async => 42), 42);
    expect(controller.transferProgress, isNull);
  });

  test('all package types are detected automatically and import without replacing agents', () async {
    final source = await create('Source');
    await storage.putMemory(
      id: 'source-fact',
      owner: source.id,
      content: 'Portable fact',
    );
    final target = await create('Target');
    await storage.putMemory(
      id: 'target-fact',
      owner: target.id,
      content: 'Existing target fact',
    );
    final controller = AgentStorageController(workspaces)..owner = source.id;
    addTearDown(controller.dispose);
    for (final type in ['chat', 'agent', 'workflow', 'memory']) {
      controller.owner = source.id;
      final path = '${directory.path}/automatic-$type.tar.zst';
      await controller.export(path, type);
      final package = await controller.inspect(path);
      expect(package['type'], type);
      final previousIds = workspaces.sessions.map((s) => s.id).toSet();
      controller.owner = target.id;
      await controller.import(package);
      expect(workspaces.find(source.id), isNotNull);
      expect(workspaces.find(target.id), isNotNull);
      final added = workspaces.sessions
          .where((s) => !previousIds.contains(s.id))
          .toList();
      if (type == 'memory') {
        expect(added, isEmpty);
        expect(
          (await storage.memories(target.id)).map((m) => m['content']),
          containsAll(['Existing target fact', 'Portable fact']),
        );
      } else {
        final expected =
            ((package['workflow'] as Map)['sessions'] as List).length;
        expect(added, hasLength(expected));
        expect(
          (await storage.memories(target.id)).single['content'],
          'Existing target fact',
        );
      }
    }
  });

  test(
    'stream compaction fixture imports below its automatic trigger',
    () async {
      final controller = AgentStorageController(workspaces);
      addTearDown(controller.dispose);
      final package = await controller.inspect(
        'artifacts/lilygobox-auto-compaction-conversation-test.tar.zst',
      );
      await controller.import(package);
      final assistant = workspaces.sessions.single.assistant;
      expect(assistant.contextBudgetTokens, 12000);
      expect(assistant.contextCompactionPercent, 28);
      expect(assistant.contextCompactionThresholdTokens, 3360);
      expect(assistant.estimatedContextTokens, inInclusiveRange(2400, 2900));
      expect(requests, isEmpty);
    },
  );

  test(
    'workflow import cancellation during staging publishes no agent or data',
    () async {
      final source = await create('Source');
      final controller = AgentStorageController(workspaces)..owner = source.id;
      addTearDown(controller.dispose);
      final path = '${directory.path}/cancel-stage.tar.zst';
      await controller.export(path, 'agent');
      final package = await controller.inspect(path);
      var cancelled = false;
      controller.addListener(() {
        final progress = controller.transferProgress;
        if (!cancelled &&
            progress?.stage == AgentPackageStage.analyzing &&
            progress?.completed == 1) {
          cancelled = true;
          expect(controller.canCancelTransfer, isTrue);
          controller.cancelTransfer();
        }
      });
      await expectLater(
        controller.import(package),
        throwsA(isA<AgentPackageCancelled>()),
      );
      expect(cancelled, isTrue);
      expect(workspaces.sessions.map((s) => s.id), [source.id]);
      expect(controller.transferActive, isFalse);
    },
  );

  test(
    'memory analysis yields to cancellation and preserves conflict decisions',
    () async {
      final target = await create('Target');
      final controller = AgentStorageController(workspaces)..owner = target.id;
      addTearDown(controller.dispose);
      final existing = [
        {'id': 'same', 'owner': target.id, 'content': 'Identical'},
        {'id': 'changed', 'owner': target.id, 'content': 'Old version'},
      ];
      for (final memory in existing) {
        await storage.putMemory(
          id: memory['id']!,
          owner: target.id,
          content: memory['content']!,
        );
      }
      final incoming = <Map<String, Object?>>[
        {'id': 'same', 'owner': 'source', 'content': 'Identical'},
        {'id': 'changed', 'owner': 'source', 'content': 'New version'},
        {'id': 'new', 'owner': 'source', 'content': 'New fact'},
        {'id': 'repeated', 'owner': 'source', 'content': 'New fact'},
        {'id': 'new', 'owner': 'source', 'content': 'Later incoming version'},
      ];
      final package = <String, dynamic>{'type': 'memory', 'memories': incoming};
      final expected = planMemoryImport(
        incoming,
        (await storage.memories(target.id)),
        (_) => target.id,
      );
      final actual = await controller.plan(package);
      expect(
        actual.map((m) => m.resolution),
        expected.map((m) => m.resolution),
      );
      expect(actual.map((m) => m.conflict), expected.map((m) => m.conflict));
      expect(actual.map((m) => m.duplicate), expected.map((m) => m.duplicate));
      final cancellationStarted = Completer<void>();
      controller.addListener(() {
        if (!cancellationStarted.isCompleted &&
            controller.transferProgress?.stage == AgentPackageStage.analyzing) {
          cancellationStarted.complete();
          Timer.run(controller.cancelTransfer);
        }
      });
      await expectLater(
        controller.plan({
          'type': 'memory',
          'memories': List.generate(
            1000,
            (i) => {'id': '$i', 'owner': 'source', 'content': 'Fact $i'},
          ),
        }),
        throwsA(isA<AgentPackageCancelled>()),
      );
      expect(cancellationStarted.isCompleted, isTrue);
    },
  );

  test('all agent exports use safe names, full IDs and a timestamp', () async {
    final agent = await create('My / agent:*');
    final controller = AgentStorageController(workspaces)..owner = agent.id;
    addTearDown(controller.dispose);
    for (final type in ['agent', 'chat', 'memory']) {
      final name = controller.suggestedExportName(
        type,
        now: DateTime(2026, 11, 15, 9, 5, 3),
      );
      final content = type == 'agent' ? 'full' : type;
      expect(
        name,
        'lilygobox-agent-${agent.id}-$content-package-202611150905.tar.zst',
      );
    }
    expect(
      controller.suggestedExportName(
        'agent',
        children: true,
        now: DateTime(2026, 11, 15, 9, 5),
      ),
      'lilygobox-agent-workflow-package-202611150905.tar.zst',
    );
    expect(
      controller.suggestedExportName('workflow', now: DateTime(2026, 11, 15)),
      'lilygobox-agent-workflow-package-202611150000.tar.zst',
    );
  });
  test(
    'storage starts without a shared scope and selects a created agent',
    () async {
      final controller = AgentStorageController(workspaces);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.owner, isEmpty);
      expect(controller.memories, isEmpty);
      await expectLater(
        controller.saveMemory('No agent exists'),
        throwsStateError,
      );
      await expectLater(
        controller.plan({'type': 'memory', 'memories': []}),
        throwsStateError,
      );
      final root = await create('Root');
      await controller.refresh();
      expect(controller.owner, root.id);
      await controller.saveMemory('Only this agent remembers');
      final other = await create('Other');
      expect(
        (await storage.memories(root.id)).single['content'],
        'Only this agent remembers',
      );
      expect(await storage.memories(other.id), isEmpty);
    },
  );
  test('workflow package preserves conversations, current memory and layout without credentials', () async {
    final root = await create('Root');
    final child = await create('Child', parent: root.id);
    await child.assistant.sendMessage('Original chat');
    await storage.putMemory(
      id: 'memory',
      owner: child.id,
      content: 'Use filled icons',
    );
    await storage.putMemory(
      id: 'memory',
      owner: child.id,
      content: 'Always use filled icons',
    );
    workspaces.updateCanvasPositions({
      root.id: [120, 80],
      child.id: [600, 80],
    });
    final controller = AgentStorageController(workspaces)..owner = child.id;
    addTearDown(controller.dispose);
    final path = '${directory.path}/workflow.tar.zst';
    await controller.export(path, 'workflow');
    await controller.export(path, 'workflow');
    final package = await controller.inspect(path);
    expect(jsonEncode(package), isNot(contains('private-test-key')));
    final memory = (package['memories'] as List).single as Map;
    expect(memory.containsKey('versions'), isFalse);
    expect(memory['content'], 'Always use filled icons');
    await controller.import(package);
    expect(workspaces.sessions, hasLength(4));
    final copy = workspaces.sessions.last;
    expect(copy.id, isNot(child.id));
    expect(
      copy.assistant.messages.map((m) => m.content),
      child.assistant.messages.map((m) => m.content),
    );
    expect(
      (await storage.memories(copy.id)).single['content'],
      'Always use filled icons',
    );
    expect(workspaces.canvasPositions[copy.id], [600, 80]);
    expect(copy.assistant.permissions.execution, isFalse);
    await workspaces.flush();
    final saved = jsonDecode((await storage.readWorkflow())!) as Map;
    expect(saved['sessions'], hasLength(4));
  });
  test('memory controls persist and copied agents have independent current memories', () async {
    final root = await create('Root');
    await storage.putMemory(
      id: 'original',
      owner: root.id,
      content: 'First preference',
    );
    await storage.putMemory(
      id: 'original',
      owner: root.id,
      content: 'Updated preference',
    );
    root.assistant.useMemory = false;
    root.assistant.contextBudgetTokens = 64000;
    await workspaces.flush();
    final saved = jsonDecode((await storage.readWorkflow())!) as Map;
    final conversation =
        (saved['sessions'] as List).single['conversation'] as Map;
    expect(conversation['useMemory'], isFalse);
    expect(conversation['contextBudgetTokens'], 64000);
    final copy = await workspaces.duplicate(root.id, title: 'Root (2)');
    final copied = (await storage.memories(copy.id)).single;
    expect(copied['id'], isNot('original'));
    expect(copied['content'], 'Updated preference');
    await storage.putMemory(
      id: copied['id'] as String,
      owner: copy.id,
      content: 'Branch only',
    );
    expect(
      (await storage.memories(root.id)).single['content'],
      'Updated preference',
    );
  });
  test(
    'compaction percentage persists across restart, forks and packages',
    () async {
      final root = await create('Configurable context');
      final assistant = root.assistant;
      expect(assistant.contextCompactionPercent, 90);
      assistant.contextBudgetTokens = 10001;
      assistant.contextCompactionPercent = 75;
      expect(assistant.contextCompactionThresholdTokens, 7500);
      assistant.contextBudgetTokens = 1;
      expect(assistant.contextCompactionThresholdTokens, 1);
      assistant.contextBudgetTokens = 10001;
      expect(() => assistant.contextCompactionPercent = 0, throwsRangeError);
      expect(() => assistant.contextCompactionPercent = 101, throwsRangeError);
      expect(assistant.contextCompactionPercent, 75);

      final copy = await workspaces.duplicate(root.id, title: 'Branch');
      expect(copy.assistant.contextCompactionPercent, 75);
      expect(copy.assistant.contextCompactionThresholdTokens, 7500);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.find(root.id)!.assistant.contextCompactionPercent, 75);
      expect(
        workspaces.find(root.id)!.assistant.contextCompactionThresholdTokens,
        7500,
      );

      final controller = AgentStorageController(workspaces)..owner = root.id;
      addTearDown(controller.dispose);
      final path = '${directory.path}/percentage.tar.zst';
      await controller.export(path, 'agent');
      final package = await controller.inspect(path);
      final before = workspaces.sessions.map((s) => s.id).toSet();
      await controller.import(package);
      final imported = workspaces.sessions.singleWhere(
        (s) => !before.contains(s.id),
      );
      expect(imported.assistant.contextCompactionPercent, 75);
      expect(imported.assistant.contextCompactionThresholdTokens, 7500);
    },
  );

  test('new and missing context settings use the default budget', () async {
    final root = await create('Default context');
    expect(root.assistant.contextBudgetTokens, 272000);
    expect(root.assistant.contextCompactionPercent, 90);
    expect(root.assistant.contextCompactionThresholdTokens, 244800);
    root.assistant.contextBudgetTokens = 64000;
    root.assistant.contextCompactionPercent = 75;
    root.assistant.restoreWorkspaceConversation({
      'messages': <Object?>[],
      'history': <Object?>[],
    });
    expect(root.assistant.contextBudgetTokens, 272000);
    expect(root.assistant.contextCompactionPercent, 90);
    expect(root.assistant.contextCompactionThresholdTokens, 244800);
  });

  test('invalid saved context budgets restore the default', () async {
    for (final value in [0, -1, '272000', 2.5, null]) {
      final root = await create('Invalid budget $value');
      root.assistant.restoreWorkspaceConversation({
        'messages': <Object?>[],
        'history': <Object?>[],
        'contextBudgetTokens': value,
      });
      expect(root.assistant.contextBudgetTokens, 272000);
      expect(root.assistant.contextCompactionThresholdTokens, 244800);
    }
  });

  test('valid saved context budgets are not replaced by the default', () async {
    final root = await create('Custom context');
    for (final value in [32000, 64000, 1000000]) {
      root.assistant.restoreWorkspaceConversation({
        'messages': <Object?>[],
        'history': <Object?>[],
        'contextBudgetTokens': value,
        'contextCompactionPercent': 75,
      });
      expect(root.assistant.contextBudgetTokens, value);
      expect(root.assistant.contextCompactionPercent, 75);
      expect(
        root.assistant.contextCompactionThresholdTokens,
        value * 75 ~/ 100,
      );
    }
  });

  test('invalid saved compaction percentages restore the default', () async {
    for (final value in [0, 101, '75', null]) {
      final root = await create('Invalid percent $value');
      root.assistant.restoreWorkspaceConversation({
        'messages': <Object?>[],
        'history': <Object?>[],
        'contextCompactionPercent': value,
      });
      expect(root.assistant.contextCompactionPercent, 90);
    }
  });

  test(
    'invalid current memory rolls back both staged agents and database writes',
    () async {
      final root = await create('Original');
      await workspaces.flush();
      final before = await storage.readWorkflow();
      final controller = AgentStorageController(workspaces);
      addTearDown(controller.dispose);
      final package = <String, dynamic>{
        'type': 'workflow',
        'workflow': workspaces.exportData(),
        'memories': [
          {
            'id': 'remote',
            'owner': root.id,
            'content': 'New fact',
            'hash': memoryContentHash('New fact'),
          },
        ],
      };
      final plan = await controller.plan(package);
      // Corrupt the prepared current entry so validation fails inside commit.
      plan.single.content = '   ';
      await expectLater(
        controller.import(package, plan: plan),
        throwsStateError,
      );
      expect(workspaces.sessions, hasLength(1));
      expect(await storage.readWorkflow(), before);
      expect(await storage.memories(root.id), isEmpty);
    },
  );
  test(
    'canvas memory import stages a new idle agent without an owner',
    () async {
      final controller = AgentStorageController(workspaces);
      addTearDown(controller.dispose);
      final package = controller.memoryPackageForNewAgent({
        'type': 'memory',
        'memories': [
          {
            'id': 'remote-memory',
            'owner': 'remote-owner',
            'content': 'Imported durable fact',
            'hash': memoryContentHash('Imported durable fact'),
          },
        ],
      }, title: 'Imported agent');
      final plan = await controller.plan(package);
      // Preparing and reviewing the import must not create any canvas node.
      expect(workspaces.sessions, isEmpty);
      expect(await storage.request('allMemories'), isEmpty);
      await controller.import(package, plan: plan);
      final imported = workspaces.sessions.single;
      expect(imported.kind, AiWorkspaceKind.primary);
      expect(imported.parentId, isNull);
      expect(imported.busy, isFalse);
      expect(imported.assistant.selectedModel, isNull);
      expect(imported.assistant.messages, isEmpty);
      expect(requests, isEmpty);
      expect(
        (await storage.memories(imported.id)).single['content'],
        'Imported durable fact',
      );
    },
  );

  test('failed canvas memory import leaves no new agent or memories', () async {
    final original = await create('Original');
    final controller = AgentStorageController(workspaces)..owner = original.id;
    addTearDown(controller.dispose);
    await workspaces.flush();
    final before = await storage.readWorkflow();
    final package = controller.memoryPackageForNewAgent({
      'type': 'memory',
      'memories': [
        {
          'id': 'remote-memory',
          'owner': 'remote-owner',
          'content': 'Imported durable fact',
        },
      ],
    }, title: 'Imported agent');
    final plan = await controller.plan(package);
    plan.single.content = '   ';
    await expectLater(controller.import(package, plan: plan), throwsStateError);
    expect(workspaces.sessions.map((agent) => agent.id), [original.id]);
    expect(await storage.readWorkflow(), before);
    expect(await storage.request('allMemories'), isEmpty);
  });

  test('small memory package uses scoped reads and preserves saved conversations', () async {
    final source = await create('Source');
    final other = await create('Unrelated');
    final recycled = await create('Recycled');
    await recycled.assistant.sendMessage(
      List.filled(1000, 'Archived text').join(' '),
    );
    workspaces.removeMany([recycled.id]);
    await storage.putMemory(
      id: 'unrelated-fact',
      owner: other.id,
      content: 'Unrelated',
    );
    for (var index = 0; index < 7; index++) {
      await storage.putMemory(
        id: 'fact-$index',
        owner: source.id,
        content: 'Fact $index',
      );
    }
    await workspaces.flush();
    final db = sqlite3.open('${directory.path}/main.db');
    addTearDown(db.close);
    db.execute('''
      CREATE TRIGGER reject_conversation_rewrite BEFORE UPDATE ON state
      WHEN OLD.key IN ('conversation:${source.id}', 'conversation:${other.id}')
      BEGIN SELECT RAISE(ABORT, 'Existing conversation was rewritten'); END;
    ''');

    final controller = AgentStorageController(workspaces)..owner = source.id;
    addTearDown(controller.dispose);
    final path = '${directory.path}/small-memory.tar.zst';
    await controller.export(path, 'memory');
    final exported = await controller.inspect(path);
    expect(exported['workflow'], isNull);
    expect(
      (exported['memories'] as List).map((fact) => fact['owner']),
      everyElement(source.id),
    );
    expect(exported['memories'], hasLength(7));

    final agentPackage = controller.memoryPackageForNewAgent(
      exported,
      title: 'Imported',
    );
    final analysisTotals = <int>{};
    controller.addListener(() {
      if (controller.transferProgress case AgentPackageProgress(
        stage: .analyzing,
        :final total?,
      )) {
        analysisTotals.add(total);
      }
    });
    final plan = await controller.plan(agentPackage);
    expect(plan, hasLength(7));
    expect(analysisTotals, {7});
    await controller.import(agentPackage, plan: plan);
    final imported = workspaces.sessions.singleWhere(
      (agent) => agent.title == 'Imported',
    );
    expect(imported.assistant.messages, isEmpty);
    expect(await storage.memories(imported.id), hasLength(7));
    expect(await storage.memories(other.id), hasLength(1));
    expect(workspaces.recycledAgents.single.id, recycled.id);

    controller.owner = imported.id;
    await controller.export(path, 'memory');
    final roundtrip = await controller.inspect(path);
    expect(
      (roundtrip['memories'] as List).map((fact) => fact['content']),
      unorderedEquals((exported['memories'] as List).map((fact) => fact['content'])),
    );

    controller.owner = other.id;
    await controller.import(exported);
    expect(await storage.memories(other.id), hasLength(8));
  });
  Map<String, Object?> compactionSnapshot({int count = 16}) => {
    'serviceId': service,
    'model': 'gpt-6.1-sol',
    'messages': <Object?>[],
    'history': [
      for (var i = 0; i < count; i++)
        {'role': i.isEven ? 'user' : 'assistant', 'content': 'History $i'},
    ],
  };

  AiProcessEntry inlineCompaction(AiMessage reply) =>
      buildAiProcessTimeline(reply.processEvents).singleWhere(
        (entry) =>
            entry.event.action?.name == 'compact_context' ||
            entry.event.toolName == 'compact_context',
      );

  test(
    'manual compaction uses the selected service without switching chat models',
    () async {
      final root = await create('Dedicated compaction');
      final assistant = root.assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot());
      final compactionService = await scope.provider.saveService(
        name: 'Summarizer',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://summary.example.test/v1',
        models: ['summary-gpt-6.1-sol'],
        apiKey: 'summary-key',
      );
      final chatEffort = assistant.reasoningEffort;
      assistant.selectApprovalModel((
        serviceId: service,
        model: 'gpt-6.1-sol',
        reasoningEffort: AiReasoningEffort.high,
      ));
      assistant.selectCompactionModel((
        serviceId: compactionService,
        model: 'summary-gpt-6.1-sol',
        reasoningEffort: AiReasoningEffort.ultra,
      ));

      expect(
        await assistant.compactContext(),
        AiContextCompactionOutcome.compacted,
      );
      expect(requests.single['model'], 'summary-gpt-6.1-sol');
      expect(requests.single['reasoning_effort'], 'ultra');
      expect(routes.single, (
        host: 'summary.example.test',
        authorization: 'Bearer summary-key',
      ));
      expect(assistant.messages.single.model, 'summary-gpt-6.1-sol');
      expect(assistant.selectedModel, 'gpt-6.1-sol');
      expect(assistant.reasoningEffort, chatEffort);

      final restored = (await create('Restored models')).assistant;
      restored.restoreWorkspaceConversation(
        assistant.snapshotWorkspaceConversation(),
      );
      expect(restored.auxiliaryModels, assistant.auxiliaryModels);
      restored.selectCompactionModel(null);
      expect(
        restored.auxiliaryModels.approval,
        assistant.auxiliaryModels.approval,
      );
      expect(restored.auxiliaryModels.compaction, isNull);
    },
  );

  test('missing dedicated compaction model does not send history to another provider', () async {
    final assistant = (await create('Missing dedicated compaction')).assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot());
    assistant.selectCompactionModel((
      serviceId: 'removed',
      model: 'summarizer',
      reasoningEffort: null,
    ));

    expect(
      await assistant.compactContext(),
      AiContextCompactionOutcome.unavailableModel,
    );
    expect(requests, isEmpty);
    expect(assistant.snapshotWorkspaceConversation()['history'], hasLength(16));
  });

  test('workflow snapshot restores approval and compaction models including recycle entries', () async {
    final active = await create('Active');
    final recycled = await create('Recycled');
    final selection = (
      serviceId: service,
      model: 'gpt-6.1-sol',
      reasoningEffort: AiReasoningEffort.high,
    );
    for (final agent in [active, recycled]) {
      agent.assistant.auxiliaryModels = (
        approval: selection,
        compaction: selection,
        memory: selection,
      );
    }
    workspaces.removeMany([recycled.id]);
    final mapping = await workspaces.importData(workspaces.exportData());
    final importedActive = workspaces.find(mapping[active.id])!;
    expect(importedActive.assistant.auxiliaryModels, (
      approval: selection,
      compaction: selection,
      memory: selection,
    ));
    final importedRecycled = mapping[recycled.id]!;
    await workspaces.restoreRecycledAgent(importedRecycled);
    expect(workspaces.find(importedRecycled)!.assistant.auxiliaryModels, (
      approval: selection,
      compaction: selection,
      memory: selection,
    ));
    expect(active.assistant.auxiliaryModels, (
      approval: selection,
      compaction: selection,
      memory: selection,
    ));
  });

  for (final type in ['chat', 'agent', 'workflow']) {
    test(
      '$type archive round-trips approval and context settings',
      () async {
        final source = await create('Scoped package');
        final key = 'export-private-key';
        final auxiliaryService = await scope.provider.saveService(
          name: 'Auxiliary models',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://auxiliary.example.test/v1',
          models: ['deepseek-flash', 'deepseek-v4-pro'],
          apiKey: key,
        );
        final approval = (
          serviceId: auxiliaryService,
          model: 'deepseek-v4-pro',
          reasoningEffort: AiReasoningEffort.none,
        );
        final compaction = (
          serviceId: auxiliaryService,
          model: 'deepseek-flash',
          reasoningEffort: AiReasoningEffort.high,
        );
        final permissions = AiPermissions(
          mode: AiApprovalMode.custom,
          network: false,
          execution: true,
          commandNoApproval: true,
          fullFiles: true,
          files: AiFileAccess.none,
          folders: [directory.path],
          folderAccess: {directory.path: AiFileAccess.readWrite},
        );
        final reviewRecord = ConversationCodec.message(
          const AiMessage(
            id: 'review-record',
            role: 'assistant',
            content: 'The read was approved.',
            processEvents: [
              AiProcessEvent(
                type: AiProcessEventType.status,
                status: AiResponseStatus.reviewingPermission,
                elapsed: Duration.zero,
                model: 'deepseek-v4-pro',
                reasoningEffort: AiReasoningEffort.none,
              ),
            ],
          ),
        );
        source.assistant.restoreWorkspaceConversation({
          'messages': [reviewRecord],
          'history': [
            {'role': 'assistant', 'content': 'The read was approved.'},
          ],
          'summary': 'Saved context summary',
        });
        source.assistant
          ..selectApprovalModel(approval)
          ..selectCompactionModel(compaction)
          ..contextBudgetTokens = 12000
          ..contextCompactionPercent = 28
          ..setPermissions(permissions);
        await source.assistant.setReasoningEffort(AiReasoningEffort.high);

        final controller = AgentStorageController(workspaces)
          ..owner = source.id;
        addTearDown(controller.dispose);
        await controller.saveMemory('Long-term memory fixture');
        final path = '${directory.path}/scoped-$type.tar.zst';
        await controller.export(path, type);
        final package = await controller.inspect(path);
        final workflow = package['workflow'] as Map;
        final record = (workflow['sessions'] as List).single as Map;
        final conversation = record['conversation'] as Map;
        expect(conversation['approvalModel'], {
          'serviceId': auxiliaryService,
          'model': approval.model,
          'effort': approval.reasoningEffort.name,
        });
        expect(conversation['compactionModel'], {
          'serviceId': auxiliaryService,
          'model': compaction.model,
          'effort': compaction.reasoningEffort.name,
        });
        expect(record['permissions'], permissions.toJson());
        expect(workflow, isNot(contains('recycleBin')));
        expect(package['memories'], hasLength(type == 'chat' ? 0 : 1));
        expect(jsonEncode(package), isNot(contains(key)));
        expect((conversation['messages'] as List).single, reviewRecord);

        await controller.import(package);
        final imported = workspaces.sessions.singleWhere(
          (session) => session.id != source.id,
        );
        expect(imported.busy, isFalse);
        expect(
          imported.assistant.selectedModel,
          source.assistant.selectedModel,
        );
        expect(imported.assistant.reasoningEffort, AiReasoningEffort.high);
        expect(imported.assistant.contextBudgetTokens, 12000);
        expect(imported.assistant.contextCompactionPercent, 28);
        expect(
          imported.assistant.snapshotWorkspaceConversation(),
          allOf(
            containsPair('summary', conversation['summary']),
            containsPair('history', conversation['history']),
          ),
        );
        expect(
          imported.assistant.messages.single.processEvents.single.model,
          'deepseek-v4-pro',
        );
        expect(imported.assistant.auxiliaryModels, (
          approval: approval,
          compaction: compaction,
          memory: null,
        ));
        expect(
          imported.assistant.permissions.toJson(),
          permissions.toJson(),
        );
        expect(source.assistant.permissions.toJson(), permissions.toJson());
      },
    );
  }

  test(
    'manual compaction reports insufficient history without requesting a model',
    () async {
      final root = await create('Short history');
      expect(
        await root.assistant.compactContext(),
        AiContextCompactionOutcome.insufficientHistory,
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'manual compaction reports unavailable model without changing history',
    () async {
      final root = await create('Missing model');
      root.assistant.restoreWorkspaceConversation(compactionSnapshot());
      await scope.provider.removeService(service);
      expect(
        await root.assistant.compactContext(),
        AiContextCompactionOutcome.unavailableModel,
      );
      expect(
        root.assistant.snapshotWorkspaceConversation()['history'],
        hasLength(16),
      );
      expect(requests, isEmpty);
    },
  );

  test('manual compaction records empty model output as a failure', () async {
    final root = await create('Empty summary');
    root.assistant.restoreWorkspaceConversation(compactionSnapshot());
    summary = ' ';
    await expectLater(
      root.assistant.compactContext(),
      throwsA(
        isA<AiCompactionException>().having(
          (error) => error.issue,
          'issue',
          AiCompactionIssue.emptySummary,
        ),
      ),
    );
    expect(
      root.assistant.snapshotWorkspaceConversation()['history'],
      hasLength(16),
    );
  });

  test('a valid summary without savings keeps the context unchanged', () async {
    final assistant = (await create('No savings')).assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot());
    summary = 'Summary ' * 100;
    expect(
      await assistant.compactContext(),
      AiContextCompactionOutcome.unchanged,
    );
    final record = assistant.messages.single;
    expect(record.status, AiResponseStatus.completed);
    expect(record.processingSteps.single.arguments['noTokenSavings'], isTrue);
    expect(assistant.snapshotWorkspaceConversation()['history'], hasLength(16));
  });

  test(
    'context-limit recovery fails when the summary saves no tokens',
    () async {
      final assistant = (await create('Recovery without savings')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot());
      assistant.useMemory = false;
      contextErrorOnce = true;
      summary = 'Summary ' * 100;

      await assistant.sendMessage('Latest question');

      expect(requests, hasLength(2));
      final response = assistant.messages.last;
      expect(response.role, 'assistant');
      expect(response.status, AiResponseStatus.failed);
      expect(
        inlineCompaction(response).event.action!.arguments,
        containsPair('compactionIssue', 'noTokenSavings'),
      );
      expect(assistant.snapshotWorkspaceConversation()['summary'], isEmpty);
    },
  );

  test('one compression covers long conversations, shares in-flight work and retains raw turns', () async {
    final root = await create('Batched summary');
    final assistant = root.assistant;
    final oldText = '🪴\n\u0001' * 21000 + 'MIDDLE_REQUIREMENT' + '多行文本' * 9000;
    assistant.restoreWorkspaceConversation({
      ...compactionSnapshot(),
      'contextBudgetTokens': 8192,
      'messages': [
        ConversationCodec.message(
          AiMessage(id: 'first', role: 'user', content: oldText),
        ),
      ],
      'history': [
        {'role': 'user', 'content': oldText},
        {'role': 'assistant', 'content': 'Recorded'},
        {'role': 'user', 'content': 'CURRENT_REQUEST'},
      ],
    });
    final first = assistant.compactContext();
    expect(identical(first, assistant.compactContext()), isTrue);
    expect(await first, AiContextCompactionOutcome.compacted);
    expect(requests.length, greaterThan(4));
    final recovered = StringBuffer();
    for (final request in requests) {
      final content = (request['messages'] as List).last['content'] as String;
      expect(content.length, lessThan(4500));
      expect(request['max_tokens'], 1024);
      final payload = jsonDecode(content) as Map;
      for (final entry in (payload['messages'] as List).whereType<Map>()) {
        if (entry['role'] == 'user') recovered.write(entry['content']);
      }
    }
    expect(recovered.toString(), oldText);
    expect(assistant.messages.first.content, oldText);
    expect(assistant.messages.last.role, 'compaction');
    expect(assistant.snapshotWorkspaceConversation()['history'], [
      {'role': 'user', 'content': 'CURRENT_REQUEST'},
    ]);
  });

  test('final reply crossing the threshold compacts prior turns', () async {
    final nextService = await scope.provider.saveService(
      name: 'Next service',
      baseUrl: 'https://next.test/v1',
      protocol: AiApiProtocol.openAiChatCompletions,
      models: ['new-model'],
      apiKey: 'other-test-key',
    );
    final assistant = (await create('Final reply')).assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot(count: 6));
    assistant.contextBudgetTokens = 2000;
    reply = ('Long answer ' * 1000).trimRight();
    consolidationGate = Completer<void>();
    consolidationStarted = Completer<void>();
    final pending = assistant.sendMessage('Latest question');
    await consolidationStarted!.future;
    await assistant.selectModel(nextService, 'new-model');
    consolidationGate!.complete();
    await pending;
    await assistant.pendingMemoryConsolidation;

    final firstSummary = requests.indexWhere(
      (request) => ((request['messages'] as List).first['content'] as String)
          .startsWith('Summarize'),
    );
    expect(firstSummary, greaterThanOrEqualTo(1));
    expect(requests[firstSummary]['model'], 'gpt-6.1-sol');
    expect(assistant.selectedModel, 'new-model');
    expect(assistant.snapshotWorkspaceConversation()['summary'], summary);
    expect(assistant.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    final response = assistant.messages.last;
    final record = inlineCompaction(response);
    expect(response.content, reply);
    expect(response.status, AiResponseStatus.completed);
    expect(record.events.first.model, 'gpt-6.1-sol');
    expect(record.events.first.toolArguments, {'trigger': 'auto'});
    expect(record.event.elapsed, greaterThan(Duration.zero));
    expect(response.elapsed, greaterThanOrEqualTo(record.event.elapsed));
    final restored = (await create('Restore auto compaction')).assistant;
    restored.restoreWorkspaceConversation(
      assistant.snapshotWorkspaceConversation(),
    );
    expect(restored.messages.last.id, response.id);
    final restoredRecord = inlineCompaction(restored.messages.last);
    expect(restoredRecord.id, record.id);
    expect(restoredRecord.events.first.model, record.events.first.model);
    expect(restoredRecord.event.action!.arguments['outcome'], 'compacted');
  });

  test('failed pre-request summary does not send the reply request', () async {
    final assistant = (await create('Single attempt')).assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot(count: 16));
    assistant.contextBudgetTokens = 100;
    assistant.useMemory = false;
    summary = '';
    await assistant.sendMessage('Latest question');

    expect(requests, hasLength(1));
    expect(assistant.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    expect(assistant.canContinue, isFalse);
    await assistant.continueGeneration();
    expect(requests, hasLength(1));
    final response = assistant.messages.last;
    expect(response.status, AiResponseStatus.failed);
    expect(response.content, isEmpty);
    expect(
      inlineCompaction(response).event.action!.arguments,
      containsPair('compactionIssue', 'emptySummary'),
    );
    expect(assistant.snapshotWorkspaceConversation()['summary'], isEmpty);
  });

  test('failed turn-end compaction keeps the reply and queued input', () async {
    final assistant = (await create('Failed turn-end compaction')).assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot(count: 6));
    assistant.contextBudgetTokens = 2000;
    assistant.useMemory = false;
    reply = 'Long answer ' * 1000;
    summary = '';
    summaryStarted = Completer<void>();
    summaryGate = Completer<void>();
    final pending = assistant.sendMessage('Latest question');
    await summaryStarted!.future;
    await assistant.sendMessage('Queued question');
    summaryGate!.complete();
    await pending;

    expect(requests, hasLength(2));
    final response = assistant.messages.singleWhere(
      (item) => item.role == 'assistant',
    );
    expect(response.content, reply.trimRight());
    expect(response.status, AiResponseStatus.failed);
    expect(assistant.messages.last.id, response.id);
    expect(
      inlineCompaction(response).event.action!.arguments['outcome'],
      'failed',
    );
    expect(assistant.pendingGuidance.single.content, 'Queued question');
  });

  for (final (finishReason, content, issue) in [
    ('length', 'Partial summary', AiCompactionIssue.outputLimit),
    ('stop', '', AiCompactionIssue.reasoningOnly),
    ('stop', 'Goals retained.', null),
  ]) {
    test(
      'GPT and DeepSeek automatic compaction: ${issue?.name ?? 'success'}',
      () async {
        final assistant = (await create('Cross-service compaction')).assistant;
        assistant.restoreWorkspaceConversation(compactionSnapshot());
        assistant.contextBudgetTokens = 100;
        assistant.useMemory = false;
        final summaryService = await scope.provider.saveService(
          name: 'DeepSeek fixture',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://summary.example.test/v1',
          models: ['deepseek-flash'],
          apiKey: 'summary-key',
        );
        assistant.selectCompactionModel((
          serviceId: summaryService,
          model: 'deepseek-flash',
          reasoningEffort: AiReasoningEffort.low,
        ));
        summaryResponse = http.Response(
          [
                {
                  'choices': [
                    {
                      'delta': {'reasoning_content': 'Thinking'},
                    },
                  ],
                },
                if (content.isNotEmpty)
                  {
                    'choices': [
                      {
                        'delta': {'content': content},
                      },
                    ],
                  },
                {
                  'choices': [
                    {'finish_reason': finishReason},
                  ],
                },
                {
                  'choices': [],
                  'usage': {'completion_tokens': 12},
                },
              ].map((chunk) => 'data: ${jsonEncode(chunk)}\n\n').join() +
              'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );

        await assistant.sendMessage('Latest question');

        expect(requests.map((request) => request['model']), [
          'deepseek-flash',
          if (issue == AiCompactionIssue.outputLimit) 'deepseek-flash',
          if (issue == null) 'gpt-6.1-sol',
        ]);
        expect(routes.first.host, 'summary.example.test');
        expect(requests.first['thinking'], {'type': 'enabled'});
        expect(requests.first['reasoning_effort'], 'low');
        expect(requests.first['max_tokens'], 2048);
        expect(assistant.selectedModel, 'gpt-6.1-sol');
        expect(assistant.messages.map((message) => message.role), [
          'user',
          'assistant',
        ]);
        final response = ConversationCodec.read(
          ConversationCodec.message(assistant.messages.last),
        );
        final record = inlineCompaction(response);
        expect(response.model, 'gpt-6.1-sol');
        expect(record.events.first.model, 'deepseek-flash');
        expect(record.events.first.reasoningEffort, AiReasoningEffort.low);
        expect(record.events.first.toolArguments?['trigger'], 'auto');
        final snapshot = assistant.snapshotWorkspaceConversation();
        if (issue == null) {
          expect(response.content, reply);
          expect(response.status, AiResponseStatus.completed);
          expect(record.event.action!.succeeded, isTrue);
          expect(snapshot['summary'], content);
        } else {
          expect(response.status, AiResponseStatus.failed);
          expect(response.processEvents.last.status, AiResponseStatus.failed);
          expect(response.content, isEmpty);
          expect(record.event.action!.succeeded, isFalse);
          expect(
            record.event.action!.arguments,
            allOf(
              containsPair('compactionIssue', issue.name),
              containsPair('finishReason', finishReason),
              containsPair('outputTokens', 12),
              containsPair(
                'outputLimit',
                issue == AiCompactionIssue.outputLimit ? 4096 : 2048,
              ),
            ),
          );
          expect(snapshot['summary'], isEmpty);
          expect(snapshot['history'], hasLength(17));
        }
      },
    );
  }

  test(
    'pre-request auto compaction uses its own model and resumes the same reply',
    () async {
      final assistant = (await create('Resume after compaction')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot(count: 16));
      final compactionService = await scope.provider.saveService(
        name: 'Summarizer',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://summary.example.test/v1',
        models: ['summary-gpt-5.4'],
        apiKey: 'summary-key',
      );
      assistant.selectCompactionModel((
        serviceId: compactionService,
        model: 'summary-gpt-5.4',
        reasoningEffort: AiReasoningEffort.none,
      ));
      assistant.contextBudgetTokens = 100;
      assistant.useMemory = false;
      summaryGate = Completer<void>();
      summaryStarted = Completer<void>();
      final pending = assistant.sendMessage('Latest question');
      await summaryStarted!.future;
      expect(assistant.messages.map((message) => message.role), [
        'user',
        'assistant',
      ]);
      final started = assistant.messages.last;
      final startedRecord = inlineCompaction(started);
      expect(started.content, isEmpty);
      expect(startedRecord.event.status, AiResponseStatus.connecting);
      expect(startedRecord.event.elapsed, Duration.zero);
      summaryGate!.complete();
      await pending;

      final response = assistant.messages.last;
      final record = inlineCompaction(response);
      expect(response.id, started.id);
      expect(record.id, startedRecord.id);
      expect(record.events.first.model, 'summary-gpt-5.4');
      expect(record.events.first.reasoningEffort, AiReasoningEffort.none);
      expect(requests.first['model'], 'summary-gpt-5.4');
      expect(requests.first['reasoning_effort'], 'none');
      expect(requests.last['model'], 'gpt-6.1-sol');
      expect(
        requests.last['reasoning_effort'],
        assistant.reasoningEffort?.name,
      );
      expect(record.event.action!.arguments['outcome'], 'compacted');
      expect(response.content, reply);
      expect(response.elapsed, greaterThanOrEqualTo(record.event.elapsed));
      final context = requests.last['messages'] as List;
      expect(jsonEncode(context), contains(summary));
      expect(context.last['content'], 'Latest question');
      expect(context.where((item) => item['role'] == 'compaction'), isEmpty);
    },
  );

  test('continuing stopped pre-request compaction reuses its record before replying', () async {
    final assistant = (await create('Stopped pre-request compaction'))
        .assistant;
    assistant.restoreWorkspaceConversation(compactionSnapshot(count: 16));
    assistant.contextBudgetTokens = 100;
    assistant.useMemory = false;
    summaryGate = Completer<void>();
    summaryStarted = Completer<void>();
    final pending = assistant.sendMessage('Latest question');
    await summaryStarted!.future;
    assistant.stopGeneration();
    summaryGate!.complete();
    await pending;

    final cancelled = assistant.messages[1];
    final cancelledRecord = inlineCompaction(cancelled);
    expect(cancelled.status, AiResponseStatus.stopped);
    expect(cancelledRecord.event.action!.arguments['outcome'], 'cancelled');
    expect(assistant.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    expect(requests, hasLength(1));
    summaryGate = Completer<void>();
    summaryStarted = Completer<void>();
    final interruptedResume = assistant.continueGeneration();
    await summaryStarted!.future;
    expect(assistant.messages[1].id, cancelled.id);
    expect(inlineCompaction(assistant.messages[1]).id, cancelledRecord.id);
    assistant.cancelContextCompaction();
    summaryGate!.complete();
    await interruptedResume;

    expect(assistant.canContinue, isTrue);
    expect(assistant.messages[1].status, AiResponseStatus.stopped);
    expect(assistant.messages, hasLength(2));
    expect(requests, hasLength(2));
    await assistant.continueGeneration();

    expect(requests, hasLength(4));
    expect(assistant.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    expect(assistant.messages[1].id, cancelled.id);
    expect(assistant.messages[1].status, AiResponseStatus.completed);
    final resumedRecord = inlineCompaction(assistant.messages[1]);
    expect(resumedRecord.id, cancelledRecord.id);
    expect(resumedRecord.event.action!.arguments['outcome'], 'compacted');
    expect(
      resumedRecord.event.elapsed,
      greaterThan(cancelledRecord.event.elapsed),
    );
    expect(assistant.messages.last.content, reply);
    final context = requests.last['messages'] as List;
    expect(context.last['content'], 'Latest question');
  });

  test(
    'stopping context limit recovery preserves the reply request record',
    () async {
      final assistant = (await create('Stop context limit recovery')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot(count: 6));
      assistant.contextBudgetTokens = 100000;
      assistant.useMemory = false;
      contextErrorOnce = true;
      summaryGate = Completer<void>();
      summaryStarted = Completer<void>();
      final pending = assistant.sendMessage('Latest question');
      await summaryStarted!.future;
      final reply = assistant.messages.last;
      expect(reply.role, 'assistant');
      expect(requests, hasLength(2));

      assistant.stopGeneration();
      summaryGate!.complete();
      await pending;

      expect(assistant.messages.last.id, reply.id);
      expect(assistant.messages.last.status, AiResponseStatus.stopped);
      expect(assistant.canContinue, isTrue);
    },
  );

  test(
    'context limit before output compacts once and resumes the same turn',
    () async {
      final assistant = (await create('Recover context error')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot(count: 6));
      assistant.contextBudgetTokens = 100000;
      assistant.useMemory = false;
      contextErrorOnce = true;
      await assistant.sendMessage('Latest question');

      expect(assistant.messages.map((message) => message.role), [
        'user',
        'assistant',
      ]);
      expect(assistant.messages.last.content, reply);
      expect(
        requests.where(
          (request) =>
              ((request['messages'] as List).first['content'] as String)
                  .startsWith('Summarize'),
        ),
        hasLength(1),
      );
      final record = inlineCompaction(assistant.messages.last);
      expect(record.events.first.toolArguments?['trigger'], 'auto');
      expect(record.event.action!.arguments['outcome'], 'compacted');
    },
  );

  test(
    'continuing stopped turn-end compaction does not request another reply',
    () async {
      final assistant = (await create('Stop final compaction')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot(count: 6));
      assistant.contextBudgetTokens = 2000;
      assistant.useMemory = false;
      reply = 'A' * 12000;
      summaryGate = Completer<void>();
      summaryStarted = Completer<void>();
      final pending = assistant.sendMessage('Latest question');
      await summaryStarted!.future;
      final started = assistant.messages.last;
      final startedRecord = inlineCompaction(started);
      expect(started.content, reply);
      expect(startedRecord.event.toolArguments?['trigger'], 'auto');
      expect(startedRecord.event.status, AiResponseStatus.connecting);
      assistant.stopGeneration();
      summaryGate!.complete();
      await pending;

      expect(assistant.messages.last.content, reply);
      expect(assistant.messages.last.id, started.id);
      expect(assistant.messages.last.status, AiResponseStatus.stopped);
      expect(
        inlineCompaction(assistant.messages.last)
            .event
            .action!
            .arguments['outcome'],
        'cancelled',
      );
      expect(assistant.snapshotWorkspaceConversation()['summary'], isEmpty);
      expect(
        assistant.snapshotWorkspaceConversation()['history'] as List,
        hasLength(greaterThanOrEqualTo(8)),
      );

      final cancelled = assistant.messages.last;
      final requestCount = requests.length;
      await assistant.continueGeneration();

      final resumedRequests = requests.skip(requestCount);
      expect(resumedRequests, isNotEmpty);
      expect(
        resumedRequests.map(
          (request) => (request['messages'] as List).first['content'],
        ),
        everyElement(startsWith('Summarize')),
      );
      expect(assistant.messages.map((message) => message.role), [
        'user',
        'assistant',
      ]);
      expect(assistant.messages[1].content, reply);
      expect(assistant.messages.last.id, cancelled.id);
      expect(assistant.messages.last.elapsed, greaterThan(cancelled.elapsed!));
      expect(assistant.messages.last.status, AiResponseStatus.completed);
      final resumedRecord = inlineCompaction(assistant.messages.last);
      expect(resumedRecord.id, startedRecord.id);
      expect(resumedRecord.event.action!.arguments['outcome'], 'compacted');
      expect(assistant.snapshotWorkspaceConversation()['summary'], summary);
    },
  );

  test(
    'changing live state preserves completed turns as the next request prefix',
    () async {
      final root = await create('Stable prefix');
      final assistant = root.assistant;
      assistant.useMemory = false;
      var timer = 1;
      assistant.workspaceRuntimeContext = () => {'runtimeTick': timer};
      await assistant.sendMessage('First');
      timer++;
      await assistant.sendMessage('Second');
      timer++;
      await assistant.sendMessage('Third');
      final previous = requests[requests.length - 2]['messages'] as List;
      final next = requests.last['messages'] as List;
      final volatileAt = previous.indexWhere(
        (item) =>
            (item['content'] as String?).toString().contains('runtimeTick'),
      );
      expect(volatileAt, greaterThan(1));
      expect(next.take(volatileAt), previous.take(volatileAt));
      expect(jsonEncode(next), contains('runtimeTick\\\":3'));
      expect(next.last['content'], 'Third');
    },
  );

  test(
    'clearing a conversation cancels a pending summary without restoring it',
    () async {
      final root = await create('Cancelled summary');
      root.assistant.restoreWorkspaceConversation(compactionSnapshot());
      summaryGate = Completer<void>();
      summaryStarted = Completer<void>();
      final pending = root.assistant.compactContext();
      await summaryStarted!.future;
      root.assistant.clearConversation();
      summaryGate!.complete();
      expect(await pending, AiContextCompactionOutcome.cancelled);
      expect(
        root.assistant.snapshotWorkspaceConversation()['history'],
        isEmpty,
      );
      expect(
        root.assistant.snapshotWorkspaceConversation()['summary'],
        isEmpty,
      );
    },
  );

  test(
    'manual compaction cancellation preserves the original context',
    () async {
      final root = await create('Cancelled summary');
      root.assistant.restoreWorkspaceConversation(compactionSnapshot());
      summaryGate = Completer<void>();
      summaryStarted = Completer<void>();
      var notifications = 0;
      root.assistant.addListener(() => notifications++);
      final pending = root.assistant.compactContext();
      await summaryStarted!.future;
      expect(root.assistant.compacting.value, isTrue);
      final started = root.assistant.messages.last;
      expect(started.role, 'compaction');
      expect(started.status, AiResponseStatus.connecting);
      expect(started.processEvents.single.elapsed, Duration.zero);
      final persistentRevision = root.assistant.persistenceRevision;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(root.assistant.messages.last.elapsed, greaterThan(Duration.zero));
      expect(root.assistant.persistenceRevision, persistentRevision);
      final startedNotifications = notifications;

      root.assistant.cancelContextCompaction();
      expect(notifications, greaterThan(startedNotifications));
      summaryGate!.complete();

      expect(await pending, AiContextCompactionOutcome.cancelled);
      expect(root.assistant.compacting.value, isFalse);
      final stopped = root.assistant.messages.last;
      expect(stopped.id, started.id);
      expect(stopped.status, AiResponseStatus.stopped);
      expect(stopped.elapsed!.inMicroseconds, greaterThan(0));
      expect(stopped.finishedAt, isNotNull);
      expect(stopped.processingSteps.single.arguments['outcome'], 'cancelled');
      expect(stopped.processEvents.last.status, AiResponseStatus.stopped);
      expect(
        root.assistant.snapshotWorkspaceConversation()['history'],
        hasLength(16),
      );
      expect(
        root.assistant.snapshotWorkspaceConversation()['summary'],
        isEmpty,
      );
    },
  );

  test('compaction preserves raw transcript, records its step and forks the summary', () async {
    final root = await create('Summary');
    final messages = [
      for (var i = 0; i < 16; i++)
        ConversationCodec.message(
          AiMessage(
            id: 'restored-$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'Original text $i',
          ),
        ),
    ];
    root.assistant.restoreWorkspaceConversation({
      'serviceId': service,
      'model': 'gpt-6.1-sol',
      'messages': messages,
      'history': [
        for (final m in messages) {'role': m['role'], 'content': m['content']},
      ],
    });
    expect(
      await root.assistant.compactContext(),
      AiContextCompactionOutcome.compacted,
    );
    final snapshot = root.assistant.snapshotWorkspaceConversation();
    expect(snapshot['messages'], hasLength(17));
    expect(root.assistant.messages[15].processEvents, isEmpty);
    final record = root.assistant.messages.last;
    expect(record.role, 'compaction');
    expect(record.status, AiResponseStatus.completed);
    final restored = ConversationCodec.read(ConversationCodec.message(record));
    expect(restored.createdAt, record.createdAt);
    expect(restored.finishedAt, record.finishedAt);
    expect(restored.elapsed, record.elapsed);
    expect(restored.processingSteps.single.arguments['trigger'], 'manual');
    final entries = buildAiProcessTimeline(restored.processEvents);
    expect(entries, hasLength(3));
    expect(entries.first.event.status, AiResponseStatus.connecting);
    expect(entries.first.event.elapsed, Duration.zero);
    expect(entries[1].events.map((event) => event.status), [
      AiResponseStatus.thinking,
      AiResponseStatus.streaming,
      null,
    ]);
    expect(entries[1].event.action!.arguments['outcome'], 'compacted');
    expect(entries[1].event.action!.name, 'compact_context');
    expect(entries.last.event.status, AiResponseStatus.completed);
    expect(entries.last.event.elapsed, restored.elapsed);
    expect(snapshot['history'], hasLength(8));
    expect(snapshot['summary'], 'Retained goals and unresolved work.');
    final copy = await workspaces.duplicate(root.id, title: 'Summary (2)');
    expect(
      copy.assistant.snapshotWorkspaceConversation()['summary'],
      snapshot['summary'],
    );
    await storage.putMemory(
      id: 'pref',
      owner: root.id,
      content: '这个项目统一使用实心图标',
    );
    await root.assistant.sendMessage('这个项目的实心图标设置是什么');
    expect(jsonEncode(requests.last['messages']), contains('这个项目统一使用实心图标'));
    expect(
      root.assistant.messages.map((m) => m.id).toSet().length,
      root.assistant.messages.length,
    );
  });
  test(
    'manual compaction failure persists independently of previous replies',
    () async {
      final assistant = (await create('Failed compaction')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot());
      summaryResponse = http.Response(
        jsonEncode({
          'error': {'code': 'invalid_model', 'message': 'Model unavailable'},
        }),
        400,
        headers: {'content-type': 'application/json'},
      );
      await expectLater(assistant.compactContext(), throwsA(anything));
      final record = ConversationCodec.read(
        ConversationCodec.message(assistant.messages.single),
      );
      expect(record.role, 'compaction');
      expect(record.status, AiResponseStatus.failed);
      expect(record.processingSteps.single.arguments['outcome'], 'failed');
      expect(record.processingSteps.single.arguments['httpStatus'], 400);
      expect(
        record.processingSteps.single.arguments['providerCode'],
        'invalid_model',
      );
      expect(
        record.processingSteps.single.output,
        contains('Model unavailable'),
      );
      expect(record.processEvents.last.status, AiResponseStatus.failed);
      expect(record.elapsed!.inMicroseconds, greaterThan(0));
      expect(record.requestError, isNotNull);
      expect(
        assistant.snapshotWorkspaceConversation()['history'],
        hasLength(16),
      );
    },
  );
  test(
    'summary retries keep the actual attempt in the same model operation',
    () async {
      final assistant = (await create('Summary retry')).assistant;
      assistant.restoreWorkspaceConversation(compactionSnapshot());
      retrySummaryOnce = true;
      expect(
        await assistant.compactContext(),
        AiContextCompactionOutcome.compacted,
      );
      final record = ConversationCodec.read(
        ConversationCodec.message(assistant.messages.single),
      );
      final entries = buildAiProcessTimeline(record.processEvents);
      expect(entries[1].events.first.type, AiProcessEventType.retry);
      expect(entries[1].events.first.retry?.attempt, 1);
      expect(record.retries.single.attempt, 1);
      expect(entries.last.event.status, AiResponseStatus.completed);
    },
  );
  test('database transactions reject stale memory conflict previews', () async {
    await storage.saveWorkflow({'sessions': [], 'version': 1});
    await storage.putMemory(id: 'a', owner: 'agent-a', content: 'First');
    final preview = (await storage.memories('agent-a')).single;
    await storage.putMemory(
      id: 'a',
      owner: 'agent-a',
      content: 'Edited while reviewing',
    );
    await expectLater(
      storage.commitImport(
        {'sessions': [], 'version': 1},
        [
          {
            'id': 'a',
            'owner': 'agent-a',
            'content': 'Imported',
            'expectedHash': preview['hash'],
          },
        ],
      ),
      throwsStateError,
    );
    expect(
      (await storage.memories('agent-a')).single['content'],
      'Edited while reviewing',
    );
  });

  test(
    'custom memory model runs non-blocking in background and is inherited by child agents',
    () async {
      final memoryService = await scope.provider.saveService(
        name: 'Memory service',
        baseUrl: 'https://memory.test/v1',
        protocol: AiApiProtocol.openAiChatCompletions,
        models: ['gpt-6.1-sol'],
        apiKey: 'memory-test-key',
      );
      final memorySelection = (
        serviceId: memoryService,
        model: 'gpt-6.1-sol',
        reasoningEffort: AiReasoningEffort.low,
      );
      final agent = await create('Background memory agent');
      agent.assistant.selectMemoryModel(memorySelection);
      consolidation = '{"memories":["Prefers concise summaries"]}';
      consolidationGate = Completer<void>();
      consolidationStarted = Completer<void>();

      await agent.assistant.sendMessage('Remember I prefer concise summaries');
      expect(agent.assistant.busy, isFalse);
      expect(agent.assistant.messages.last.content, 'Done');
      await consolidationStarted!.future;
      expect(await storage.memories(agent.id), isEmpty);

      consolidationGate!.complete();
      await agent.assistant.pendingMemoryConsolidation;

      final extraction = consolidationRequests().single;
      expect(extraction['model'], 'gpt-6.1-sol');
      expect(extraction['reasoning_effort'], 'low');
      final saved = await storage.memories(agent.id);
      expect(
        saved.map((m) => m['content']),
        contains('Prefers concise summaries'),
      );

      final child = await workspaces.create(
        title: 'Child Worker',
        task: 'Handle delegated task',
        parentId: agent.id,
        requestedBy: agent,
        startImmediately: false,
      );
      expect(child.assistant.auxiliaryModels.memory, memorySelection);
    },
  );

  test(
    'disabling per-turn memory retrieval still keeps manual memory tools available',
    () async {
      final agent = await create('Manual memory tools');
      agent.assistant.useMemory = false;
      requestMemoryTool = true;
      await agent.assistant.sendMessage('Save this preference manually');
      final toolNames = (requests.first['tools'] as List)
          .map((tool) => (tool['function'] as Map)['name'])
          .toSet();
      expect(toolNames, containsAll(['search_memory', 'save_memory', 'delete_memory']));
      final saved = await storage.memories(agent.id);
      expect(saved.map((m) => m['content']), contains('Use filled icons'));
      expect(consolidationRequests(), isEmpty);
    },
  );
}
