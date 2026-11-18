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
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';

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
  var summary = 'Retained goals and unresolved work.';
  var consolidation = '{"memories":[]}';
  var consolidationStatus = 200;
  var replyStatus = 200;
  var requestMemoryTool = false;
  var topologyRounds = 0;
  Completer<void>? consolidationGate;
  Completer<void>? consolidationStarted;
  Completer<void>? summaryGate;
  Completer<void>? summaryStarted;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lilygobox-memory-');
    storage = AgentStorage(path: '${directory.path}/main.db');
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests.clear();
    summary = 'Retained goals and unresolved work.';
    consolidation = '{"memories":[]}';
    consolidationStatus = 200;
    replyStatus = 200;
    requestMemoryTool = false;
    topologyRounds = 0;
    consolidationGate = null;
    consolidationStarted = null;
    summaryGate = null;
    summaryStarted = null;
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        final messages = body['messages'] as List;
        final consolidating = (messages.first['content'] as String).startsWith(
          'Consolidate durable',
        );
        if (consolidating) {
          consolidationStarted?.complete();
          await consolidationGate?.future;
        }
        if ((messages.first['content'] as String).startsWith('Summarize')) {
          summaryStarted?.complete();
          await summaryGate?.future;
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
                      : 'Done',
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
    final saved = await storage.memories(agent.id);
    expect(saved.map((m) => m['content']).toSet(), {
      'Use filled icons',
      'Reply in Chinese',
    });
    final extraction = consolidationRequests().single;
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
    expect(await storage.memories(agent.id), hasLength(2));
  });

  test('automatic extraction runs once after the complete tool chain and deduplicates tool-saved facts', () async {
    final agent = await create('Tool chain memory');
    requestMemoryTool = true;
    consolidation = '{"memories":["Use filled icons"]}';
    await agent.assistant.sendMessage('Always use filled icons');
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
    'guidance during memory consolidation waits and then continues',
    () async {
      final agent = await create('Guided extraction');
      consolidation = '{"memories":[]}';
      final gate = Completer<void>();
      consolidationGate = gate;
      consolidationStarted = Completer<void>();
      final pending = agent.assistant.sendMessage('Initial task');
      await consolidationStarted!.future;
      await agent.assistant.receiveAgentMessage(
        sourceId: 'parent-id',
        sourceTitle: 'Parent',
        sourceKind: 'primary',
        content: 'Use the revised task',
        steer: true,
      );
      expect(agent.assistant.busy, isTrue);
      expect(
        agent.assistant.pendingGuidance.single.content,
        'Use the revised task',
      );
      consolidationStarted = null;
      consolidationGate = null;
      gate.complete();
      await pending.timeout(const Duration(seconds: 2));
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
        final path = '${directory.path}/$type.7z';
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
          controller.export('${directory.path}/deleted-$type.7z', type),
          throwsStateError,
        );
      }
      await expectLater(
        controller.export('${directory.path}/backup.7z', 'backup'),
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
      final path = '${directory.path}/automatic-$type.7z';
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
    'workflow import cancellation during staging publishes no agent or data',
    () async {
      final source = await create('Source');
      final controller = AgentStorageController(workspaces)..owner = source.id;
      addTearDown(controller.dispose);
      final path = '${directory.path}/cancel-stage.7z';
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
        'lilygobox-agent-${agent.id}-$content-package-202611150905.7z',
      );
    }
    expect(
      controller.suggestedExportName(
        'agent',
        children: true,
        now: DateTime(2026, 11, 15, 9, 5),
      ),
      'lilygobox-agent-workflow-package-202611150905.7z',
    );
    expect(
      controller.suggestedExportName('workflow', now: DateTime(2026, 11, 15)),
      'lilygobox-agent-workflow-package-202611150000.7z',
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
    final path = '${directory.path}/workflow.7z';
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
      final path = '${directory.path}/percentage.7z';
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
  Map<String, Object?> compactionSnapshot({int count = 16}) => {
    'serviceId': service,
    'model': 'gpt-6.1-sol',
    'messages': <Object?>[],
    'history': [
      for (var i = 0; i < count; i++)
        {'role': i.isEven ? 'user' : 'assistant', 'content': 'History $i'},
    ],
  };

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

  test('manual compaction reports empty model output as unchanged', () async {
    final root = await create('Empty summary');
    root.assistant.restoreWorkspaceConversation(compactionSnapshot());
    summary = ' ';
    expect(
      await root.assistant.compactContext(),
      AiContextCompactionOutcome.unchanged,
    );
    expect(
      root.assistant.snapshotWorkspaceConversation()['history'],
      hasLength(16),
    );
  });

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
    expect(snapshot['messages'], hasLength(16));
    expect(snapshot['history'], hasLength(8));
    expect(snapshot['summary'], 'Retained goals and unresolved work.');
    expect(
      root.assistant.messages.last.processEvents.last.action!.name,
      'compact_context',
    );
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
}
