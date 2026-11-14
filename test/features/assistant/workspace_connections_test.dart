import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
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
  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    scope = await createAssistantTestScope(
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
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  });
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

  tearDown(() {
    workspaces.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });
  Future<AiAgentWorkspace> task(
    String name, {
    String? parent,
    AiWorkspaceKind kind = AiWorkspaceKind.permanent,
  }) => workspaces.create(
    title: name,
    task: 'Task $name',
    parentId: parent,
    kind: kind,
    startImmediately: false,
  );
  AiTaskConnection connectConfirmed(String from, String to) =>
      workspaces.connectTasks(
        from,
        to,
        confirmedMerge: workspaces.connectionMergeFor(from, to),
      );

  Future<void> settle() async {
    for (var i = 0; i < 200 && workspaces.sessions.any((s) => s.busy); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(workspaces.sessions.any((s) => s.busy), isFalse);
  }

  Future<void> reload({Map<String, dynamic>? replacement}) async {
    await workspaces.flush();
    workspaces.dispose();
    if (replacement != null) {
      scope.preferences.setValue(
        AiWorkspaceProvider.storageKey,
        jsonEncode(replacement),
      );
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
  test(
    'disconnect preserves one root through alternate links and reroutes ownership',
    () async {
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
    },
  );
  test(
    'batch cut previews roles without mutation then promotes each split tree once',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final a = await task('A', parent: root.id);
      final b = await task('B', parent: root.id);
      final nested = await task('Nested', parent: a.id);
      final unrelated = await task('Unrelated orphan');
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
      expect(unrelated.kind, AiWorkspaceKind.permanent);
      expect(workspaces.connections.single.id, nested.id);
      await reload();
      expect(workspaces.find(a.id)!.kind, AiWorkspaceKind.primary);
      expect(workspaces.find(b.id)!.kind, AiWorkspaceKind.primary);
    },
  );
  test(
    'cut with an alternate path preserves root and all unselected edges',
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
    'supplemental links roundtrip and legacy topology needs no connections field',
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
      final legacy =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map<String, dynamic>;
      legacy.remove('connections');
      await reload(replacement: legacy);
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.connections.map((c) => c.id), [a.id, b.id]);
      expect(requests, isEmpty);
    },
  );
  test(
    'invalid saved connection lists are rejected before tasks restore',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B');
      await workspaces.flush();
      final saved =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map<String, dynamic>;
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
    'deletion preview excludes explicitly selected child subtrees',
    () async {
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final keep = await task('Keep', parent: root.id);
      final remove = await task('Remove', parent: root.id);
      await task('Remove descendant', parent: remove.id);
      expect(
        workspaces.rootReplacementsForDeletion([
          root.id,
          remove.id,
          remove.id,
        ])[root.id],
        same(keep),
      );
      workspaces.removeMany([root.id, remove.id]);
      expect(workspaces.sessions, [keep]);
      expect(keep.kind, AiWorkspaceKind.primary);
    },
  );
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
  test(
    'explicit reparent coalesces peer edge without phantom link after disconnect',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B');
      connectConfirmed(a.id, b.id);
      workspaces.reparent(b.id, a.id);
      expect(workspaces.connections.single.id, b.id);
      expect(workspaces.connections.single.isHierarchy, isTrue);
      workspaces.disconnectConnection(b.id);
      expect(workspaces.connections, isEmpty);
      expect(b.kind, AiWorkspaceKind.primary);
    },
  );

  test(
    'cross-tree endpoints require explicit approval before any hierarchy mutation',
    () async {
      final rootA = await task('Root A', kind: AiWorkspaceKind.primary);
      final rootB = await task('Root B', kind: AiWorkspaceKind.primary);
      final childA = await task('Child A', parent: rootA.id);
      final childB = await task('Child B', parent: rootB.id);
      final before = workspaces.connections.map((e) => e.id).toList();
      expect(
        () => workspaces.connectTasks(rootA.id, rootB.id),
        throwsStateError,
      );
      expect(
        () => workspaces.connectTasks(childA.id, childB.id),
        throwsStateError,
      );
      expect(rootA.parentId, isNull);
      expect(rootB.parentId, isNull);
      expect(rootA.kind, AiWorkspaceKind.primary);
      expect(rootB.kind, AiWorkspaceKind.primary);
      expect(childA.parentId, rootA.id);
      expect(childB.parentId, rootB.id);
      expect(workspaces.connections.map((e) => e.id), before);
      expect(workspaces.connectionMergeFor(rootA.id, childA.id), isNull);
    },
  );

  test(
    'confirmed child-to-child join moves only target branch with history and internal peers',
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
      final plan = workspaces.connectionMergeFor(childA.id, childB.id)!;
      expect(plan.sourceRootId, rootA.id);
      expect(plan.targetRootId, rootB.id);
      expect(plan.rootId, childB.id);
      expect(plan.parentId, childA.id);
      expect(plan.changesRole, isFalse);
      final edge = workspaces.connectTasks(
        childA.id,
        childB.id,
        confirmedMerge: plan,
      );
      expect(edge.isHierarchy, isTrue);
      expect(rootA.kind, AiWorkspaceKind.primary);
      expect(rootA.parentId, isNull);
      expect(rootB.kind, AiWorkspaceKind.primary);
      expect(rootB.parentId, isNull);
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
        isFalse,
      );
      expect(
        workspaces.connections.any(
          (item) => item.id == boundaryDescendantPeer.id,
        ),
        isFalse,
      );
      expect(workspaces.isConnected(childB.id, rootB.id), isFalse);
      expect(childB.assistant, same(assistant));
      expect(assistant.permissions, same(permissions));
      expect(assistant.messages.map((m) => m.content), history);
      expect(workspaces.primaries, [rootA, rootB]);
      expect(workspaces.connectTasks(childB.id, childA.id).id, edge.id);
      expect(workspaces.connectionMergeFor(childA.id, childB.id), isNull);
      await reload();
      expect(workspaces.find(childB.id)!.parentId, childA.id);
      expect(workspaces.find(siblingB.id)!.parentId, rootB.id);
      expect(workspaces.find(nested.id)!.parentId, childB.id);
      expect(workspaces.primaries.map((task) => task.id), [rootA.id, rootB.id]);
      expect(workspaces.isConnected(nested.id, nestedSibling.id), isTrue);
      expect(workspaces.isConnected(childB.id, siblingB.id), isFalse);
    },
  );
  test(
    'reversing drag direction moves the other target branch and retains both roots',
    () async {
      final rootA = await task('Root A', kind: AiWorkspaceKind.primary);
      final rootB = await task('Root B', kind: AiWorkspaceKind.primary);
      final childA = await task('Child A', parent: rootA.id);
      final childB = await task('Child B', parent: rootB.id);
      final plan = workspaces.connectionMergeFor(childB.id, childA.id)!;
      expect(plan.rootId, childA.id);
      expect(plan.parentId, childB.id);
      workspaces.connectTasks(childB.id, childA.id, confirmedMerge: plan);
      expect(workspaces.primaries, [rootA, rootB]);
      expect(rootA.parentId, isNull);
      expect(rootB.parentId, isNull);
      expect(childA.parentId, childB.id);
      expect(childB.parentId, rootB.id);
    },
  );
  test(
    'target parent change inside its old tree invalidates branch move approval',
    () async {
      final source = await task('Source', kind: AiWorkspaceKind.primary);
      final oldRoot = await task('Old root', kind: AiWorkspaceKind.primary);
      final target = await task('Target', parent: oldRoot.id);
      final sibling = await task('Sibling', parent: oldRoot.id);
      final approval = workspaces.connectionMergeFor(source.id, target.id)!;
      workspaces.reparent(target.id, sibling.id);
      final graph = workspaces.connections
          .map((edge) => (edge.id, edge.fromId, edge.toId))
          .toList();
      expect(
        () => workspaces.connectTasks(
          source.id,
          target.id,
          confirmedMerge: approval,
        ),
        throwsStateError,
      );
      expect(target.parentId, sibling.id);
      expect(source.parentId, isNull);
      expect(oldRoot.parentId, isNull);
      expect(
        workspaces.connections.map((edge) => (edge.id, edge.fromId, edge.toId)),
        graph,
      );
      connectConfirmed(source.id, target.id);
      expect(target.parentId, source.id);
      expect(sibling.parentId, oldRoot.id);
      expect(workspaces.primaries, [source, oldRoot]);
    },
  );
  test(
    'stale hierarchy role or reversed approvals reject without further changes',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B', kind: AiWorkspaceKind.primary);
      final c = await task('C', kind: AiWorkspaceKind.primary);
      final oldPlan = workspaces.connectionMergeFor(a.id, b.id)!;
      expect(
        () => workspaces.connectTasks(b.id, a.id, confirmedMerge: oldPlan),
        throwsStateError,
      );
      expect(b.parentId, isNull);
      expect(a.parentId, isNull);
      workspaces.reparent(b.id, c.id);
      expect(
        () => workspaces.connectTasks(a.id, b.id, confirmedMerge: oldPlan),
        throwsStateError,
      );
      expect(b.parentId, c.id);
      expect(c.parentId, isNull);
      expect(a.parentId, isNull);
      final current = workspaces.connectionMergeFor(a.id, b.id)!;
      c.kind = AiWorkspaceKind.permanent;
      expect(
        () => workspaces.connectTasks(a.id, b.id, confirmedMerge: current),
        throwsStateError,
      );
      expect(c.parentId, isNull);
      expect(a.parentId, isNull);
      final confirmed = workspaces.connectionMergeFor(a.id, b.id)!;
      final edge = workspaces.connectTasks(
        a.id,
        b.id,
        confirmedMerge: confirmed,
      );
      final edgeCount = workspaces.connections.length;
      expect(
        () => workspaces.connectTasks(a.id, b.id, confirmedMerge: confirmed),
        throwsStateError,
      );
      expect(workspaces.connections, hasLength(edgeCount));
      expect(workspaces.connectTasks(a.id, b.id).id, edge.id);
    },
  );

  test(
    'orphan source subtree joins existing target root without changing roles',
    () async {
      final orphan = await task('Orphan');
      final orphanChild = await task('Orphan child', parent: orphan.id);
      final root = await task('Root', kind: AiWorkspaceKind.primary);
      final target = await task('Target child', parent: root.id);
      final plan = workspaces.connectionMergeFor(orphanChild.id, target.id)!;
      expect(plan.sourceRootId, orphan.id);
      expect(plan.targetRootId, root.id);
      expect(plan.rootId, orphan.id);
      expect(plan.parentId, target.id);
      expect(plan.changesRole, isFalse);
      expect(
        () => workspaces.connectTasks(orphanChild.id, target.id),
        throwsStateError,
      );
      workspaces.connectTasks(orphanChild.id, target.id, confirmedMerge: plan);
      expect(root.parentId, isNull);
      expect(root.kind, AiWorkspaceKind.primary);
      expect(orphan.parentId, target.id);
      expect(orphan.kind, AiWorkspaceKind.permanent);
      expect(orphanChild.parentId, orphan.id);
      expect(target.parentId, root.id);
    },
  );

  test('two orphan trees still require explicit merge approval', () async {
    final a = await task('A');
    final b = await task('B');
    final plan = workspaces.connectionMergeFor(a.id, b.id)!;
    expect(plan.changesRole, isFalse);
    expect(() => workspaces.connectTasks(a.id, b.id), throwsStateError);
    workspaces.connectTasks(a.id, b.id, confirmedMerge: plan);
    expect(b.parentId, a.id);
    expect(b.kind, AiWorkspaceKind.permanent);
    expect(a.kind, AiWorkspaceKind.permanent);
  });

  test(
    'legacy cross-tree links restore and group-copy without silently changing root roles',
    () async {
      final a = await task('A', kind: AiWorkspaceKind.primary);
      final b = await task('B', kind: AiWorkspaceKind.primary);
      await workspaces.flush();
      final saved =
          jsonDecode(
                scope.preferences.stringValue(
                  AiWorkspaceProvider.storageKey,
                  '',
                ),
              )
              as Map<String, dynamic>;
      saved['connections'] = [
        {'fromId': a.id, 'toId': b.id},
      ];
      await reload(replacement: saved);
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.primaries.map((s) => s.id), [a.id, b.id]);
      expect(workspaces.find(a.id)!.parentId, isNull);
      expect(workspaces.find(b.id)!.parentId, isNull);
      expect(workspaces.connections.single.isHierarchy, isFalse);
      expect(() => workspaces.connectTasks(a.id, b.id), throwsStateError);
      final copies = await workspaces.pasteCards(
        workspaces.copyCards([a.id, b.id]),
        titleForCopy: (name) => name,
      );
      expect(
        copies.every(
          (copy) =>
              copy.kind == AiWorkspaceKind.primary && copy.parentId == null,
        ),
        isTrue,
      );
      expect(workspaces.isConnected(copies[0].id, copies[1].id), isTrue);
      final plan = workspaces.connectionMergeFor(a.id, b.id)!;
      workspaces.connectTasks(a.id, b.id, confirmedMerge: plan);
      expect(workspaces.find(b.id)!.parentId, a.id);
      expect(
        workspaces.connections.where((e) => e.fromId == a.id && e.toId == b.id),
        hasLength(1),
      );
    },
  );

  test(
    'explicit promotion cuts all subtree boundary peers but retains internal links and state',
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
    'promotion after an alternate path cut isolates the selected subtree',
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
      expect(workspaces.connections.single.toId, child.id);
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
  test(
    'mixed deletion preview matches role changes after root replacement and cuts',
    () async {
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
      expect(preview[replacement.id], AiWorkspaceKind.primary);
      expect(root.kind, AiWorkspaceKind.primary);
      expect(detached.parentId, root.id);
      workspaces.removeMany([root.id]);
      workspaces.disconnectConnections([detached.id]);
      for (final entry in preview.entries) {
        expect(workspaces.find(entry.key)!.kind, entry.value);
      }
      expect(workspaces.connections, isEmpty);
    },
  );
}
