import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/agent_link.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/domain/roleplay_card.dart';
import 'package:lilygobox/features/assistant/domain/task_canvas_style.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';

import 'assistant_test_scope.dart';

class _WorkflowSaveFailureStorage extends AgentStorage {
  _WorkflowSaveFailureStorage() : super(path: ':memory:');

  bool failNextWorkflowSave = false;
  int workflowSaves = 0;
  void Function(Map<String, Object?>)? onRecycleCommit;

  @override
  Future<Object?> request(
    String operation, [
    Map<String, Object?> args = const {},
  ]) {
    if (operation == 'commitRecycle') onRecycleCommit?.call(args);
    return super.request(operation, args);
  }

  @override
  Future<void> saveWorkflow(Object value) {
    workflowSaves++;
    if (failNextWorkflowSave) {
      failNextWorkflowSave = false;
      return Future.error(StateError('Workflow save failed'));
    }
    return super.saveWorkflow(value);
  }
}

void main() {
  late AssistantTestScope scope;
  late _WorkflowSaveFailureStorage storage;
  late AiWorkspaceProvider workspaces;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late List<Map<String, dynamic>> requests;
  Completer<void>? gate;
  Completer<void>? namingGate;
  test(
    'roleplay library migrates bound cards and saves independent entries',
    () async {
      final card = AiRoleplayCard.fromFields({
        'name': 'Library card',
        'first_mes': 'Welcome to the library.',
      });
      final imported = AiRoleplayBinding(card: card, playerName: 'Guest');
      final agent = await workspaces.createPrimary(
        title: 'Agent',
        task: '',
        roleplay: imported,
        roleplayOpening: 0,
      );
      await workspaces.flush();

      final previous = await storage.request('readWorkflowData') as Map;
      previous.remove('roleplayLibrary');
      await storage.saveWorkflow(previous);
      final restored = AiWorkspaceProvider(scope.provider);
      await restored.initialized;
      final fingerprint = card.templateFingerprint;
      try {
        final assistant = restored.find(agent.id)!.assistant;
        expect(restored.roleplayTemplates.single.card.name, 'Library card');
        assistant.setRoleplayEnabled(false);
        expect(
          restored.deleteRoleplayTemplate(fingerprint, confirmedAgents: []),
          AiRoleplayLibraryDeleteResult.changed,
        );
        final affected = restored.roleplayLibraryUsage[fingerprint]!;
        expect(affected.single.id, agent.id);
        expect(
          restored.deleteRoleplayTemplate(
            fingerprint,
            confirmedAgents: affected,
          ),
          AiRoleplayLibraryDeleteResult.deleted,
        );
        expect(assistant.roleplayBinding, isNull);
        expect(assistant.messages.single.content, 'Welcome to the library.');
        expect(restored.roleplayTemplates, isEmpty);
        restored.addRoleplayTemplate(imported);
        restored.addRoleplayTemplate(imported);
        expect(restored.roleplayTemplates, hasLength(1));
        restored.addRoleplayTemplate(
          AiRoleplayBinding(
            card: AiRoleplayCard.fromFields({'name': 'Unused import'}),
            playerName: 'Guest',
          ),
        );
        await restored.flush();
        final reloaded = AiWorkspaceProvider(scope.provider);
        try {
          await reloaded.initialized;
          expect(reloaded.find(agent.id)!.assistant.roleplayBinding, isNull);
          expect(reloaded.roleplayTemplates.map((item) => item.card.name), [
            'Library card',
            'Unused import',
          ]);
          expect(
            reloaded.deleteRoleplayTemplate(fingerprint, confirmedAgents: []),
            AiRoleplayLibraryDeleteResult.deleted,
          );
          await reloaded.flush();
          final saved = await storage.request('readWorkflowData') as Map;
          expect(saved['roleplayLibrary'], hasLength(1));
        } finally {
          reloaded.dispose();
        }
      } finally {
        restored.dispose();
      }
    },
  );
  test(
    'agent creation and card forks retain independent processing speed',
    () async {
      final service = await scope.provider.saveService(
        name: 'Speed',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6.1-sol'],
        apiKey: 'key',
      );
      final source = await workspaces.create(
        title: 'Source',
        task: 'Instructions',
        serviceId: service,
        model: 'gpt-6.1-sol',
        processingSpeed: AiProcessingSpeed.fast,
        startImmediately: false,
      );
      final copy = await workspaces.duplicate(source.id, title: 'Copy');
      expect(copy.assistant.processingSpeed, AiProcessingSpeed.fast);
      final pasted = await workspaces.pasteCards([
        AiTaskCardCopy(source),
      ], titleForCopy: (title) => '$title (2)');
      expect(pasted.single.assistant.processingSpeed, AiProcessingSpeed.fast);
      await copy.assistant.setProcessingSpeed(AiProcessingSpeed.standard);
      expect(source.assistant.processingSpeed, AiProcessingSpeed.fast);
    },
  );
  void Function()? observeRequest;
  var spawnFromMain = false;
  Map<String, Object?> spawnSelection = {};
  Map<String, Object?>? waitSelection;
  var askApproval = false;
  var failNaming = false;
  var parentResponseCount = 0;
  FutureOr<Map<String, Object?>?> Function(List<dynamic>)? routeConversation;
  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    gate = null;
    namingGate = null;
    observeRequest = null;
    spawnFromMain = false;
    spawnSelection = {};
    waitSelection = null;
    askApproval = false;
    failNaming = false;
    parentResponseCount = 0;
    routeConversation = null;
    storage = _WorkflowSaveFailureStorage();
    await storage.ready;
    scope = await createAssistantTestScope(
      storage: storage,
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        body['_testAuthorization'] = request.headers['authorization'];
        body['_testUrl'] = request.url.toString();
        observeRequest?.call();
        requests.add(body);
        final messages = body['messages'] as List;
        if (await routeConversation?.call(messages) case final response?) {
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': response},
              ],
            }),
            200,
          );
        }
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
        final needsWait =
            isParent &&
            waitSelection != null &&
            messages.every((message) => message['role'] != 'tool');
        final needsTool =
            isParent && spawnFromMain && parentResponseCount++ == 0;
        final needsApproval =
            askApproval && messages.every((m) => m['role'] != 'tool');
        final response = needsWait || needsTool || needsApproval
            ? {
                'content': '',
                'tool_calls': [
                  {
                    'id': 'call-1',
                    'type': 'function',
                    'function': {
                      'name': needsWait
                          ? 'wait_agents'
                          : needsTool
                          ? 'spawn_agent'
                          : 'list_directory',
                      'arguments': jsonEncode(
                        needsWait
                            ? waitSelection
                            : needsTool
                            ? {
                                'title': 'Review',
                                'task': 'Check child',
                                ...spawnSelection,
                              }
                            : {'path': Directory.current.path},
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
    // These fixtures isolate workflow/messaging requests. Automatic memory
    // extraction has its own integration suite and makes additional API calls.
    scope.provider.autoSaveMemory = false;
    workspaces = AiWorkspaceProvider(scope.provider);
    workspaces.addListener(() {
      for (final session in workspaces.sessions) {
        session.assistant.autoSaveMemory = false;
      }
    });
  });
  tearDown(() async {
    if (gate?.isCompleted == false) gate!.complete();
    if (namingGate?.isCompleted == false) namingGate!.complete();
    await workspaces.flush().catchError((_) {});
    workspaces.dispose();
    await storage.close();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  for (final (existing, revoke) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test(
      'delegated tool review uses the original user request (existing: $existing, revoked: $revoke)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'delegated-review-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final output = File(
          '${directory.path}${Platform.pathSeparator}result.txt',
        );
        final root = await workspaces.create(
          title: 'Coordinator',
          task: 'Coordinator',
          startImmediately: false,
        );
        root.assistant.setPermissions(
          AiPermissions(mode: AiApprovalMode.automatic),
        );
        final existingWorker = existing
            ? await workspaces.create(
                title: 'Worker',
                task: 'Worker',
                parentId: root.id,
                startImmediately: false,
              )
            : null;
        final human =
            'Ask the worker to create ${output.path} and report back.';
        const assignment = 'Write the requested file and report back.';
        const report = 'Worker has finished.';
        final reviews = <Map<String, dynamic>>[];
        final writeReviewStarted = Completer<void>();
        final writeReviewDecision = Completer<void>();
        addTearDown(() {
          if (!writeReviewDecision.isCompleted) writeReviewDecision.complete();
        });
        Map<String, Object?> call(
          String name,
          Map<String, Object?> arguments,
        ) => {
          'content': '',
          'tool_calls': [
            {
              'id': 'call-$name',
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(arguments)},
            },
          ],
        };
        routeConversation = (messages) async {
          final user =
              messages.lastWhere((item) => item['role'] == 'user')['content']
                  as String;
          if ((messages.first['content'] as String).startsWith(
            'Review one proposed tool operation.',
          )) {
            final review = jsonDecode(user) as Map<String, dynamic>;
            reviews.add(review);
            if (review['operation'] == 'write_file') {
              writeReviewStarted.complete();
              if (revoke) await writeReviewDecision.future;
            }
            return {'content': 'APPROVE'};
          }
          final used = messages
              .where((message) => message['role'] == 'tool')
              .length;
          if (user == human) {
            if (used != 0) return {'content': 'Waiting for worker'};
            return existingWorker == null
                ? call('spawn_agent', {'title': 'Worker', 'task': assignment})
                : call('send_agent_message', {
                    'agent_id': existingWorker.id,
                    'message': assignment,
                  });
          }
          final envelope = jsonDecode(user) as Map<String, dynamic>;
          if (envelope['content'] == assignment) {
            if (used == 0) {
              return call('write_file', {
                'path': output.path,
                'content': 'delegated result',
                'expected_content': null,
              });
            }
            if (used == 1) {
              return call('send_agent_message', {
                'agent_id': root.id,
                'message': report,
              });
            }
          }
          return {'content': 'Done'};
        };

        final running = root.assistant.sendMessage(human);
        await writeReviewStarted.future.timeout(const Duration(seconds: 5));
        final child = workspaces.sessions.singleWhere(
          (item) => item.parentId == root.id,
        );
        expect(output.existsSync(), isFalse);
        if (revoke) root.assistant.stopGeneration();
        writeReviewDecision.complete();
        await running;
        final finished = Completer<void>();
        void checkFinished() {
          if (!child.busy && !finished.isCompleted) finished.complete();
        }

        child.assistant.addListener(checkFinished);
        try {
          checkFinished();
          await finished.future.timeout(const Duration(seconds: 5));
        } finally {
          child.assistant.removeListener(checkFinished);
        }

        final childReviews = reviews.where(
          (item) => item.containsKey('agent_messages'),
        );
        expect(childReviews.map((item) => item['operation']), [
          'write_file',
          if (!revoke) 'send_agent_message',
        ]);
        for (final review in childReviews) {
          expect(review['request'], human);
          expect(review['agent_messages'], [assignment]);
        }
        if (revoke) {
          expect(await output.exists(), isFalse);
        } else {
          expect(await output.readAsString(), 'delegated result');
          expect(
            root.assistant.messages.any((message) => message.content == report),
            isTrue,
          );
        }
      },
    );
  }
  Future<void> finish(String id) async {
    await workspaces.executeTool('wait_agents', {
      'agent_ids': [id],
      'wait_ms': 100,
    });
  }

  test(
    'canvas position saves do not notify workflow or relationship observers',
    () async {
      final primary = await workspaces.create(
        title: 'Primary',
        task: 'Coordinate',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: primary.id,
        startImmediately: false,
      );
      await workspaces.flush();
      final topologyBefore = await primary.assistant.workspaceToolHandler!(
        'get_agent_topology',
        {},
      );
      var workflowNotifications = 0;
      var agentNotifications = 0;
      void workflowListener() => workflowNotifications++;
      void agentListener() => agentNotifications++;
      workspaces.addListener(workflowListener);
      primary.assistant.addListener(agentListener);
      child.assistant.addListener(agentListener);
      try {
        final positions = {
          primary.id: [100.0, 200.0],
          child.id: [400.0, 200.0],
        };
        workspaces.updateCanvasPositions(positions);
        expect(workspaces.canvasPositions, positions);
        expect(workflowNotifications, 0);
        expect(agentNotifications, 0);
        await workspaces.flush();
        final saved = await storage.request('readWorkflowData') as Map;
        expect(saved['canvas'], positions);
        expect(workflowNotifications, 0);
        expect(agentNotifications, 0);
        expect(
          await primary.assistant.workspaceToolHandler!(
            'get_agent_topology',
            {},
          ),
          topologyBefore,
        );
        workspaces.select(child.id);
        expect(workflowNotifications, 1);
        expect(agentNotifications, 0);
      } finally {
        workspaces.removeListener(workflowListener);
        primary.assistant.removeListener(agentListener);
        child.assistant.removeListener(agentListener);
      }
    },
  );

  test('canvas-only saves preserve recycled records and coalesce with workflow edits', () async {
    final primary = await workspaces.create(
      title: 'Primary',
      task: 'Coordinate',
      startImmediately: false,
    );
    final child = await workspaces.create(
      title: 'Child',
      task: 'Saved long history ' * 1000,
      parentId: primary.id,
      startImmediately: false,
    );
    final beforeRemoval = workspaces.captureTopologyEdit();
    workspaces.remove(child.id);
    final afterRemoval = workspaces.captureTopologyEdit();
    addTearDown(() {
      workspaces.releaseTopologyEdit(beforeRemoval);
      workspaces.releaseTopologyEdit(afterRemoval);
    });
    final recycled = workspaces.recycledAgents.single.toJson();
    final initialSaves = storage.workflowSaves;
    for (var step = 1; step <= 3; step++) {
      workspaces.updateCanvasPositions({
        primary.id: [step * 100.0, step * 50.0],
      }, origin: Offset(-10.0 * step, 5.0 * step));
      workspaces.select(step.isEven ? null : primary.id);
      await workspaces.flush();
      expect(storage.workflowSaves, initialSaves + 1);
      final saved = await storage.request('readWorkflowData') as Map;
      expect(saved['canvas'], workspaces.canvasPositions);
      expect(saved['canvasOrigin'], [-10.0 * step, 5.0 * step]);
      expect(saved['selectedId'], workspaces.selectedId);
      expect(saved['recycleBin'], [recycled]);
      expect(workspaces.exportData()['recycleBin'], [recycled]);
    }
    workspaces.select(null);
    workspaces.rename(primary.id, 'Moved');
    await workspaces.flush();
    expect(storage.workflowSaves, initialSaves + 2);
    final renamed = await storage.request('readWorkflowData') as Map;
    expect((renamed['sessions'] as List).single['title'], 'Moved');
    expect(renamed['recycleBin'], [recycled]);
    await workspaces.restoreTopologyEdit(beforeRemoval, previous: afterRemoval);
    await workspaces.flush();
    expect(
      (await storage.request('readWorkflowData') as Map)['recycleBin'],
      isEmpty,
    );
    await workspaces.restoreTopologyEdit(afterRemoval, previous: beforeRemoval);
    await workspaces.flush();
    expect((await storage.request('readWorkflowData') as Map)['recycleBin'], [
      recycled,
    ]);
    workspaces.releaseTopologyEdit(beforeRemoval);
    workspaces.releaseTopologyEdit(afterRemoval);
    workspaces.dispose();
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.persistenceError, isNull);
    expect(workspaces.recycledAgents.single.toJson(), recycled);
    expect(workspaces.find(primary.id), isNotNull);
    expect(workspaces.find(child.id), isNull);
  });

  test(
    'agent lookup tracks creation deletion and recycle restoration',
    () async {
      expect(workspaces.find(null), isNull);
      expect(workspaces.find('missing'), isNull);
      final primary = await workspaces.create(
        title: 'Primary',
        task: 'Coordinate',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: primary.id,
        startImmediately: false,
      );
      expect(workspaces.find(primary.id), same(primary));
      expect(workspaces.find(child.id), same(child));
      expect(workspaces.sessions, [primary, child]);
      child.assistant.setPermissions(
        AiPermissions(mode: AiApprovalMode.automatic),
      );
      workspaces.remove(child.id);
      expect(workspaces.find(child.id), isNull);
      expect(workspaces.find(primary.id), same(primary));
      await workspaces.restoreRecycledAgent(child.id);
      final restored = workspaces.sessions.last;
      expect(restored.id, child.id);
      expect(restored, isNot(same(child)));
      expect(workspaces.find(child.id), same(restored));
      expect(restored.parentId, primary.id);
      expect(restored.assistant.permissions.mode, AiApprovalMode.automatic);
      expect(workspaces.recycledAgents, isEmpty);
    },
  );

  test(
    'purging reuses retained chats and preserves unsaved work on retry',
    () async {
      Future<AiAgentWorkspace> create(String title) => workspaces.create(
        title: title,
        task: 'Retain this history',
        startImmediately: false,
      );
      final retained = await create('Retained');
      await retained.assistant.sendMessage('Retained conversation');
      final messages = retained.assistant
          .snapshotWorkspaceConversation()['messages'];
      final purged = await create('Purged');
      final unchanged = await create('Unchanged');
      workspaces.removeMany([retained.id, purged.id]);
      await workspaces.flush();
      final unsaved = await create('Unsaved');
      var attempts = 0;
      storage.onRecycleCommit = (args) {
        attempts++;
        expect(args['owners'], [purged.id]);
        final workflow = args['value'] as Map;
        expect(
          (workflow['recycleBin'] as List).single['record'],
          isA<String>(),
        );
        final conversations = {
          for (final session in workflow['sessions'] as List)
            session['id']: session['conversation'],
        };
        expect(conversations[unchanged.id], {'@conversation': unchanged.id});
        expect(conversations[unsaved.id], contains('messages'));
        if (attempts == 1) throw StateError('Interrupted recycle commit');
      };
      await expectLater(
        workspaces.permanentlyDeleteRecycledAgents([purged.id]),
        throwsStateError,
      );
      expect(workspaces.recycledAgents, hasLength(2));
      await workspaces.permanentlyDeleteRecycledAgents([purged.id]);
      expect(attempts, 2);
      expect(workspaces.recycledAgents.single.id, retained.id);
      await workspaces.restoreRecycledAgent(retained.id);
      expect(
        workspaces
            .find(retained.id)!
            .assistant
            .snapshotWorkspaceConversation()['messages'],
        messages,
      );
      final saved = await storage.request('readWorkflowData') as Map;
      expect(
        (saved['sessions'] as List).map((entry) => entry['id']),
        unorderedEquals([unchanged.id, unsaved.id, retained.id]),
      );
    },
  );

  test('agent lookup follows topology undo redo and discarded edits', () async {
    final primary = await workspaces.create(
      title: 'Primary',
      task: 'Coordinate',
      startImmediately: false,
    );
    final before = workspaces.captureTopologyEdit();
    final child = await workspaces.create(
      title: 'Child',
      task: 'Work',
      parentId: primary.id,
      startImmediately: false,
    );
    final after = workspaces.captureTopologyEdit();
    try {
      await workspaces.restoreTopologyEdit(before);
      expect(workspaces.sessions, [primary]);
      expect(workspaces.find(child.id), isNull);
      await workspaces.restoreTopologyEdit(after);
      expect(workspaces.find(child.id), same(child));
      expect(workspaces.sessions, [primary, child]);
      workspaces.remove(child.id);
      expect(workspaces.find(child.id), isNull);
      await workspaces.restoreTopologyEdit(after);
      expect(workspaces.find(child.id), same(child));
      await workspaces.restoreTopologyEdit(before);
      expect(workspaces.find(child.id), isNull);
    } finally {
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
    }
    expect(workspaces.find(primary.id), same(primary));
    expect(workspaces.find(child.id), isNull);
  });

  test(
    'agent lookup tracks import persistence restoration and disposal',
    () async {
      final primary = await workspaces.create(
        title: 'Primary',
        task: 'Coordinate',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: primary.id,
        startImmediately: false,
      );
      final imported = await workspaces.importData(workspaces.exportData());
      expect(workspaces.find(imported[primary.id]), isNotNull);
      expect(
        workspaces.find(imported[child.id])!.parentId,
        imported[primary.id],
      );
      final order = workspaces.sessions.map((session) => session.id).toList();
      expect(order.take(2), [primary.id, child.id]);
      const origin = Offset(480, 240);
      workspaces.updateCanvasPositions({
        primary.id: [24, 72],
      }, origin: origin);
      for (final session in workspaces.sessions) {
        expect(workspaces.find(session.id), same(session));
      }
      await workspaces.flush();
      workspaces.dispose();
      for (final id in order) {
        expect(workspaces.find(id), isNull);
      }
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.sessions.map((session) => session.id), order);
      expect(workspaces.canvasOrigin, origin);
      expect(workspaces.canvasPositions[primary.id], [24, 72]);
      for (final session in workspaces.sessions) {
        expect(workspaces.find(session.id), same(session));
      }
      expect(workspaces.find(child.id)!.parentId, primary.id);
      expect(workspaces.find(null), isNull);
      expect(workspaces.find('missing'), isNull);
    },
  );

  test('agent lookup rolls back a failed recycle batch before retry', () async {
    final primary = await workspaces.create(
      title: 'Primary',
      task: 'Coordinate',
      startImmediately: false,
    );
    final child = await workspaces.create(
      title: 'Child',
      task: 'Work',
      parentId: primary.id,
      startImmediately: false,
    );
    final grandchild = await workspaces.create(
      title: 'Grandchild',
      task: 'Work',
      parentId: child.id,
      startImmediately: false,
    );
    final batch = [grandchild.id, child.id];
    workspaces.removeMany(batch);
    await workspaces.flush();
    storage.failNextWorkflowSave = true;
    await expectLater(
      workspaces.restoreRecycledAgents(batch),
      throwsStateError,
    );
    expect(workspaces.recycleBusy, isFalse);
    expect(workspaces.pendingRecycleRestore, isNull);
    expect(workspaces.sessions, [primary]);
    expect(workspaces.find(primary.id), same(primary));
    expect(workspaces.find(child.id), isNull);
    expect(workspaces.find(grandchild.id), isNull);
    expect(
      workspaces.recycledAgents.map((entry) => entry.id),
      unorderedEquals(batch),
    );
    await workspaces.restoreRecycledAgents(batch);
    expect(workspaces.find(child.id)?.parentId, primary.id);
    expect(workspaces.find(grandchild.id)?.parentId, child.id);
    expect(workspaces.recycledAgents, isEmpty);
  });

  test(
    'batch restore commits 836 long conversations together in parent order',
    () async {
      const count = 836;
      const firstId = '1000-0';
      const lastId = '1000-835';
      final content = 'Repeated test content. ' * 5700;
      final template = ConversationCodec.message(
        const AiMessage(id: 'message', role: 'user', content: ''),
      );
      final now = DateTime.now().toIso8601String();
      await workspaces.initialized;
      workspaces.dispose();
      await storage.saveWorkflow({
        'version': 1,
        'sessions': [],
        'connections': [],
        'recycleBin': [
          for (var index = count - 1; index >= 0; index--)
            {
              'deletedAt': now,
              'position': [index, index],
              'record': {
                'id': '1000-$index',
                'title': 'Agent $index',
                'task': 'Test restore',
                'kind': index == 0 ? 'primary' : 'permanent',
                'parentId': index == 0 ? null : '1000-${index - 1}',
                'createdAt': now,
                'conversation': {
                  'serviceId': '',
                  'model': '',
                  'messages': [
                    {...template, 'content': '$content$index'},
                  ],
                  'history': [],
                },
              },
            },
        ],
      });
      await storage.putMemory(id: 'memory', owner: lastId, content: 'Kept');
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.recycledAgents, hasLength(count));
      await workspaces.flush();
      await storage.request('clean');
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.recycledAgents, hasLength(count));
      final savesBefore = storage.workflowSaves;
      await workspaces.restoreRecycledAgents([
        for (var index = count - 1; index >= 0; index--) '1000-$index',
      ]);
      expect(storage.workflowSaves - savesBefore, 1);
      expect(workspaces.recycledAgents, isEmpty);
      expect(workspaces.sessions, hasLength(count));
      expect(workspaces.sessions.first.id, firstId);
      expect(workspaces.sessions.last.id, lastId);
      expect(workspaces.find(lastId)?.parentId, '1000-834');
      expect(
        workspaces.find(lastId)?.assistant.messages.single.content,
        '${content}835',
      );
      expect(workspaces.canvasPositions[lastId], [835, 835]);
      expect((await storage.memories(lastId)).single['content'], 'Kept');
    },
  );

  test(
    'a child report wakes an active wait without starting a new turn',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'Plan',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Worker',
        task: 'Collect findings',
        parentId: root.id,
        startImmediately: false,
      );
      gate = Completer<void>();
      await workspaces.send(child.id, 'Keep working');
      waitSelection = {
        'agent_ids': [child.id],
        'wait_ms': 5000,
      };
      final waiting = Completer<void>();
      root.assistant.addListener(() {
        if (waiting.isCompleted) return;
        if (root.assistant.messages.any(
          (message) => message.status == AiResponseStatus.executingTools,
        )) {
          waiting.complete();
        }
      });
      final turn = root.assistant.sendMessage('Delegate this');
      await waiting.future.timeout(const Duration(seconds: 2));
      await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': root.id,
        'message': 'Interim finding',
      });
      await turn.timeout(const Duration(seconds: 2));
      expect(child.busy, isTrue);
      expect(root.assistant.pendingGuidance, isEmpty);
      expect(
        root.assistant.messages.where((message) => message.role == 'user'),
        hasLength(1),
      );
      final outputs = requests
          .expand((request) => request['messages'] as List)
          .where((message) => message['tool_call_id'] == 'call-1');
      final output = jsonDecode(outputs.single['content'] as String) as Map;
      expect(output['reports'], [
        {
          'source_agent_id': child.id,
          'source_agent_title': 'Worker',
          'source_agent_kind': child.kind.name,
          'message': 'Interim finding',
        },
      ]);
    },
  );

  test('a child can collect reports from its parent and a connected peer only when selected', () async {
    final root = await workspaces.create(
      title: 'Root',
      task: 'Plan',
      startImmediately: false,
    );
    Future<AiAgentWorkspace> child(String title) => workspaces.create(
      title: title,
      task: 'Collaborate',
      parentId: root.id,
      startImmediately: false,
    );
    final caller = await child('Caller');
    final peer = await child('Peer');
    final unlinked = await child('Unlinked');
    workspaces.connectTasks(caller.id, peer.id);
    gate = Completer<void>();
    final turn = caller.assistant.sendMessage('Work');
    Future<Map<String, Object?>> sendReport(AiAgentWorkspace sender) =>
        sender.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': caller.id,
          'message': sender.title,
        });
    await expectLater(sendReport(unlinked), throwsStateError);
    await sendReport(root);
    await sendReport(peer);
    await caller.assistant.sendMessage('User follow-up');
    final tool = caller.assistant.workspaceToolHandler!;
    final peerWait = await tool('wait_agents', {
      'agent_ids': [peer.id],
      'wait_ms': 0,
    });
    expect((peerWait['reports'] as List).single['message'], peer.title);
    expect(caller.assistant.pendingGuidance.map((message) => message.content), [
      root.title,
      'User follow-up',
    ]);
    final parentWait = await tool('wait_agents', {
      'agent_ids': [root.id],
      'wait_ms': 0,
    });
    expect((parentWait['reports'] as List).single['message'], root.title);
    expect(caller.assistant.pendingGuidance.single.content, 'User follow-up');
    final peerTurn = peer.assistant.sendMessage('Keep working');
    final pending = tool('wait_agents', {
      'agent_ids': [peer.id],
      'wait_ms': 5000,
    });
    workspaces.stop(caller.id);
    expect(await pending.timeout(const Duration(seconds: 2)), {
      'cancelled': true,
    });
    expect(caller.assistant.pendingGuidance.single.content, 'User follow-up');
    gate!.complete();
    await turn;
    await peerTurn;
  });

  test('spawn exposes exact service speed tiers and uses them on the first request', () async {
    final serviceId = scope.provider.selectedService!.id;
    final root = await workspaces.create(
      title: 'Root',
      task: 'Plan',
      startImmediately: false,
    );
    final parent = await workspaces.create(
      title: 'Parent',
      task: 'Delegate',
      parentId: root.id,
      startImmediately: false,
    );
    final runTool = root.assistant.workspaceToolHandler!;
    final catalog = await runTool('list_agent_models', {});
    expect(catalog['inherited_processing_speed'], 'standard');
    final service = (catalog['services'] as List).single as Map;
    final speeds = service['processing_speeds'] as Map;
    expect(speeds['gpt-6.1-sol'], ['standard', 'fast']);
    expect(speeds['deepseek-flash'], isEmpty);

    final result = await runTool('spawn_agent', {
      'title': 'Worker',
      'task': 'Use the requested tier',
      'parent_agent_id': parent.id,
      'service_id': serviceId,
      'model': 'gpt-6.1-sol',
      'reasoning_effort': 'high',
      'processing_speed': 'fast',
    });
    expect(result['processing_speed'], 'fast');
    expect(result['reasoning_effort'], 'high');
    expect(result['parent_id'], parent.id);
    await finish(result['agent_id'] as String);
    expect(requests.first['service_tier'], 'priority');

    final count = workspaces.sessions.length;
    for (final speed in ['ultrafast', 'turbo']) {
      await expectLater(
        runTool('spawn_agent', {
          'title': 'Unsupported',
          'task': 'Do not create',
          'service_id': serviceId,
          'model': 'gpt-6.1-sol',
          'processing_speed': speed,
        }),
        throwsFormatException,
      );
    }
    expect(workspaces.sessions, hasLength(count));
  });

  test('agent speed changes respect management scope and reject incompatible changes atomically', () async {
    final serviceId = scope.provider.selectedService!.id;
    final root = await workspaces.create(
      title: 'Root',
      task: 'Plan',
      startImmediately: false,
    );
    Future<AiAgentWorkspace> child(
      String title,
      String parentId, {
      String model = 'gpt-6.1-sol',
    }) => workspaces.create(
      title: title,
      task: title,
      parentId: parentId,
      serviceId: serviceId,
      model: model,
      startImmediately: false,
    );
    final parent = await child('Parent', root.id);
    final leaf = await child('Leaf', parent.id);
    final end = await child('End', leaf.id);
    final incompatible = await child(
      'Incompatible',
      parent.id,
      model: 'deepseek-flash',
    );
    final busy = await child('Busy', parent.id);
    final outside = await workspaces.create(
      title: 'Outside',
      task: 'Plan',
      startImmediately: false,
    );
    workspaces.connectTasks(parent.id, end.id);
    final rootTool = root.assistant.workspaceToolHandler!;
    final parentTool = parent.assistant.workspaceToolHandler!;

    final single = await rootTool('configure_agent', {
      'agent_id': end.id,
      'processing_speed': 'fast',
    });
    expect(single['processing_speed'], 'fast');
    expect(
      (await parentTool('configure_agent', {
        'agent_id': leaf.id,
        'processing_speed': 'fast',
      }))['configured'],
      isTrue,
    );
    await expectLater(
      parentTool('configure_agent', {
        'agent_id': end.id,
        'processing_speed': 'standard',
      }),
      throwsStateError,
    );
    await expectLater(
      rootTool('configure_agents', {
        'agent_ids': [leaf.id, outside.id],
        'processing_speed': 'standard',
      }),
      throwsStateError,
    );
    expect(leaf.assistant.processingSpeed, AiProcessingSpeed.fast);

    await expectLater(
      rootTool('configure_agent', {
        'agent_id': leaf.id,
        'service_id': serviceId,
        'model': 'deepseek-flash',
        'reasoning_effort': 'low',
        'processing_speed': 'fast',
      }),
      throwsFormatException,
    );
    expect(leaf.assistant.selectedModel, 'gpt-6.1-sol');
    expect(leaf.assistant.processingSpeed, AiProcessingSpeed.fast);

    gate = Completer<void>();
    final running = busy.assistant.sendMessage('Keep working');
    final batch = await rootTool('configure_agents', {
      'agent_ids': [parent.id, incompatible.id, busy.id],
      'processing_speed': 'fast',
    });
    gate!.complete();
    await running;
    final results = (batch['results'] as List).cast<Map<String, Object?>>();
    expect(results.map((item) => item['configured']), [true, false, false]);
    expect(results[1]['detail'], contains('Unsupported processing_speed'));
    expect(results[2]['reason'], 'busy');
    expect(busy.assistant.processingSpeed, AiProcessingSpeed.standard);
    expect(root.assistant.processingSpeed, AiProcessingSpeed.standard);
  });

  test(
    'creation validates and applies context settings before work starts',
    () async {
      scope.provider.contextBudgetTokens = 180000;
      scope.provider.contextCompactionPercent = 85;
      final root = await workspaces.create(
        title: 'Root context',
        task: 'Wait',
        startImmediately: false,
      );
      expect(root.assistant.contextBudgetTokens, 180000);
      expect(root.assistant.contextCompactionPercent, 85);
      final child = await workspaces.create(
        title: 'Child context',
        task: 'Wait',
        parentId: root.id,
        contextBudgetTokens: 64000,
        contextCompactionPercent: 75,
        startImmediately: false,
      );
      expect(child.assistant.contextBudgetTokens, 64000);
      expect(child.assistant.contextCompactionThresholdTokens, 48000);
      expect(root.assistant.contextBudgetTokens, 180000);
      final snapshot = child.assistant.snapshotWorkspaceConversation();
      expect(snapshot['contextBudgetTokens'], 64000);
      expect(snapshot['contextCompactionPercent'], 75);
      final before = workspaces.sessions.length;
      await expectLater(
        workspaces.create(
          title: 'Invalid',
          task: 'Never run',
          contextBudgetTokens: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        workspaces.createPrimary(
          title: 'Invalid percent',
          task: 'Never run',
          contextCompactionPercent: 101,
        ),
        throwsRangeError,
      );
      expect(workspaces.sessions, hasLength(before));
    },
  );

  test('first model request sees the requested context settings', () async {
    var observed = false;
    observeRequest = () {
      final assistant = workspaces.sessions.single.assistant;
      expect(assistant.contextBudgetTokens, 96000);
      expect(assistant.contextCompactionPercent, 75);
      observed = true;
    };
    final root = await workspaces.createPrimary(
      title: 'First request',
      task: 'Answer briefly',
      contextBudgetTokens: 96000,
      contextCompactionPercent: 75,
    );
    await finish(root.id);
    expect(observed, isTrue);
  });

  test('wait_agents accepts more than 16 connected agents', () async {
    final root = await workspaces.create(
      title: 'Coordinator',
      task: 'Coordinate',
      startImmediately: false,
    );
    final ids = <String>[];
    for (var i = 0; i < 24; i++) {
      final child = await workspaces.create(
        title: 'Worker $i',
        task: 'Work',
        parentId: root.id,
        startImmediately: false,
      );
      ids.add(child.id);
    }
    final result = await root.assistant.workspaceToolHandler!('wait_agents', {
      'agent_ids': ids,
      'wait_ms': 0,
    });
    expect(result['agents'], hasLength(24));
  });

  test(
    'deleting a selected model clears live agents and drafts until reselection',
    () async {
      final agent = await workspaces.create(
        title: 'Keep conversation',
        task: 'Remember',
        startImmediately: false,
      );
      await workspaces.send(agent.id, 'Keep this history');
      await finish(agent.id);
      final draft = agent.assistant.forkForWorkspace();
      addTearDown(draft.dispose);
      final service = agent.assistant.selectedService!;
      final history = agent.assistant.messages.map((m) => m.content).toList();
      var changes = 0;
      agent.assistant.addListener(() => changes++);
      await scope.provider.saveService(
        id: service.id,
        name: service.name,
        protocol: service.protocol,
        baseUrl: service.baseUrl,
        models: ['deepseek-flash'],
      );
      expect(changes, greaterThan(0));
      for (final assistant in [agent.assistant, draft]) {
        expect(assistant.selectedModel, isNull);
        expect(assistant.selectedService, isNull);
        expect(assistant.hasApiKey, isFalse);
        expect(assistant.canSendMessage, isFalse);
      }
      expect(scope.provider.selectedModel, isNull);
      expect(scope.provider.hasApiKey, isFalse);
      expect(agent.assistant.messages.map((m) => m.content), history);
      final before = requests.length;
      await agent.assistant.sendMessage('Blocked');
      expect(requests.length, before);
      await agent.assistant.selectModel(service.id, 'deepseek-flash');
      await workspaces.send(agent.id, 'Use selected model');
      await finish(agent.id);
      expect(requests.last['model'], 'deepseek-flash');
      expect(agent.assistant.workspaceSelectionUnavailable, isFalse);
    },
  );

  test('service updates refresh live agent credentials and deletion clears its selection', () async {
    final agent = await workspaces.create(
      title: 'Agent',
      task: 'Work',
      startImmediately: false,
    );
    final service = agent.assistant.selectedService!;
    await scope.provider.saveService(
      id: service.id,
      name: 'Renamed',
      protocol: service.protocol,
      baseUrl: service.baseUrl,
      models: service.models,
      apiKey: 'rotated-key',
    );
    expect(agent.assistant.selectedService!.name, 'Renamed');
    await workspaces.send(agent.id, 'Use current key');
    await finish(agent.id);
    expect(requests.last['_testAuthorization'], 'Bearer rotated-key');
    await scope.provider.removeService(service.id);
    expect(agent.assistant.selectedModel, isNull);
    expect(agent.assistant.hasServiceKey(service.id), isFalse);
    expect(agent.assistant.canSendMessage, isFalse);
  });

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

    test('open tool emits exact target and source once per request without executing target', () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Plan');
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
      final result = await root.assistant.workspaceToolHandler!('open_agent', {
        'agent_id': child.id,
      });
      expect(result['navigation_requested'], isTrue);
      expect(result['url'], agentLink(child.id));
      expect(agentIdFromLink(child.toToolResult()['url'] as String), child.id);
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
    });

    test('background open returns link without stealing focus and rejects unavailable targets', () async {
      final root = await workspaces.createPrimary(title: 'Root', task: 'Plan');
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
      final result = await root.assistant.workspaceToolHandler!('open_agent', {
        'agent_id': child.id,
      });
      expect(result['navigation_requested'], isFalse);
      expect(result['url'], agentLink(child.id));
      expect(workspaces.navigationRequest, isNull);
      for (final id in [unrelated.id, 'missing', root.title]) {
        await expectLater(
          root.assistant.workspaceToolHandler!('open_agent', {'agent_id': id}),
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
    });
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

    test('should name an unnamed task with its selected model without polluting execution history', () async {
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
    });

    test('should keep task creation working when naming fails and preserve explicit names', () async {
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
    });
  });

  group('Task duplication', () {
    test('should fork conversation and configuration into an idle independent sibling without descendants', () async {
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
    });
  });

  test('fork continues with inherited context and leaves original history unchanged', () async {
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
    expect(history.where((m) => m['role'] == 'user').map((m) => m['content']), [
      'Remember the initial context',
      'Continue the branch',
    ]);
    expect(history.any((m) => m['role'] == 'assistant'), isTrue);
    expect(
      source.assistant.messages.map((m) => m.content),
      isNot(contains('Continue the branch')),
    );
    final ids = copy.assistant.messages.map((m) => m.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('fork waiting on approval closes pending tool context without copying approval', () async {
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
  });

  test(
    'detaching a child promotes it and persists the current role structure',
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
      workspaces.reparent(child.id, null);
      expect(child.kind, AiWorkspaceKind.primary);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      final restored = workspaces.find(child.id)!;
      expect(restored.parentId, isNull);
      expect(restored.kind, AiWorkspaceKind.primary);
      workspaces.reparent(restored.id, null);
      expect(restored.kind, AiWorkspaceKind.primary);
    },
  );

  test('card clipboard snapshots survive edits and deletion and preserve selected parent links', () async {
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
      copies.every((copy) => copy.assistant.messages.isNotEmpty && !copy.busy),
      isTrue,
    );
    expect(requests.length, count);
  });

  group('Task names', () {
    test('should persist renamed display titles without changing task identity or conversation', () async {
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
    });
  });

  group('Child model selection', () {
    test(
      'main manages every descendant without additional communication edges',
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
        final leaf = await workspaces.create(
          title: 'Leaf',
          task: 'Work',
          parentId: middle.id,
          startImmediately: false,
        );
        final end = await workspaces.create(
          title: 'End',
          task: 'Work',
          parentId: leaf.id,
          startImmediately: false,
        );
        expect(workspaces.isConnected(root.id, leaf.id), isFalse);
        final listed = await root.assistant.workspaceToolHandler!(
          'list_agents',
          {},
        );
        expect(
          (listed['agents'] as List).map((agent) => agent['agent_id']),
          containsAll([middle.id, leaf.id, end.id]),
        );
        await root.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': leaf.id,
          'message': 'Check',
        });
        await finish(leaf.id);
        final waited = await root.assistant.workspaceToolHandler!(
          'wait_agents',
          {
            'agent_ids': [leaf.id],
            'wait_ms': 0,
          },
        );
        expect((waited['agents'] as List).single['agent_id'], leaf.id);
        gate = Completer<void>();
        final running = leaf.assistant.sendMessage('Work');
        await Future<void>.delayed(Duration.zero);
        final guided = await root.assistant.workspaceToolHandler!(
          'send_agent_message',
          {'agent_id': leaf.id, 'message': 'Correct premise', 'mode': 'guide'},
        );
        expect(guided['delivered'], isTrue);
        gate!.complete();
        await running;
        await finish(leaf.id);
        gate = null;
        await root.assistant.workspaceToolHandler!('stop_agent', {
          'agent_id': end.id,
        });
        expect(workspaces.find(end.id), same(end));
        expect(end.busy, isFalse);
        final deleted = await root.assistant.workspaceToolHandler!(
          'delete_agent',
          {'agent_id': leaf.id},
        );
        expect(deleted['promoted_agent_ids'], isEmpty);
        expect(workspaces.find(leaf.id), isNull);
        expect(end.parentId, middle.id);
        expect(end.kind, AiWorkspaceKind.permanent);
        expect(workspaces.isConnected(middle.id, end.id), isTrue);
      },
    );

    test('child control remains direct-only and separate workflows grant no authority', () async {
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
      final leaf = await workspaces.create(
        title: 'Leaf',
        task: 'Work',
        parentId: middle.id,
        startImmediately: false,
      );
      final end = await workspaces.create(
        title: 'End',
        task: 'Work',
        parentId: leaf.id,
        startImmediately: false,
      );
      final other = await workspaces.create(
        title: 'Other',
        task: 'Plan',
        startImmediately: false,
      );
      final outside = await workspaces.create(
        title: 'Outside',
        task: 'Work',
        parentId: other.id,
        startImmediately: false,
      );
      workspaces.connectTasks(middle.id, end.id);
      for (final tool in ['stop_agent', 'delete_agent', 'configure_agent']) {
        for (final (caller, target) in [
          (middle, end),
          (root, outside),
          (middle, root),
          (root, root),
        ]) {
          await expectLater(
            caller.assistant.workspaceToolHandler!(tool, {
              'agent_id': target.id,
              if (tool == 'configure_agent') 'reasoning_effort': 'high',
            }),
            throwsStateError,
          );
        }
      }
      await expectLater(
        middle.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': end.id,
          'message': 'Interrupt',
          'mode': 'guide',
        }),
        throwsStateError,
      );
      await middle.assistant.workspaceToolHandler!('delete_agent', {
        'agent_id': leaf.id,
      });
      expect(end.parentId, middle.id);
      expect(end.kind, AiWorkspaceKind.permanent);
    });

    test('configure_agent rejects image-incompatible models without losing history', () async {
      final service = await scope.provider.saveService(
        name: 'Image compatibility',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['gpt-6.1-sol', 'plain-text'],
        apiKey: 'key',
        imageInputs: {
          'gpt-6.1-sol': AiImageInput.supported,
          'plain-text': AiImageInput.unsupported,
        },
      );
      final root = await workspaces.create(
        title: 'Root',
        task: 'Plan',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: root.id,
        serviceId: service,
        model: 'gpt-6.1-sol',
        startImmediately: false,
      );
      await child.assistant.sendMessage(
        'Describe',
        attachments: [
          AiImageAttachment(
            name: 'image.png',
            mimeType: 'image/png',
            bytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
            ),
          ),
        ],
      );
      expect(child.assistant.hasImageHistory, isTrue);
      final count = child.assistant.messages.length;
      await expectLater(
        child.assistant.selectModel(service, 'plain-text'),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(child.model, 'gpt-6.1-sol');
      await expectLater(
        root.assistant.workspaceToolHandler!('configure_agent', {
          'agent_id': child.id,
          'service_id': service,
          'model': 'plain-text',
        }),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(child.model, 'gpt-6.1-sol');
      expect(child.assistant.messages, hasLength(count));
      final result = await root.assistant.workspaceToolHandler!(
        'configure_agent',
        {'agent_id': child.id, 'reasoning_effort': 'high'},
      );
      expect(result['configured'], isTrue);
      expect(child.assistant.hasImageHistory, isTrue);
    });

    test(
      'configure_agent applies atomic local changes and persists them',
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
        final permissions = child.assistant.permissions;
        final service = scope.provider.selectedService!.id;
        final result = await root.assistant.workspaceToolHandler!(
          'configure_agent',
          {
            'agent_id': child.id,
            'service_id': service,
            'model': 'deepseek-flash',
            'reasoning_effort': 'max',
          },
        );
        expect(result['configured'], isTrue);
        expect(result['reasoning_effort'], 'max');
        expect(child.model, 'deepseek-flash');
        expect(child.assistant.permissions, same(permissions));
        expect(root.model, 'gpt-6.1-sol');
        expect(scope.provider.selectedModel, 'gpt-6.1-sol');
        expect(requests, isEmpty);
        await child.assistant.sendMessage('Check');
        expect(requests.last['reasoning_effort'], 'max');
        final history = child.assistant.messages.length;
        await root.assistant.workspaceToolHandler!('configure_agent', {
          'agent_id': child.id,
          'reasoning_effort': 'none',
        });
        expect(child.assistant.messages, hasLength(history));
        await workspaces.flush();
        workspaces.dispose();
        workspaces = AiWorkspaceProvider(scope.provider);
        await workspaces.initialized;
        expect(workspaces.find(child.id)!.model, 'deepseek-flash');
        expect(
          workspaces.find(child.id)!.assistant.reasoningEffort,
          AiReasoningEffort.none,
        );
      },
    );

    test('configure_agent follows management authority instead of communication links', () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'Plan',
        startImmediately: false,
      );
      final other = await workspaces.create(
        title: 'Other',
        task: 'Plan',
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'Work',
        parentId: root.id,
        startImmediately: false,
      );
      final peer = await workspaces.create(
        title: 'Peer',
        task: 'Work',
        parentId: root.id,
        startImmediately: false,
      );
      final grandchild = await workspaces.create(
        title: 'Grandchild',
        task: 'Work',
        parentId: child.id,
        startImmediately: false,
      );
      final descendant = await workspaces.create(
        title: 'Descendant',
        task: 'Work',
        parentId: grandchild.id,
        startImmediately: false,
      );
      workspaces.connectTasks(child.id, peer.id);
      for (final (caller, target) in [
        (child, root),
        (child, peer),
        (child, child),
        (child, descendant),
        (root, other),
        (other, grandchild),
      ]) {
        await expectLater(
          caller.assistant.workspaceToolHandler!('configure_agent', {
            'agent_id': target.id,
            'reasoning_effort': 'high',
          }),
          throwsStateError,
        );
      }
      for (final (caller, target) in [
        (root, descendant),
        (child, grandchild),
      ]) {
        final result = await caller.assistant.workspaceToolHandler!(
          'configure_agent',
          {'agent_id': target.id, 'reasoning_effort': 'high'},
        );
        expect(result['configured'], isTrue);
        expect(target.assistant.reasoningEffort, AiReasoningEffort.high);
      }
    });

    test('configure_agent rejects invalid changes without partially switching models', () async {
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
      final service = scope.provider.selectedService!.id;
      final originalEffort = child.assistant.reasoningEffort;
      for (final change in <Map<String, Object?>>[
        {},
        {'service_id': service},
        {'model': 'deepseek-flash'},
        {'reasoning_effort': null},
        {'reasoning_effort': 'HIGH'},
        {
          'service_id': service,
          'model': 'deepseek-flash',
          'reasoning_effort': 'medium',
        },
        {'service_id': service, 'model': 'missing'},
        {'service_id': 'missing', 'model': 'deepseek-flash'},
      ]) {
        await expectLater(
          root.assistant.workspaceToolHandler!('configure_agent', {
            'agent_id': child.id,
            ...change,
          }),
          throwsA(
            anyOf(
              isA<FormatException>(),
              isA<StateError>(),
              isA<AiConfigurationException>(),
            ),
          ),
        );
        expect(child.model, 'gpt-6.1-sol');
        expect(child.assistant.reasoningEffort, originalEffort);
      }
      gate = Completer<void>();
      final running = child.assistant.sendMessage('Wait');
      await Future<void>.delayed(Duration.zero);
      expect(child.busy, isTrue);
      final result = await root.assistant.workspaceToolHandler!(
        'configure_agent',
        {
          'agent_id': child.id,
          'service_id': service,
          'model': 'deepseek-flash',
          'reasoning_effort': 'high',
        },
      );
      expect(result['configured'], isFalse);
      expect(result['reason'], 'busy');
      expect(child.model, 'gpt-6.1-sol');
      await child.assistant.selectModel(service, 'deepseek-flash');
      await child.assistant.setReasoningEffort(AiReasoningEffort.high);
      gate!.complete();
      await running;
      expect(requests.last['model'], 'gpt-6.1-sol');
      await child.assistant.sendMessage('Use the next configuration');
      expect(requests.last['model'], 'deepseek-flash');
      expect(requests.last['reasoning_effort'], 'high');
    });

    test(
      'manual and tool model changes share local configuration rules',
      () async {
        final root = await workspaces.create(
          title: 'Root',
          task: 'Plan',
          startImmediately: false,
        );
        final manual = await workspaces.create(
          title: 'Manual',
          task: 'Work',
          parentId: root.id,
          startImmediately: false,
        );
        final automated = await workspaces.create(
          title: 'Automated',
          task: 'Work',
          parentId: root.id,
          startImmediately: false,
        );
        final service = scope.provider.selectedService!.id;
        await manual.assistant.selectModel(service, 'deepseek-flash');
        await manual.assistant.setReasoningEffort(AiReasoningEffort.high);
        await root.assistant.workspaceToolHandler!('configure_agent', {
          'agent_id': automated.id,
          'service_id': service,
          'model': 'deepseek-flash',
          'reasoning_effort': 'high',
        });
        expect(manual.model, automated.model);
        expect(
          manual.assistant.reasoningEffort,
          automated.assistant.reasoningEffort,
        );
        expect(
          manual.assistant.processingSpeed,
          automated.assistant.processingSpeed,
        );
        await expectLater(
          manual.assistant.setReasoningEffort(AiReasoningEffort.medium),
          throwsFormatException,
        );
        expect(manual.assistant.reasoningEffort, AiReasoningEffort.high);
        await manual.assistant.setReasoningEffort(null);
        expect(manual.assistant.reasoningEffort, isNull);
        expect(scope.provider.selectedModel, 'gpt-6.1-sol');
      },
    );

    for (final entry in ['canvas', 'chat', 'tool', 'all']) {
      test(
        '$entry stop clears approval waits and prevents queued restart',
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
          askApproval = true;
          final running = child.assistant.sendMessage('Needs approval');
          for (
            var attempt = 0;
            attempt < 50 && child.assistant.pendingApproval == null;
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(child.assistant.pendingApproval, isNotNull);
          await child.assistant.sendMessage('Queued');
          switch (entry) {
            case 'canvas':
              workspaces.stop(child.id);
            case 'chat':
              child.assistant.stopGeneration();
            case 'tool':
              await root.assistant.workspaceToolHandler!('stop_agent', {
                'agent_id': child.id,
              });
            case 'all':
              workspaces.stopAll();
          }
          await running.timeout(const Duration(seconds: 2));
          expect(child.assistant.pendingApproval, isNull);
          expect(child.assistant.busy, isFalse);
          expect(child.assistant.manuallyPaused, isTrue);
          expect(requests, hasLength(1));
          expect(child.assistant.pendingGuidance.single.content, 'Queued');
        },
      );
    }

    test(
      'should expose and apply exact reasoning levels on the first request',
      () async {
        final service = scope.provider.selectedService!.id;
        await scope.provider.setReasoningEffort(AiReasoningEffort.high);
        final choices = await workspaces.executeTool('list_agent_models', {});
        expect(choices['inherited_reasoning_effort'], 'high');
        final catalog = (choices['services'] as List).single as Map;
        expect((catalog['reasoning_efforts'] as Map)['deepseek-flash'], [
          'none',
          'low',
          'high',
          'max',
        ]);
        final definition = scope.provider.workspaceToolDefinitions.singleWhere(
          (spec) => (spec['function'] as Map)['name'] == 'spawn_agent',
        );
        final parameters = (definition['function'] as Map)['parameters'] as Map;
        expect((parameters['properties'] as Map), contains('reasoning_effort'));
        for (final effort in ['none', 'low', 'max']) {
          final result = await workspaces.executeTool('spawn_agent', {
            'title': 'Explicit $effort',
            'task': 'Check $effort',
            'service_id': service,
            'model': 'deepseek-flash',
            'reasoning_effort': effort,
          });
          final child = workspaces.find(result['agent_id'] as String)!;
          await finish(child.id);
          expect(result['reasoning_effort'], effort);
          expect(child.assistant.reasoningEffort?.name, effort);
          expect(requests.last['thinking'], {
            'type': effort == 'none' ? 'disabled' : 'enabled',
          });
          if (effort == 'none') {
            expect(requests.last, isNot(contains('reasoning_effort')));
          } else {
            expect(requests.last['reasoning_effort'], effort);
          }
        }
        expect(scope.provider.reasoningEffort, AiReasoningEffort.high);
        await scope.provider.selectModel(service, 'deepseek-flash');
        expect(scope.provider.reasoningEffort, AiReasoningEffort.low);
      },
    );

    test(
      'should override inherited reasoning without changing the parent',
      () async {
        final parent = await workspaces.create(
          title: 'Parent',
          task: 'Coordinate',
          startImmediately: false,
        );
        await parent.assistant.setReasoningEffort(AiReasoningEffort.high);
        for (final effort in [null, 'low']) {
          final result = await parent.assistant.workspaceToolHandler!(
            'spawn_agent',
            {
              'title': 'Child',
              'task': 'Check',
              if (effort != null) 'reasoning_effort': effort,
            },
          );
          final child = workspaces.find(result['agent_id'] as String)!;
          await finish(child.id);
          expect(result['reasoning_effort'], effort ?? 'high');
          expect(requests.last['reasoning_effort'], effort ?? 'high');
        }
        expect(parent.assistant.reasoningEffort, AiReasoningEffort.high);
      },
    );

    test(
      'should reject invalid or unsupported reasoning without spawning',
      () async {
        final service = scope.provider.selectedService!.id;
        await scope.provider.saveService(
          name: 'No reasoning',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://other.test/v1',
          models: ['plain-model'],
          apiKey: 'key',
        );
        final plainService = scope.provider.services.last.id;
        final count = workspaces.sessions.length;
        for (final effort in <Object?>[
          'medium',
          'minimal',
          'HIGH',
          '',
          'unknown',
          null,
          2,
          true,
        ]) {
          await expectLater(
            workspaces.executeTool('spawn_agent', {
              'title': 'Invalid',
              'task': 'Must not run',
              'service_id': service,
              'model': 'deepseek-flash',
              'reasoning_effort': effort,
            }),
            throwsFormatException,
          );
          expect(workspaces.sessions, hasLength(count));
        }
        await expectLater(
          workspaces.executeTool('spawn_agent', {
            'title': 'Invalid',
            'task': 'Must not run',
            'service_id': plainService,
            'model': 'plain-model',
            'reasoning_effort': 'none',
          }),
          throwsFormatException,
        );
        expect(workspaces.sessions, hasLength(count));
        expect(requests, isEmpty);
      },
    );

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

    test('should use the exact external service for both child kinds on the first request', () async {
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
        final result = await parent.assistant.workspaceToolHandler!(
          'spawn_agent',
          {
            'title': 'External $kind',
            'task': 'External $kind',
            'service_id': external,
            'model': 'external-deepseek',
          },
        );
        final child = workspaces.find(result['agent_id'] as String)!;
        await finish(child.id);
        expect(result['service_id'], external);
        expect(result['service_name'], 'External provider');
        expect(result['model'], 'external-deepseek');
        expect(child.assistant.permissions, same(parent.assistant.permissions));
        final request = requests.last;
        expect(request['model'], 'external-deepseek');
        expect(request['_testUrl'], startsWith('https://other.test/'));
        expect(request['_testAuthorization'], 'Bearer external-secret');
        expect(parent.model, 'gpt-6.1-sol');
        expect(scope.provider.selectedService!.id, original);
      }
    });

    test('should reject incomplete, unknown or mismatched selections without spawning or fallback', () async {
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
    });

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
        await workspaces.create(
          title: 'Task $i',
          task: 'Work $i',
          parentId: 'main',
        );
      }
      expect(workspaces.runningCount, 3);
      await workspaces.create(title: 'Extra', task: 'Extra', parentId: 'main');
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
        utf8.encode((await storage.request('readWorkflow')) as String).length,
        greaterThan(2 * 1024 * 1024),
      );
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      final progress = <double?>[];
      workspaces.restoreProgress.addListener(
        () => progress.add(workspaces.restoreProgress.value),
      );
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNull);
      expect(workspaces.sessions, hasLength(130));
      final measured = progress.whereType<double>().toList();
      expect(measured.first, 0);
      expect(measured.length, greaterThan(90));
      for (var index = 0; index < measured.length; index++) {
        expect(measured[index], inInclusiveRange(0, 1));
        expect(
          measured[index] * 130,
          closeTo((measured[index] * 130).round(), .000001),
        );
        if (index > 0) {
          expect(measured[index], greaterThan(measured[index - 1]));
        }
      }
      expect(progress.last, isNull);
      expect(workspaces.find(copies.single.id), isNotNull);
      expect(workspaces.sessions.every((agent) => !agent.busy), isTrue);
    },
  );

  test(
    'model spawning and agent messages can start beyond three running children',
    () async {
      final idle = await workspaces.create(
        title: 'Idle',
        task: 'First',
        parentId: 'main',
      );
      await finish(idle.id);
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(
          title: 'Busy $i',
          task: 'Hold $i',
          parentId: 'main',
        );
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
      final idle = await workspaces.create(
        title: 'Idle',
        task: 'First',
        parentId: 'main',
      );
      await finish(idle.id);
      gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await workspaces.create(
          title: 'Busy $i',
          task: 'Working $i',
          parentId: 'main',
        );
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
      await workspaces.send(child.id, 'Use updated service');
      await finish(child.id);
      expect(requests.last['_testUrl'], startsWith('https://new-origin.test/'));
      expect(requests.last['_testAuthorization'], 'Bearer new-origin-key');
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
  test('visible child tools permit owned stop and deletion but reject unrelated tasks', () async {
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
    final spawned = await first.assistant.workspaceToolHandler!('spawn_agent', {
      'title': 'Visible child',
      'task': 'Work once',
    });
    final child = workspaces.find(spawned['agent_id'] as String)!;
    await finish(child.id);
    expect(child.kind, AiWorkspaceKind.permanent);
    expect(child.parentId, first.id);
    final nested = await child.assistant.workspaceToolHandler!('spawn_agent', {
      'title': 'Nested',
      'task': 'Nested work',
    });
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
        second.assistant.workspaceToolHandler!(action, {'agent_id': child.id}),
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
    expect(workspaces.find(nestedId), same(nestedTask));
    expect(nestedTask.kind, AiWorkspaceKind.permanent);
    expect(nestedTask.parentId, first.id);
    expect(nestedTask.assistant.stopRequested, isFalse);
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
  });

  test('format starts at 1 and rejects obsolete versions IDs and temporary records', () async {
    final root = await workspaces.createPrimary(title: 'Main', task: 'Plan');
    await finish(root.id);
    expect(root.id, matches(RegExp(r'^\d+-\d+$')));
    await workspaces.flush();
    final snapshot = (await storage.request('readWorkflow')) as String;
    expect((jsonDecode(snapshot) as Map)['version'], 1);
    workspaces.dispose();
    scope.preferences.setValue('ai.taskTopology.v1', snapshot);
    scope.preferences.setValue('ai.agentWorkflow.v2', snapshot);
    await storage.saveWorkflow({
      'version': 1,
      'sessions': [],
      'connections': [],
    });
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.sessions, isEmpty);
    expect(scope.provider.services, isNotEmpty);
    workspaces.dispose();
    for (final corruption in ['version', 'id', 'kind']) {
      final saved = jsonDecode(snapshot) as Map;
      if (corruption == 'version') saved['version'] = 2;
      final record = (saved['sessions'] as List).single as Map;
      if (corruption == 'id') record['id'] = 'agent-123-0';
      if (corruption == 'kind') record['kind'] = 'temporary';
      await storage.saveWorkflow(saved);
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.sessions, isEmpty, reason: corruption);
      expect(workspaces.persistenceError, isNotNull, reason: corruption);
      workspaces.dispose();
    }
    await storage.saveWorkflow({
      'version': 1,
      'sessions': [],
      'connections': [],
    });
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  });

  test(
    'old conversation snapshots are rejected without inventing IDs or history',
    () async {
      final agent = await workspaces.create(
        title: 'New',
        task: 'New',
        startImmediately: false,
      );
      final snapshot = agent.assistant.snapshotWorkspaceConversation();
      expect(
        () => agent.assistant.restoreWorkspaceConversation({
          ...snapshot,
          'history': null,
        }),
        throwsFormatException,
      );
      expect(
        () => agent.assistant.restoreWorkspaceConversation({
          ...snapshot,
          'messages': [
            {'role': 'user', 'content': 'Old text snapshot'},
          ],
        }),
        throwsFormatException,
      );
      expect(agent.assistant.messages, isEmpty);
      expect(
        agent.assistant.snapshotWorkspaceConversation()['history'],
        isEmpty,
      );
    },
  );

  test('manual model selection applies before the first turn and primary turns do not consume child slots', () async {
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
      await workspaces.create(
        title: 'Busy $i',
        task: 'Busy $i',
        parentId: 'main',
      );
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
  });
  test('missing saved services preserve nodes and text until an explicit local reselection', () async {
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
        jsonDecode((await storage.request('readWorkflow')) as String) as Map;
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
    expect(requests.last['_testUrl'], startsWith('https://replacement.test/'));
    expect(requests.last['_testAuthorization'], 'Bearer replacement-key');
  });
  test('connected tasks can message in both directions with explicit source identities', () async {
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
    expect(received.toolArguments!['source_agent_kind'], 'primary');
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
  });

  test('automatic messages continue beyond 12 deliveries while suppressing duplicates', () async {
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
    for (var index = 0; index < 50; index++) {
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
    expect(
      (await primary.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': child.id,
        'message': 'Over budget',
      }))['delivered'],
      isTrue,
    );
    final spawned = await primary.assistant.workspaceToolHandler!(
      'spawn_agent',
      {'title': 'New worker', 'task': 'Continue collaboration'},
    );
    final temporary = workspaces.find(spawned['agent_id'] as String)!;
    await finish(temporary.id);
    expect(temporary.assistant.messages.first.toolName, 'agent_message');
    expect(
      temporary.assistant.messages.first.toolArguments!['source_agent_id'],
      primary.id,
    );
    expect(
      (await primary.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': temporary.id,
        'message': 'Still over budget after spawning',
      }))['delivered'],
      isTrue,
    );
    await workspaces.send(primary.id, 'Human adds instructions');
    await finish(primary.id);
    final resumed = await primary.assistant.workspaceToolHandler!(
      'send_agent_message',
      {'agent_id': child.id, 'message': 'New collaboration'},
    );
    expect(resumed['delivered'], isTrue);
    await finish(child.id);
  });

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
  test('long-term descendants retain child edge isolation while mains manage the whole tree', () async {
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
    final delivery = await root.assistant.workspaceToolHandler!(
      'send_agent_message',
      {'agent_id': leaf.id, 'message': 'Skip parent'},
    );
    expect(delivery['delivered'], isTrue);
    await finish(leaf.id);
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
    expect(workspaces.find(middle.id), isNull);
    expect(workspaces.find(leaf.id), same(leaf));
    expect(leaf.kind, AiWorkspaceKind.permanent);
    expect(leaf.parentId, root.id);
    expect(workspaces.find(temporary.id), same(temporary));
    expect(temporary.parentId, leaf.id);
    expect(workspaces.find(furtherId)!.parentId, temporary.id);
  });

  test('restore sorts arbitrary nested records and rejects invalid graphs without rewriting', () async {
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
    final data = jsonDecode(
      (await storage.request('readWorkflow')) as String,
    ) as Map<String, dynamic>;
    data['sessions'] = (data['sessions'] as List).reversed.toList();
    await storage.saveWorkflow(data);
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
      await storage.saveWorkflow(invalid);
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.persistenceError, isNotNull);
      expect(workspaces.sessions, isEmpty);
      await expectLater(workspaces.flush(), throwsStateError);
      expect((await storage.request('readWorkflow')) as String, invalid);
      workspaces.dispose();
    }
    await storage.saveWorkflow({
      'version': 1,
      'sessions': [],
      'connections': [],
    });
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  });

  test(
    'nested automatic deliveries and newly spawned agents remain available',
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
      for (var index = 0; index < 50; index++) {
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
        expect(
          (await spawned.assistant.workspaceToolHandler!('send_agent_message', {
            'agent_id': middle.id,
            'message': 'Budget bypass $kind',
          }))['delivered'],
          isTrue,
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
  test('explicit task permissions apply to root and long-term first turns without changing the parent', () async {
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
  });

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
  test('canvas style persists independently of the workflow', () async {
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
    );
    await finish(root.id);
    await workspaces.flush();
    final topology =
        jsonDecode((await storage.request('readWorkflow')) as String) as Map;
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
    expect(restored.assistant.permissions.isDefault, isTrue);
    workspaces.setCanvasStyle(AiTaskCanvasStyle.plain);
    await workspaces.flush();
    workspaces.dispose();
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.canvasStyle, AiTaskCanvasStyle.plain);
  });

  test('reopen restores saved approval modes and rules', () async {
    final automatic = await workspaces.create(
      title: 'Automatic',
      task: 'Review tools',
      startImmediately: false,
    );
    final custom = await workspaces.create(
      title: 'Custom',
      task: 'Use selected folders',
      startImmediately: false,
    );
    final folder = Directory.systemTemp.absolute.path;
    final child = '$folder${Platform.pathSeparator}restricted';
    final customSettings = AiPermissions(
      mode: AiApprovalMode.custom,
      network: false,
      execution: true,
      commandNoApproval: true,
      files: AiFileAccess.readWrite,
      folders: [folder, child],
      folderAccess: {child: AiFileAccess.none},
    );
    await workspaces.flush();
    automatic.assistant.setPermissions(
      AiPermissions(mode: AiApprovalMode.automatic),
    );
    custom.assistant.setPermissions(customSettings);
    await workspaces.flush();
    workspaces.dispose();
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    expect(workspaces.persistenceError, isNull);
    expect(
      workspaces.find(automatic.id)!.assistant.permissions.mode,
      AiApprovalMode.automatic,
    );
    final restored = workspaces.find(custom.id)!.assistant;
    expect(restored.permissions.toJson(), customSettings.toJson());
    expect(restored.permissions.folders, [folder, child]);
    expect(restored.pendingApproval, isNull);
  });

  test('import restores only valid permission settings', () async {
    final source = await workspaces.create(
      title: 'Source agent',
      task: 'Do not start on import',
      startImmediately: false,
      permissions: AiPermissions(mode: AiApprovalMode.custom, network: false),
    );
    final permissions = source.assistant.permissions;
    Map<String, dynamic> exported() =>
        Map<String, dynamic>.from(workspaces.exportData(agentId: source.id));
    expect(
      (exported()['sessions'] as List).single['permissions'],
      permissions.toJson(),
    );
    final valid = await workspaces.importData(exported());
    final legacy = exported();
    ((legacy['sessions'] as List).single as Map).remove('permissions');
    final fromLegacy = await workspaces.importData(legacy);
    final corrupt = exported();
    (corrupt['sessions'] as List).single['permissions'] = {
      ...permissions.toJson(),
      'network': 'invalid',
      'fullFiles': true,
    };
    final fromCorrupt = await workspaces.importData(corrupt);
    final imported = workspaces.find(valid[source.id])!.assistant;
    expect(imported.permissions.toJson(), permissions.toJson());
    for (final mapping in [fromLegacy, fromCorrupt]) {
      final agent = workspaces.find(mapping[source.id])!.assistant;
      expect(agent.permissions.isDefault, isTrue);
      expect(agent.pendingApproval, isNull);
    }
    expect(requests, isEmpty);
    await workspaces.flush();
    final stored = await storage.request('readWorkflowData') as Map;
    final byId = {
      for (final record in (stored['sessions'] as List).cast<Map>())
        record['id']: record['permissions'],
    };
    expect(byId[source.id], permissions.toJson());
    expect(byId[valid[source.id]], permissions.toJson());
  });

  test('unknown saved canvas style falls back to dots without changing task storage', () async {
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
  });
  test('root removal promotes latest direct long-term child and preserves other branches intact', () async {
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
    expect(workspaces.find(nested.id)!.kind, AiWorkspaceKind.permanent);
    expect(workspaces.find(nested.id)!.parentId, replacement.id);
    expect(workspaces.find(replacement.id), isNotNull);
    expect(workspaces.find(keptTemp.id), isNotNull);
  });

  test(
    'promoted task keeps message dedupe and supports continued collaboration',
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
      for (var index = 0; index < 50; index++) {
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
      for (var index = 1; index < 50; index++) {
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
      expect(
        (await replacement.assistant.workspaceToolHandler!(
          'send_agent_message',
          {'agent_id': first.id, 'message': 'Cannot reset by promotion'},
        ))['delivered'],
        isTrue,
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
  test('manual reconnect preserves task state, enforces one parent and persists acyclic roles', () async {
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
    expect(() => workspaces.reparent(child.id, temporary.id), throwsStateError);
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
  });

  test('detaching and merging trees preserves dedupe without blocking fresh messages', () async {
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
    final other = await workspaces.createPrimary(title: 'Other', task: 'Other');
    await finish(other.id);
    for (var index = 0; index < 50; index++) {
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
    expect(
      (await grandchild.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': child.id,
        'message': 'After detach',
      }))['delivered'],
      isTrue,
    );
    workspaces.reparent(child.id, other.id);
    expect(
      (await other.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': child.id,
        'message': 'After merge',
      }))['delivered'],
      isTrue,
    );
    workspaces.reparent(child.id, root.id);
    expect(
      (await root.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': child.id,
        'message': 'Original branch retained',
      }))['delivered'],
      isTrue,
    );
  });

  test('same-tree reconnect allows continued automatic deliveries', () async {
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
    for (var index = 4; index < 50; index++) {
      await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': root.id,
        'message': 'Next $index',
      });
      await finish(root.id);
    }
    expect(
      (await child.assistant.workspaceToolHandler!('send_agent_message', {
        'agent_id': root.id,
        'message': 'Thirteenth',
      }))['delivered'],
      isTrue,
    );
  });

  test('batch deletion excludes selected branches from promotion and deduplicates descendants', () async {
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
  });
  test(
    'whole-tree merge preserves dedupe until human input after a later detach',
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
      for (var index = 0; index < 50; index++) {
        await child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': merged.id,
          'message': 'Repeat $index',
        });
        await finish(merged.id);
      }
      workspaces.reparent(merged.id, root.id);
      expect(
        (await child.assistant.workspaceToolHandler!('send_agent_message', {
          'agent_id': merged.id,
          'message': 'Exhausted after merge',
        }))['delivered'],
        isTrue,
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
