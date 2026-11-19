import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late AssistantTestScope scope;
  late AgentStorage storage;
  late AiWorkspaceProvider workspaces;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late List<Map<String, dynamic>> requests;
  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    storage = AgentStorage(path: ':memory:');
    await storage.ready;
    scope = await createAssistantTestScope(
      storage: storage,
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
                'message': {'content': 'Done'},
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
      models: ['test'],
      apiKey: 'key',
    );
    // These fixtures isolate workflow/messaging requests. Automatic memory
    // extraction has its own integration suite and makes additional API calls.
    scope.provider.autoSaveMemory = false;
    workspaces = AiWorkspaceProvider(scope.provider);
    workspaces.addListener(() {
      for (final session in workspaces.sessions) {
        session.assistant.autoSaveMemory = false;
      }
    });
    await workspaces.initialized;
  });
  test('canvas child to root connection adopts target subtree and survives undo and restore', () async {
    final root = await workspaces.create(
      title: 'Root',
      task: 'Plan',
      startImmediately: false,
    );
    final child = await workspaces.create(
      title: 'Child',
      task: 'Work',
      parentId: root.id,
      startImmediately: false,
    );
    final target = await workspaces.create(
      title: 'Target',
      task: 'Plan',
      startImmediately: false,
    );
    final descendant = await workspaces.create(
      title: 'Descendant',
      task: 'Work',
      parentId: target.id,
      startImmediately: false,
    );
    final model = target.model;
    final permissions = target.assistant.permissions;
    final before = workspaces.captureTopologyEdit();
    final edge = workspaces.connectCanvasTasks(child.id, target.id);
    expect(edge.isHierarchy, isTrue);
    expect(target.parentId, child.id);
    expect(target.kind, AiWorkspaceKind.permanent);
    expect(descendant.parentId, target.id);
    expect(
      workspaces.sessions
          .where((agent) => agent.kind == AiWorkspaceKind.primary)
          .map((agent) => agent.id),
      [root.id],
    );
    expect(target.model, model);
    expect(target.assistant.permissions, same(permissions));
    expect(workspaces.connectCanvasTasks(child.id, target.id).id, edge.id);
    final after = workspaces.captureTopologyEdit();
    await workspaces.restoreTopologyEdit(before);
    expect(target.kind, AiWorkspaceKind.primary);
    expect(target.parentId, isNull);
    await workspaces.restoreTopologyEdit(after);
    expect(target.parentId, child.id);
    expect(target.kind, AiWorkspaceKind.permanent);
    await workspaces.flush();
    workspaces.dispose();
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.find(target.id)!.parentId, child.id);
    expect(workspaces.find(target.id)!.kind, AiWorkspaceKind.permanent);
    expect(workspaces.find(descendant.id)!.parentId, target.id);
  });

  test(
    'same-tree links preserve leadership and cross-tree links join workflows',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'Plan',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: root.id,
        startImmediately: false,
      );
      final descendant = await workspaces.create(
        title: 'Descendant',
        task: 'Work',
        parentId: child.id,
        startImmediately: false,
      );
      final other = await workspaces.create(
        title: 'Other',
        task: 'Plan',
        startImmediately: false,
      );
      workspaces.connectCanvasTasks(descendant.id, root.id);
      expect(root.parentId, isNull);
      expect(root.kind, AiWorkspaceKind.primary);
      workspaces.connectTasks(child.id, other.id);
      expect(other.kind, AiWorkspaceKind.permanent);
      workspaces.connectCanvasTasks(child.id, other.id);
      expect(other.parentId, child.id);
      expect(other.kind, AiWorkspaceKind.permanent);
      expect(
        workspaces.connections.where(
          (edge) => {edge.fromId, edge.toId}.containsAll([child.id, other.id]),
        ),
        hasLength(1),
      );
      expect(
        () => workspaces.connectCanvasTasks(child.id, child.id),
        throwsStateError,
      );
    },
  );

  for (final batch in [false, true]) {
    test(
      'deletion reconnects descendants to nearest retained ancestor batch=$batch',
      () async {
        final root = await workspaces.create(
          title: 'Root',
          task: 'Plan',
          startImmediately: false,
        );
        final middle = await workspaces.create(
          title: 'Middle',
          task: 'Work',
          parentId: root.id,
          startImmediately: false,
        );
        final child = await workspaces.create(
          title: 'Child',
          task: 'Work',
          parentId: middle.id,
          startImmediately: false,
        );
        final leaf = await workspaces.create(
          title: 'Leaf',
          task: 'Work',
          parentId: child.id,
          startImmediately: false,
        );
        final peer = await workspaces.create(
          title: 'Peer',
          task: 'Work',
          parentId: root.id,
          startImmediately: false,
        );
        workspaces.connectTasks(leaf.id, peer.id);
        final permissions = leaf.assistant.permissions;
        final before = workspaces.captureTopologyEdit();
        workspaces.removeMany(
          batch ? [child.id, middle.id, middle.id] : [middle.id],
        );
        expect(workspaces.find(middle.id), isNull);
        expect(leaf.parentId, batch ? root.id : child.id);
        if (!batch) expect(child.parentId, root.id);
        expect(leaf.assistant.permissions, same(permissions));
        expect(workspaces.isConnected(leaf.id, peer.id), isTrue);
        expect(
          workspaces.isConnected(root.id, batch ? leaf.id : child.id),
          isTrue,
        );
        expect(
          workspaces.sessions
              .where((agent) => agent.kind == AiWorkspaceKind.primary)
              .map((agent) => agent.id),
          [root.id],
        );
        expect(
          workspaces.recycledAgents.map((entry) => entry.id),
          unorderedEquals(batch ? [middle.id, child.id] : [middle.id]),
        );
        final after = workspaces.captureTopologyEdit();
        await workspaces.restoreTopologyEdit(before, previous: after);
        expect(middle.parentId, root.id);
        expect(child.parentId, middle.id);
        expect(leaf.parentId, child.id);
        await workspaces.restoreTopologyEdit(after, previous: before);
        expect(leaf.parentId, batch ? root.id : child.id);
        await workspaces.flush();
        workspaces.dispose();
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        expect(workspaces.find(leaf.id)!.parentId, batch ? root.id : child.id);
        await workspaces.restoreRecycledAgent(middle.id);
        expect(workspaces.find(middle.id)!.parentId, root.id);
        expect(workspaces.find(leaf.id)!.parentId, batch ? root.id : child.id);
      },
    );
  }

  test('copy titles number existing tasks and never stack suffixes', () async {
    await workspaces.createPrimary(title: '配置', task: 'one');
    expect(workspaces.nextCopyTitle('配置'), '配置 (2)');
    await workspaces.createPrimary(title: '配置 (2)', task: 'two');
    expect(workspaces.nextCopyTitle('配置'), '配置 (3)');
    expect(workspaces.nextCopyTitle('配置 (2)'), '配置 (3)');
    await workspaces.createPrimary(title: '配置 (3)', task: 'three');
    expect(workspaces.nextCopyTitle('配置 (2)'), '配置 (4)');
    expect(workspaces.nextCopyTitle('配置 (2) (3)'), '配置 (4)');
    expect(workspaces.nextCopyTitle('项目 (2026) 计划'), '项目 (2026) 计划 (2)');
    final longName = '长' * 200;
    expect(workspaces.nextCopyTitle(longName), longName);
  });

  tearDown(() async {
    await workspaces.flush().catchError((_) {});
    workspaces.dispose();
    await storage.close();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });
  Future<AiAgentWorkspace> task(
    String name, {
    String? parent,
    AiWorkspaceKind? kind,
  }) => workspaces.create(
    title: name,
    task: 'Task $name',
    parentId: parent,
    kind: kind,
    startImmediately: false,
  );

  void expectSingleMainPerWorkflow() {
    final remaining = workspaces.sessions
        .where((agent) => !agent.closed)
        .map((agent) => agent.id)
        .toSet();
    while (remaining.isNotEmpty) {
      final members = <String>{};
      final pending = [remaining.first];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!members.add(id)) continue;
        remaining.remove(id);
        pending.addAll(workspaces.neighborsOf(id).map((agent) => agent.id));
      }
      final leaders = members.where(
        (id) => workspaces.find(id)!.kind == AiWorkspaceKind.primary,
      );
      expect(leaders, hasLength(1));
      final root = leaders.single;
      for (final id in members) {
        final path = <String>{};
        var current = workspaces.find(id)!;
        while (current.parentId != null) {
          expect(path.add(current.id), isTrue);
          expect(members, contains(current.parentId));
          current = workspaces.find(current.parentId)!;
        }
        expect(current.id, root);
      }
    }
  }

  for (final canvas in [false, true]) {
    for (final sourceChild in [false, true]) {
      for (final targetChild in [false, true]) {
        test(
          'connection joins one workflow canvas=$canvas sourceChild=$sourceChild targetChild=$targetChild',
          () async {
            final sourceRoot = await task('Source root');
            final targetRoot = await task('Target root');
            final source = sourceChild
                ? await task('Source child', parent: sourceRoot.id)
                : sourceRoot;
            final target = targetChild
                ? await task('Target child', parent: targetRoot.id)
                : targetRoot;
            await task('Target branch', parent: targetRoot.id);
            await task('Target descendant', parent: target.id);
            final before = workspaces.captureTopologyEdit();
            final originalEdges = workspaces.connections
                .map((edge) => ({edge.fromId, edge.toId}))
                .toList();
            final edge = canvas
                ? workspaces.connectCanvasTasks(source.id, target.id)
                : workspaces.connectTasks(source.id, target.id);
            expect(edge.isHierarchy, isTrue);
            expect(target.parentId, source.id);
            expect(workspaces.primaries, [sourceRoot]);
            expect(workspaces.connections, hasLength(originalEdges.length + 1));
            for (final endpoints in originalEdges) {
              expect(
                workspaces.isConnected(endpoints.first, endpoints.last),
                isTrue,
              );
            }
            expectSingleMainPerWorkflow();
            final after = workspaces.captureTopologyEdit();
            await workspaces.restoreTopologyEdit(before, previous: after);
            expect(workspaces.primaries, [sourceRoot, targetRoot]);
            expectSingleMainPerWorkflow();
            await workspaces.restoreTopologyEdit(after, previous: before);
            expect(workspaces.primaries, [sourceRoot]);
            expectSingleMainPerWorkflow();
            expect(workspaces.connectTasks(target.id, source.id).id, edge.id);
            await workspaces.flush();
            workspaces.dispose();
            workspaces = AiWorkspaceProvider(scope.provider);
            await workspaces.initialized;
            expect(workspaces.primaries.map((agent) => agent.id), [
              sourceRoot.id,
            ]);
            expectSingleMainPerWorkflow();
          },
        );
      }
    }
  }

  test(
    'import repairs connected roots through child endpoints before persistence',
    () async {
      final root = await task('Root');
      final first = await task('First', parent: root.id);
      final other = await task('Other');
      final second = await task('Second', parent: other.id);
      final packet = workspaces.exportData();
      packet['connections'] = [
        {'fromId': first.id, 'toId': second.id},
      ];
      final mapping = await workspaces.importData(packet);
      expect(workspaces.find(mapping[second.id])!.parentId, mapping[first.id]);
      expect(workspaces.find(mapping[other.id])!.parentId, mapping[second.id]);
      expectSingleMainPerWorkflow();
      final copies = await workspaces.pasteCards(
        workspaces.copyCards(mapping.values),
        titleForCopy: (title) => title,
      );
      expect(
        copies.where((agent) => agent.kind == AiWorkspaceKind.primary),
        hasLength(1),
      );
      expectSingleMainPerWorkflow();
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expectSingleMainPerWorkflow();
    },
  );
  AiTaskConnection connectConfirmed(String from, String to) =>
      workspaces.connectTasks(from, to);

  test(
    'wait_agents rejects results after communication is disconnected',
    () async {
      final caller = await task('Caller');
      final target = await task('Target');
      final connection = connectConfirmed(caller.id, target.id);
      final pending = caller.assistant.workspaceToolHandler!('wait_agents', {
        'agent_ids': [target.id],
        'wait_ms': 5000,
      });
      final assertion = expectLater(pending, throwsStateError);
      workspaces.disconnectConnection(connection.id);
      await assertion;
    },
  );

  test('wait_agents rejects results after its caller is removed', () async {
    final caller = await task('Caller');
    final target = await task('Target');
    connectConfirmed(caller.id, target.id);
    final pending = caller.assistant.workspaceToolHandler!('wait_agents', {
      'agent_ids': [target.id],
      'wait_ms': 5000,
    });
    final assertion = expectLater(pending, throwsStateError);
    workspaces.remove(caller.id);
    await assertion;
  });

  test('wait_agents still reports a removed target as closed', () async {
    final caller = await task('Caller');
    final target = await task('Target');
    connectConfirmed(caller.id, target.id);
    final pending = caller.assistant.workspaceToolHandler!('wait_agents', {
      'agent_ids': [target.id],
      'wait_ms': 5000,
    });
    workspaces.remove(target.id);
    expect((await pending)['agents'], [
      {'agent_id': target.id, 'status': 'closed'},
    ]);
  });

  Future<void> settle() async {
    for (var i = 0; i < 200 && workspaces.sessions.any((s) => s.busy); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(workspaces.sessions.any((s) => s.busy), isFalse);
  }

  Future<void> reload({Map<String, dynamic>? replacement}) async {
    if (workspaces.persistenceError == null) await workspaces.flush();
    workspaces.dispose();
    if (replacement != null) {
      await storage.saveWorkflow(replacement);
    }
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  }

  test(
    'sibling links preserve hierarchy and roles and allow supplemental cycles',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      final edge = workspaces.connectTasks(a.id, b.id);
      expect(edge.isHierarchy, isFalse);
      expect(a.parentId, root.id);
      expect(b.parentId, root.id);
      expect(a.kind, AiWorkspaceKind.permanent);
      expect(b.kind, AiWorkspaceKind.permanent);
      expect(
        workspaces.connections.map((c) => c.id),
        containsAll([a.id, b.id, edge.id]),
      );
      expect(
        workspaces.neighborsOf(a.id).map((s) => s.id),
        containsAll([root.id, b.id]),
      );
      expect(workspaces.isConnected(b.id, a.id), isTrue);
      expect(workspaces.isConnected(a.id, a.id), isFalse);
      final other = await task('Other root', kind: AiWorkspaceKind.primary);
      connectConfirmed(a.id, other.id);
      workspaces.connectTasks(b.id, other.id);
      expect(workspaces.connections, hasLength(5));
      expect(other.parentId, a.id);
      expect(other.kind, AiWorkspaceKind.permanent);
    },
  );
  test('reverse duplicate and structural pairs reuse existing edge', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final a = await task('A', parent: root.id);
    final b = await task('B', parent: root.id);
    final edge = workspaces.connectTasks(a.id, b.id);
    expect(workspaces.connectTasks(b.id, a.id), same(edge));
    expect(workspaces.connectTasks(a.id, b.id).id, edge.id);
    final structural = workspaces.connectTasks(a.id, root.id);
    expect(structural.id, a.id);
    expect(structural.isHierarchy, isTrue);
    expect(workspaces.connections, hasLength(3));
    workspaces.disconnectConnection(edge.id);
    expect(workspaces.connectTasks(b.id, a.id).id, edge.id);
  });
  test('self unknown and closed endpoints are rejected', () async {
    final a = await task('A', kind: AiWorkspaceKind.primary);
    final temp = await task(
      'Temp',
      parent: a.id,
      kind: AiWorkspaceKind.permanent,
    );
    final b = await task('B');
    b.closed = true;
    for (final pair in [
      [a.id, a.id],
      [a.id, 'unknown'],
      [a.id, b.id],
    ]) {
      expect(() => workspaces.connectTasks(pair[0], pair[1]), throwsStateError);
    }
    expect(workspaces.connections.single.toId, temp.id);
  });
  test('disconnect preserves one main through remaining peer links', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final a = await task('A', parent: root.id);
    final b = await task('B', parent: root.id);
    final peer = workspaces.connectTasks(a.id, b.id);
    workspaces.disconnectConnection(peer.id);
    expect(a.parentId, root.id);
    expect(b.parentId, root.id);
    expect(workspaces.connections.map((c) => c.id), [a.id, b.id]);
    workspaces.connectTasks(a.id, b.id);
    workspaces.disconnectConnection(a.id);
    expect(a.parentId, b.id);
    expect(a.kind, AiWorkspaceKind.permanent);
    expect(b.parentId, root.id);
    expect(workspaces.isConnected(a.id, b.id), isTrue);
    workspaces.disconnectConnection('missing');
    expect(workspaces.sessions, hasLength(3));
    expect(workspaces.isConnected(a.id, b.id), isTrue);
  });
  test('batch cut previews roles without mutation then promotes each split tree once', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final a = await task('A', parent: root.id);
    final b = await task('B', parent: root.id);
    final nested = await task('Nested', parent: a.id);
    final unrelated = await task('Unrelated root');
    final peer = workspaces.connectTasks(a.id, b.id);
    final selected = [a.id, b.id, peer.id];
    expect(workspaces.disconnectionRoleChanges(selected), {
      a.id: AiWorkspaceKind.primary,
      b.id: AiWorkspaceKind.primary,
    });
    expect(a.parentId, root.id);
    expect(b.kind, AiWorkspaceKind.permanent);
    var notifications = 0;
    workspaces.addListener(() => notifications++);
    workspaces.disconnectConnections(selected);
    expect(notifications, 1);
    expect(a.parentId, isNull);
    expect(a.kind, AiWorkspaceKind.primary);
    expect(b.parentId, isNull);
    expect(b.kind, AiWorkspaceKind.primary);
    expect(nested.parentId, a.id);
    expect(nested.kind, AiWorkspaceKind.permanent);
    expect(unrelated.kind, AiWorkspaceKind.primary);
    expect(workspaces.connections.single.id, nested.id);
    await reload();
    expect(workspaces.find(a.id)!.kind, AiWorkspaceKind.primary);
    expect(workspaces.find(b.id)!.kind, AiWorkspaceKind.primary);
  });
  test(
    'cut with an alternate path reroutes delegation without adding edges',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: a.id);
      workspaces.connectTasks(root.id, b.id);
      expect(workspaces.disconnectionRoleChanges([a.id]), isEmpty);
      workspaces.disconnectConnections([a.id]);
      expect(root.kind, AiWorkspaceKind.primary);
      expect(a.parentId, b.id);
      expect(b.parentId, root.id);
      expect(workspaces.isConnected(root.id, a.id), isFalse);
      expect(workspaces.isConnected(root.id, b.id), isTrue);
      expect(workspaces.isConnected(a.id, b.id), isTrue);
      expect(workspaces.connections, hasLength(2));
    },
  );
  test(
    'peer tools list and message both ways but reject indirect access',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      final isolated = await task('Isolated', kind: AiWorkspaceKind.primary);
      workspaces.connectTasks(a.id, b.id);
      for (final pair in [(a, b), (b, a)]) {
        final visible = await pair.$1.assistant.workspaceToolHandler!(
          'list_agents',
          {},
        );
        expect(
          (visible['agents'] as List).map((v) => (v as Map)['agent_id']),
          contains(pair.$2.id),
        );
        final delivered = await pair.$1.assistant.workspaceToolHandler!(
          'send_agent_message',
          {'agent_id': pair.$2.id, 'message': 'From ${pair.$1.id}'},
        );
        expect(delivered['delivered'], isTrue);
        await settle();
        expect(
          pair.$2.assistant.messages.first.toolArguments?['source_agent_id'],
          pair.$1.id,
        );
        await expectLater(
          pair.$1.assistant.workspaceToolHandler!('send_agent_message', {
            'agent_id': isolated.id,
            'message': 'Not connected',
          }),
          throwsStateError,
        );
      }
      expect(requests, hasLength(2));
      workspaces.disconnectConnection(
        workspaces.connections.singleWhere((c) => !c.isHierarchy).id,
      );
      final visible = await a.assistant.workspaceToolHandler!(
        'list_agents',
        {},
      );
      expect(
        (visible['agents'] as List).map((v) => (v as Map)['agent_id']),
        isNot(contains(b.id)),
      );
    },
  );
  test(
    'supplemental links roundtrip and missing connections is rejected',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      final edge = workspaces.connectTasks(a.id, b.id);
      await reload();
      expect(workspaces.persistenceError, isNull);
      expect(
        workspaces.connections.map((c) => c.id),
        containsAll([a.id, b.id, edge.id]),
      );
      expect(workspaces.isConnected(a.id, b.id), isTrue);
      await workspaces.flush();
      final incomplete = jsonDecode(
        (await storage.request('readWorkflow')) as String,
      ) as Map<String, dynamic>;
      incomplete.remove('connections');
      await reload(replacement: incomplete);
      expect(workspaces.persistenceError, isNotNull);
      expect(workspaces.sessions, isEmpty);
      expect(requests, isEmpty);
    },
  );
  test(
    'invalid saved connection lists are rejected before tasks restore',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B');
      await workspaces.flush();
      final saved = jsonDecode(
        (await storage.request('readWorkflow')) as String,
      ) as Map<String, dynamic>;
      for (final invalid in [
        null,
        'wrong-type',
        [
          {'fromId': a.id, 'toId': 'unknown'},
        ],
        [
          {'fromId': a.id, 'toId': a.id},
        ],
        [
          {'fromId': a.id, 'toId': b.id},
          {'fromId': b.id, 'toId': a.id},
        ],
      ]) {
        await reload(replacement: {...saved, 'connections': invalid});
        expect(workspaces.persistenceError, isA<FormatException>());
        expect(workspaces.sessions, isEmpty);
      }
    },
  );
  test('deleting task removes incident links without deleting peers', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final a = await task('A', parent: root.id);
    final b = await task('B', parent: root.id);
    final c = await task('C', parent: root.id);
    workspaces.connectTasks(a.id, b.id);
    workspaces.connectTasks(b.id, c.id);
    workspaces.remove(b.id);
    expect(workspaces.find(a.id), same(a));
    expect(workspaces.find(c.id), same(c));
    expect(workspaces.connections.every((edge) => edge.isHierarchy), isTrue);
    await reload();
    expect(workspaces.connections, hasLength(2));
    expect(workspaces.sessions, hasLength(3));
  });
  test(
    'root promotion prunes deleted endpoints and redundant hierarchy peers',
    () async {
      final outside = await task('Outside', kind: AiWorkspaceKind.primary);
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      workspaces.connectTasks(a.id, b.id);
      connectConfirmed(root.id, outside.id);
      final retained = workspaces.connectTasks(a.id, outside.id);
      final replacement = workspaces.rootReplacementsForDeletion([
        root.id,
      ])[root.id]!;
      workspaces.remove(root.id);
      expect(replacement.kind, AiWorkspaceKind.primary);
      expect(replacement.parentId, isNull);
      expect(workspaces.connections, hasLength(3));
      expect(
        workspaces.connections.any(
          (c) => c.fromId == root.id || c.toId == root.id,
        ),
        isFalse,
      );
      expect(
        workspaces.connections.where((c) => !c.isHierarchy).single.id,
        retained.id,
      );
      workspaces.disconnectConnection(a.id);
      expect(workspaces.isConnected(a.id, b.id), isFalse);
      await reload();
      expect(workspaces.connections, hasLength(2));
    },
  );
  test(
    'deletion preview preserves descendants of explicitly selected children',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final keep = await task('Keep', parent: root.id);
      final remove = await task('Remove', parent: root.id);
      final descendant = await task('Remove descendant', parent: remove.id);
      expect(
        workspaces.rootReplacementsForDeletion([
          root.id,
          remove.id,
          remove.id,
        ])[root.id],
        same(keep),
      );
      workspaces.removeMany([root.id, remove.id]);
      expect(workspaces.sessions, [keep, descendant]);
      expect(keep.kind, AiWorkspaceKind.primary);
      expect(descendant.kind, AiWorkspaceKind.permanent);
      expect(descendant.parentId, keep.id);
    },
  );
  test(
    'deleting adjacent children preserves branches under the retained ancestor',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final middle = await task('Middle', parent: root.id);
      final adjacent = await task('Adjacent', parent: middle.id);
      final first = await task('First', parent: middle.id);
      final second = await task('Second', parent: adjacent.id);
      final deeper = await task('Deeper', parent: second.id);
      final permissions = second.assistant.permissions;
      final messages = second.assistant.messages.toList();
      expect(
        workspaces.promotedRootsForDeletion([middle.id, adjacent.id]).keys,
        isEmpty,
      );
      workspaces.removeMany([adjacent.id, middle.id, middle.id]);
      expect(workspaces.find(root.id), same(root));
      expect(workspaces.find(middle.id), isNull);
      expect(workspaces.find(adjacent.id), isNull);
      for (final child in [first, second]) {
        expect(child.parentId, root.id);
        expect(child.kind, AiWorkspaceKind.permanent);
      }
      expect(deeper.parentId, second.id);
      expect(deeper.kind, AiWorkspaceKind.permanent);
      expect(second.assistant.permissions, same(permissions));
      expect(second.assistant.messages, orderedEquals(messages));
      await reload();
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.find(first.id)!.kind, AiWorkspaceKind.permanent);
      expect(workspaces.find(second.id)!.parentId, root.id);
      expect(workspaces.find(deeper.id)!.parentId, second.id);
    },
  );

  test('delete tool reports only selected child and reconnects its live descendants', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final middle = await task('Middle', parent: root.id);
    final leaf = await task('Leaf', parent: middle.id);
    final result = await root.assistant.workspaceToolHandler!('delete_agent', {
      'agent_id': middle.id,
    });
    expect(result['deleted_agent_ids'], [middle.id]);
    expect(result['promoted_agent_ids'], isEmpty);
    expect(workspaces.find(leaf.id), same(leaf));
    expect(leaf.kind, AiWorkspaceKind.permanent);
    expect(leaf.parentId, root.id);
  });

  test(
    'selected peer copies connect only copies and preserve original hierarchy',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      workspaces.connectTasks(a.id, b.id);
      final copies = await workspaces.pasteCards(
        workspaces.copyCards([a.id, b.id]),
        titleForCopy: (title) => title,
      );
      expect(workspaces.isConnected(copies[0].id, copies[1].id), isTrue);
      expect(copies[0].parentId, root.id);
      expect(copies[1].parentId, root.id);
      expect(workspaces.isConnected(copies[0].id, a.id), isFalse);
      final single = await workspaces.pasteCards(
        workspaces.copyCards([a.id]),
        titleForCopy: (title) => title,
      );
      expect(workspaces.isConnected(single.single.id, b.id), isFalse);
    },
  );
  test('explicit reparent coalesces peer edge without phantom link after disconnect', () async {
    final a = await task('A', kind: AiWorkspaceKind.primary);
    final b = await task('B');
    connectConfirmed(a.id, b.id);
    workspaces.reparent(b.id, a.id);
    expect(workspaces.connections.single.id, b.id);
    expect(workspaces.connections.single.isHierarchy, isTrue);
    workspaces.disconnectConnection(b.id);
    expect(workspaces.connections, isEmpty);
    expect(b.kind, AiWorkspaceKind.primary);
  });

  test('cross-tree connection merges roots and retains branch edges', () async {
    final rootA = await task('Root A', kind: AiWorkspaceKind.primary);
    final rootB = await task('Root B', kind: AiWorkspaceKind.primary);
    final childA = await task('Child A', parent: rootA.id);
    final childB = await task('Child B', parent: rootB.id);
    final before = workspaces.connections.map((e) => e.id).toList();
    final rootLink = workspaces.connectTasks(rootA.id, rootB.id);
    final childLink = workspaces.connectTasks(childA.id, childB.id);
    expect(rootA.parentId, isNull);
    expect(rootB.parentId, rootA.id);
    expect(rootA.kind, AiWorkspaceKind.primary);
    expect(rootB.kind, AiWorkspaceKind.permanent);
    expect(childA.parentId, rootA.id);
    expect(childB.parentId, rootB.id);
    expect(
      workspaces.connections.map((e) => e.id),
      unorderedEquals([...before, rootLink.id, childLink.id]),
    );
  });

  test(
    'child-to-child communication retains history ownership and all peer links',
    () async {
      final rootA = await task('Root A', kind: AiWorkspaceKind.primary);
      final rootB = await task('Root B', kind: AiWorkspaceKind.primary);
      final childA = await task('Child A', parent: rootA.id);
      final childB = await task('Child B', parent: rootB.id);
      final siblingB = await task('Sibling B', parent: rootB.id);
      final nested = await task('Nested B', parent: childB.id);
      final nestedSibling = await task('Nested sibling B', parent: childB.id);
      final innerPeer = workspaces.connectTasks(nested.id, nestedSibling.id);
      final boundaryPeer = workspaces.connectTasks(childB.id, siblingB.id);
      final boundaryDescendantPeer = workspaces.connectTasks(
        nested.id,
        rootB.id,
      );
      await childB.assistant.sendMessage('Existing target history');
      final assistant = childB.assistant;
      final permissions = assistant.permissions;
      final history = assistant.messages.map((m) => m.content).toList();
      final edge = workspaces.connectTasks(childA.id, childB.id);
      expect(edge.isHierarchy, isTrue);
      expect(rootA.kind, AiWorkspaceKind.primary);
      expect(rootA.parentId, isNull);
      expect(rootB.kind, AiWorkspaceKind.permanent);
      expect(rootB.parentId, childB.id);
      expect(childA.kind, AiWorkspaceKind.permanent);
      expect(childA.parentId, rootA.id);
      expect(childB.parentId, childA.id);
      expect(childB.kind, AiWorkspaceKind.permanent);
      expect(siblingB.parentId, rootB.id);
      expect(nested.parentId, childB.id);
      expect(nestedSibling.parentId, childB.id);
      expect(
        workspaces.connections.any((item) => item.id == innerPeer.id),
        isTrue,
      );
      expect(
        workspaces.connections.any((item) => item.id == boundaryPeer.id),
        isTrue,
      );
      expect(
        workspaces.connections.any(
          (item) => item.id == boundaryDescendantPeer.id,
        ),
        isTrue,
      );
      expect(workspaces.isConnected(childB.id, rootB.id), isTrue);
      expect(childB.assistant, same(assistant));
      expect(assistant.permissions, same(permissions));
      expect(assistant.messages.map((m) => m.content), history);
      expect(workspaces.primaries, [rootA]);
      expect(workspaces.connectTasks(childB.id, childA.id).id, edge.id);
      await reload();
      expect(workspaces.find(childB.id)!.parentId, childA.id);
      expect(workspaces.find(siblingB.id)!.parentId, rootB.id);
      expect(workspaces.find(nested.id)!.parentId, childB.id);
      expect(workspaces.primaries.map((task) => task.id), [rootA.id]);
      expect(workspaces.isConnected(nested.id, nestedSibling.id), isTrue);
      expect(workspaces.isConnected(childB.id, siblingB.id), isTrue);
    },
  );
  test(
    'reverse duplicate connection retains the first source group leader',
    () async {
      final rootA = await task('Root A', kind: AiWorkspaceKind.primary);
      final rootB = await task('Root B', kind: AiWorkspaceKind.primary);
      final childA = await task('Child A', parent: rootA.id);
      final childB = await task('Child B', parent: rootB.id);
      final edge = workspaces.connectTasks(childB.id, childA.id);
      expect(workspaces.connectTasks(childA.id, childB.id).id, edge.id);
      expect(workspaces.primaries, [rootB]);
      expect(rootA.parentId, childA.id);
      expect(rootB.parentId, isNull);
      expect(childA.parentId, childB.id);
      expect(childB.parentId, rootB.id);
    },
  );
  test(
    'cross-tree connection reverses the target path and retains its branches',
    () async {
      final source = await task('Source', kind: AiWorkspaceKind.primary);
      final oldRoot = await task('Old root', kind: AiWorkspaceKind.primary);
      final target = await task('Target', parent: oldRoot.id);
      final sibling = await task('Sibling', parent: oldRoot.id);
      workspaces.reparent(target.id, sibling.id);
      final graph = workspaces.connections
          .map((edge) => (edge.id, edge.fromId, edge.toId))
          .toList();
      expect(target.parentId, sibling.id);
      expect(source.parentId, isNull);
      expect(oldRoot.parentId, isNull);
      expect(
        workspaces.connections.map((edge) => (edge.id, edge.fromId, edge.toId)),
        graph,
      );
      connectConfirmed(source.id, target.id);
      expect(target.parentId, source.id);
      expect(sibling.parentId, target.id);
      expect(oldRoot.parentId, sibling.id);
      expect(workspaces.primaries, [source]);
    },
  );
  test('reparent moves only the selected subtree and reconnect joins its old group', () async {
    final a = await task('A', kind: AiWorkspaceKind.primary);
    final b = await task('B', kind: AiWorkspaceKind.primary);
    final c = await task('C', kind: AiWorkspaceKind.primary);
    workspaces.connectTasks(a.id, b.id);
    expect(b.parentId, a.id);
    expect(a.parentId, isNull);
    workspaces.reparent(b.id, c.id);
    expect(b.parentId, c.id);
    expect(c.parentId, isNull);
    expect(a.parentId, isNull);
    expect(c.parentId, isNull);
    expect(a.parentId, isNull);
    final edge = workspaces.connectTasks(b.id, a.id);
    expect(a.parentId, b.id);
    expect(workspaces.primaries, [c]);
    expect(workspaces.connections, hasLength(2));
    expect(workspaces.connectTasks(a.id, b.id).id, edge.id);
  });

  test('child creation without a parent is rejected', () async {
    await expectLater(
      task('Orphan', kind: AiWorkspaceKind.permanent),
      throwsStateError,
    );
    expect(workspaces.sessions, isEmpty);
  });

  test(
    'saved child without a parent is rejected instead of restored',
    () async {
      final root = await task('Root');
      await task('Child', parent: root.id);
      await workspaces.flush();
      final saved = jsonDecode(
        (await storage.request('readWorkflow')) as String,
      ) as Map<String, dynamic>;
      final child = (saved['sessions'] as List).cast<Map>().firstWhere(
        (record) => record['parentId'] == root.id,
      );
      child['parentId'] = null;
      await reload(replacement: saved);
      expect(workspaces.persistenceError, isNotNull);
      expect(workspaces.sessions, isEmpty);
    },
  );

  test('restores ten thousand saved agents in reverse parent order', () async {
    const count = 10000;
    await reload(
      replacement: {
        'version': 1,
        'connections': [],
        'sessions': [
          for (var index = count - 1; index >= 0; index--)
            {
              'id': '1000-$index',
              'parentId': index == 0 ? null : '1000-${index - 1}',
              'kind': index == 0 ? 'primary' : 'permanent',
              'title': 'Task $index',
              'task': 'Local fixture',
              'conversation': {
                'model': '',
                'serviceId': '',
                'messages': [],
                'history': [],
              },
            },
        ],
      },
    );
    expect(workspaces.persistenceError, isNull);
    expect(workspaces.sessions, hasLength(count));
    expect(workspaces.sessions.first.id, '1000-0');
    expect(workspaces.sessions.last.parentId, '1000-${count - 2}');
    expect(workspaces.primaries.single.id, '1000-0');
  });

  for (final (parent, reason) in [
    ('1000-1', 'Agent topology contains a cycle'),
    ('1000-99', 'Invalid saved parent agent'),
  ]) {
    test('rejects saved parent $parent when restoring a chain', () async {
      await reload(
        replacement: {
          'version': 1,
          'connections': [],
          'sessions': [
            for (final (id, parentId) in [
              ('1000-1', '1000-0'),
              ('1000-0', parent),
            ])
              {
                'id': id,
                'parentId': parentId,
                'kind': 'permanent',
                'title': 'Task $id',
                'task': 'Local fixture',
                'conversation': {
                  'model': '',
                  'serviceId': '',
                  'messages': [],
                  'history': [],
                },
              },
          ],
        },
      );
      expect(
        workspaces.persistenceError,
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          reason,
        ),
      );
      expect(workspaces.sessions, isEmpty);
    });
  }

  test(
    'stored cross-tree links restore and group-copy with one main per workflow',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B', kind: AiWorkspaceKind.primary);
      await workspaces.flush();
      final saved = jsonDecode(
        (await storage.request('readWorkflow')) as String,
      ) as Map<String, dynamic>;
      saved['connections'] = [
        {'fromId': a.id, 'toId': b.id},
      ];
      await reload(replacement: saved);
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.primaries.map((s) => s.id), [a.id]);
      expect(workspaces.find(a.id)!.parentId, isNull);
      expect(workspaces.find(b.id)!.parentId, a.id);
      expect(workspaces.connections.single.isHierarchy, isTrue);
      expect(
        workspaces.connectTasks(a.id, b.id).id,
        workspaces.connections.single.id,
      );
      final copies = await workspaces.pasteCards(
        workspaces.copyCards([a.id, b.id]),
        titleForCopy: (name) => name,
      );
      expect(
        copies.where((copy) => copy.kind == AiWorkspaceKind.primary),
        hasLength(1),
      );
      expect(workspaces.isConnected(copies[0].id, copies[1].id), isTrue);
      workspaces.connectTasks(a.id, b.id);
      expect(workspaces.find(b.id)!.parentId, a.id);
      expect(
        workspaces.connections.where((e) => e.fromId == a.id && e.toId == b.id),
        hasLength(1),
      );
    },
  );

  test(
    'explicit promotion cuts boundary links and preserves internal state',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final branch = await task('Branch', parent: root.id);
      final left = await task('Left', parent: branch.id);
      final right = await task('Right', parent: branch.id);
      final outside = await task('Outside', parent: root.id);
      final internal = workspaces.connectTasks(left.id, right.id);
      final cutFirst = workspaces.connectTasks(branch.id, outside.id);
      final cutSecond = workspaces.connectTasks(right.id, root.id);
      await branch.assistant.sendMessage('Keep conversation');
      final assistant = branch.assistant;
      final permissions = assistant.permissions;
      final messages = assistant.messages
          .map((message) => message.content)
          .toList();
      var notifications = 0;
      workspaces.addListener(() {
        notifications++;
        expect(branch.kind, AiWorkspaceKind.primary);
        expect(workspaces.isConnected(branch.id, outside.id), isFalse);
        expect(workspaces.isConnected(right.id, root.id), isFalse);
      });
      workspaces.promoteToRoot(branch.id);
      expect(notifications, 1);
      expect(branch.parentId, isNull);
      expect(branch.kind, AiWorkspaceKind.primary);
      expect(left.parentId, branch.id);
      expect(right.parentId, branch.id);
      expect(left.kind, AiWorkspaceKind.permanent);
      expect(right.kind, AiWorkspaceKind.permanent);
      expect(outside.parentId, root.id);
      expect(root.kind, AiWorkspaceKind.primary);
      expect(branch.assistant, same(assistant));
      expect(assistant.permissions, same(permissions));
      expect(assistant.messages.map((message) => message.content), messages);
      expect(
        workspaces.connections.map((edge) => edge.id),
        containsAll([left.id, right.id, outside.id, internal.id]),
      );
      expect(
        workspaces.connections.any(
          (edge) => edge.id == cutFirst.id || edge.id == cutSecond.id,
        ),
        isFalse,
      );
      await reload();
      expect(workspaces.find(branch.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(branch.id)!.parentId, isNull);
      expect(workspaces.connections, hasLength(4));
      expect(workspaces.isConnected(left.id, right.id), isTrue);
      expect(workspaces.isConnected(right.id, root.id), isFalse);
    },
  );

  test(
    'promotion after a delegation cut splits the current management subtree',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final branch = await task('Branch', parent: root.id);
      final child = await task('Child', parent: branch.id);
      workspaces.connectTasks(child.id, root.id);
      workspaces.disconnectConnection(branch.id);
      expect(branch.parentId, child.id);
      expect(branch.kind, AiWorkspaceKind.permanent);
      expect(workspaces.isConnected(child.id, root.id), isTrue);
      workspaces.promoteToRoot(branch.id);
      expect(branch.kind, AiWorkspaceKind.primary);
      expect(workspaces.isConnected(branch.id, child.id), isFalse);
      expect(workspaces.isConnected(child.id, root.id), isTrue);
      expect(workspaces.connections, hasLength(1));
    },
  );

  test(
    'promotion rejects invalid endpoints and repeated promotion is a no-op',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final temp = await task(
        'Temporary',
        parent: root.id,
        kind: AiWorkspaceKind.permanent,
      );
      final closed = await task('Closed');
      closed.closed = true;
      workspaces.promoteToRoot(temp.id);
      expect(temp.kind, AiWorkspaceKind.primary);
      for (final id in ['unknown', closed.id]) {
        expect(() => workspaces.promoteToRoot(id), throwsStateError);
      }
      expect(root.kind, AiWorkspaceKind.primary);
      expect(root.parentId, isNull);
      var changes = 0;
      workspaces.addListener(() => changes++);
      workspaces.promoteToRoot(root.id);
      expect(changes, 0);
    },
  );
  test('restoring a deleted main with a surviving peer edge does not create two mains', () async {
    final root = await task('Root');
    final child = await task('Child', parent: root.id);
    final nested = await task('Nested', parent: child.id);
    workspaces.connectTasks(root.id, nested.id);
    workspaces.remove(root.id);
    expect(workspaces.primaries, [child]);
    await workspaces.restoreRecycledAgent(root.id);
    expect(workspaces.primaries, [child]);
    expect(workspaces.find(root.id)!.parentId, nested.id);
    expect(workspaces.isConnected(root.id, nested.id), isTrue);
    expectSingleMainPerWorkflow();
    await reload();
    expectSingleMainPerWorkflow();
  });

  test('startup repairs the screenshot topology through child endpoints without losing edges', () async {
    final root = await task('Original main');
    final first = await task('First child', parent: root.id);
    final second = await task('Second child', parent: root.id);
    final other = await task('Copied main');
    final endpoint = await task('Copied child', parent: other.id);
    final saved = workspaces.exportData();
    saved['connections'] = [
      {'fromId': second.id, 'toId': endpoint.id},
    ];
    await reload(replacement: saved);
    expect(workspaces.persistenceError, isNull);
    expect(workspaces.primaries.map((agent) => agent.id), [root.id]);
    expect(workspaces.find(other.id)!.parentId, endpoint.id);
    expect(workspaces.find(endpoint.id)!.parentId, second.id);
    expect(workspaces.find(first.id)!.parentId, root.id);
    expect(workspaces.connections, hasLength(4));
    expectSingleMainPerWorkflow();
    await reload();
    expectSingleMainPerWorkflow();
  });

  test('mixed deletion preview matches role changes after root replacement and cuts', () async {
    final root = await task('Root', kind: AiWorkspaceKind.primary);
    final a = await task('A', parent: root.id);
    final b = await task('B', parent: root.id);
    final replacement = workspaces.replacementRootFor(root.id)!;
    final detached = replacement.id == a.id ? b : a;
    final preview = workspaces.disconnectionRoleChanges(
      [detached.id],
      deletingTaskIds: [root.id],
    );
    expect(preview[detached.id], AiWorkspaceKind.primary);
    expect(preview[replacement.id], isNull);
    expect(root.kind, AiWorkspaceKind.primary);
    expect(detached.parentId, root.id);
    workspaces.removeMany([root.id]);
    workspaces.disconnectConnections([detached.id]);
    for (final entry in preview.entries) {
      expect(workspaces.find(entry.key)!.kind, entry.value);
    }
    expect(workspaces.connections, isEmpty);
  });
}
