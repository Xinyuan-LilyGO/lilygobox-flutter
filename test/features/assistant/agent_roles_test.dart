import 'dart:async';
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
  late AiWorkspaceProvider workspace;
  late AgentStorage storage;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late List<Map<String, dynamic>> requests;
  late DateTime now;
  Map<String, Object?>? nextModelTool;

  Future<AiAgentWorkspace> create(String title, {String? parent}) =>
      workspace.create(
        title: title,
        task: title,
        parentId: parent,
        startImmediately: false,
      );

  setUp(() async {
    now = DateTime.utc(2026, 11, 18, 1);
    nextModelTool = null;
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    requests = [];
    storage = AgentStorage(path: ':memory:');
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final tool = nextModelTool;
        nextModelTool = null;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': tool == null ? 'Done' : '',
                  if (tool != null) 'tool_calls': [tool],
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
      models: ['test'],
      apiKey: 'key',
    );
    workspace = AiWorkspaceProvider(scope.provider, clock: () => now);
    workspace.addListener(() {
      for (final task in workspace.sessions) {
        task.assistant.useMemory = false;
        task.assistant.autoSaveMemory = false;
      }
    });
    await workspace.initialized;
  });

  tearDown(() async {
    await workspace.flush();
    workspace.dispose();
    scope.dispose();
    await storage.close();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  List<Map> updates() => (requests.last['messages'] as List)
      .whereType<Map>()
      .where(
        (message) =>
            message['role'] == 'system' &&
            message['content'] is String &&
            (message['content'] as String).startsWith(
              '{"event":"agent_relationship_update"',
            ),
      )
      .map((message) => jsonDecode(message['content'] as String) as Map)
      .toList();

  Future<Map<String, Object?>> topology(AiAgentWorkspace agent) =>
      agent.assistant.workspaceToolHandler!('get_agent_topology', {});

  Future<Map<String, Object?>> timerTool(
    AiAgentWorkspace agent,
    String name, [
    Map<String, Object?> args = const {},
  ]) => agent.assistant.workspaceToolHandler!(name, args);

  Future<void> waitUntil(bool Function() ready) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Expected asynchronous timer operation did not become ready');
  }

  test(
    'main connects siblings without changing roles and link persists',
    () async {
      final leader = await create('Leader');
      final first = await create('First', parent: leader.id);
      final second = await create('Second', parent: leader.id);
      final args = {'from_agent_id': first.id, 'to_agent_id': second.id};
      final before = workspace.connections.length;
      final result = await timerTool(leader, 'connect_agents', args);
      expect(result['connected'], isTrue);
      expect(result['already_connected'], isFalse);
      expect(workspace.isConnected(first.id, second.id), isTrue);
      expect(workspace.isConnected(second.id, first.id), isTrue);
      expect(first.parentId, leader.id);
      expect(second.kind, AiWorkspaceKind.permanent);
      final repeated = await timerTool(leader, 'connect_agents', args);
      expect(repeated['already_connected'], isTrue);
      expect(workspace.connections.length, before + 1);
      final response = await timerTool(first, 'send_agent_message', {
        'agent_id': second.id,
        'message': 'Discuss directly',
      });
      expect(response['delivered'], isTrue);
      await waitUntil(() => !second.assistant.busy);
      expect(
        second.assistant.messages.any(
          (message) => message.content == 'Discuss directly',
        ),
        isTrue,
      );
      await workspace.flush();
      workspace.dispose();
      workspace = AiWorkspaceProvider(scope.provider, clock: () => now);
      await workspace.initialized;
      expect(workspace.isConnected(first.id, second.id), isTrue);
    },
  );

  test(
    'connection tool rejects children outside groups self and closed agents',
    () async {
      final leader = await create('Leader');
      final first = await create('First', parent: leader.id);
      final second = await create('Second', parent: leader.id);
      final outside = await create('Outside');
      await expectLater(
        timerTool(first, 'connect_agents', {
          'from_agent_id': first.id,
          'to_agent_id': second.id,
        }),
        throwsStateError,
      );
      await expectLater(
        timerTool(leader, 'connect_agents', {
          'from_agent_id': first.id,
          'to_agent_id': outside.id,
        }),
        throwsStateError,
      );
      await expectLater(
        timerTool(leader, 'connect_agents', {
          'from_agent_id': first.id,
          'to_agent_id': first.id,
        }),
        throwsStateError,
      );
      second.closed = true;
      await expectLater(
        timerTool(leader, 'connect_agents', {
          'from_agent_id': first.id,
          'to_agent_id': second.id,
        }),
        throwsStateError,
      );
      expect(workspace.isConnected(first.id, outside.id), isFalse);
    },
  );

  test(
    'disconnect removes only supplemental edges and allows reconnect',
    () async {
      final leader = await create('Leader');
      final first = await create('First', parent: leader.id);
      final second = await create('Second', parent: leader.id);
      final args = {'from_agent_id': first.id, 'to_agent_id': second.id};
      await timerTool(leader, 'connect_agents', args);
      final result = await timerTool(leader, 'disconnect_agents', args);
      expect(result['disconnected'], isTrue);
      expect(result['already_disconnected'], isFalse);
      expect(workspace.isConnected(first.id, second.id), isFalse);
      expect(first.parentId, leader.id);
      expect(second.parentId, leader.id);
      expect(workspace.find(first.id), same(first));
      expect(
        (await timerTool(
          leader,
          'disconnect_agents',
          args,
        ))['already_disconnected'],
        isTrue,
      );
      await expectLater(
        timerTool(leader, 'disconnect_agents', {
          'from_agent_id': leader.id,
          'to_agent_id': first.id,
        }),
        throwsStateError,
      );
      await expectLater(
        timerTool(first, 'disconnect_agents', args),
        throwsStateError,
      );
      await timerTool(leader, 'connect_agents', args);
      expect(workspace.isConnected(first.id, second.id), isTrue);
    },
  );

  test('an idle workflow expires without messages or model requests', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    final result = await timerTool(leader, 'start_timer', {
      'duration_seconds': 60,
      'objective': 'Wait for an external task',
    });
    expect(result['started'], isTrue);
    now = now.add(const Duration(minutes: 1));
    final expired = await timerTool(leader, 'get_timer');
    expect(expired['status'], 'expired');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests, isEmpty);
    for (final agent in [leader, child]) {
      expect(agent.assistant.busy, isFalse);
      expect(agent.assistant.messages, isEmpty);
      expect(agent.assistant.pendingGuidance, isEmpty);
      expect(
        jsonEncode(agent.assistant.snapshotWorkspaceConversation()),
        isNot(contains('timer_expired')),
      );
    }
  });

  test('main creates a grandchild without relaying or inheriting its parent permissions', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    final outside = await create('Outside');
    child.assistant.setPermissions(
      child.assistant.permissions.copyWith(execution: true),
    );
    final args = {'title': 'Worker', 'task': 'Work independently'};
    final result = await timerTool(leader, 'spawn_agent', {
      ...args,
      'parent_agent_id': child.id,
    });
    final worker = workspace.find(result['agent_id'] as String)!;
    await waitUntil(() => !worker.assistant.busy);
    expect(worker.parentId, child.id);
    expect(worker.assistant.permissions, same(leader.assistant.permissions));
    expect(
      worker.assistant.messages.first.toolArguments?['source_agent_id'],
      leader.id,
    );
    await expectLater(
      timerTool(leader, 'spawn_agent', {
        ...args,
        'parent_agent_id': outside.id,
      }),
      throwsStateError,
    );
    await expectLater(
      timerTool(child, 'spawn_agent', {...args, 'parent_agent_id': child.id}),
      throwsStateError,
    );
  });

  test(
    'main moves a branch without changing descendants or crossing workflows',
    () async {
      final leader = await create('Leader');
      final child = await create('Child', parent: leader.id);
      final grandchild = await create('Grandchild', parent: child.id);
      final sibling = await create('Sibling', parent: leader.id);
      final outside = await create('Outside');
      Future<Map<String, Object?>> move(
        AiAgentWorkspace caller,
        AiAgentWorkspace target,
        AiAgentWorkspace parent,
      ) => timerTool(caller, 'reparent_agent', {
        'agent_id': target.id,
        'parent_agent_id': parent.id,
      });
      await expectLater(move(leader, child, grandchild), throwsStateError);
      await expectLater(move(leader, child, outside), throwsStateError);
      await expectLater(move(leader, outside, sibling), throwsStateError);
      await expectLater(move(child, grandchild, sibling), throwsStateError);
      await move(leader, child, sibling);
      expect(child.parentId, sibling.id);
      expect(grandchild.parentId, child.id);
      expect(outside.parentId, isNull);
      await move(leader, child, leader);
      expect(child.parentId, leader.id);
    },
  );

  test('main batches only explicit descendants and rejects mixed-scope batches before acting', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    final middle = await create('Middle', parent: child.id);
    final leaf = await create('Leaf', parent: middle.id);
    final outside = await create('Outside');
    final service = leader.assistant.selectedService!;
    final config = {
      'service_id': service.id,
      'model': leader.assistant.selectedModel!,
    };
    for (final tool in ['stop_agents', 'delete_agents', 'configure_agents']) {
      await expectLater(
        timerTool(leader, tool, {
          ...config,
          'agent_ids': [child.id, outside.id],
        }),
        throwsStateError,
      );
      await expectLater(
        timerTool(leader, tool, {
          ...config,
          'agent_ids': [child.id, leader.id],
        }),
        throwsStateError,
      );
      await expectLater(
        timerTool(child, tool, {
          ...config,
          'agent_ids': [middle.id],
        }),
        throwsStateError,
      );
    }
    expect(workspace.find(child.id), same(child));
    expect(child.assistant.manuallyPaused, isFalse);
    final configured = await timerTool(leader, 'configure_agents', {
      ...config,
      'agent_ids': [child.id, middle.id],
    });
    expect(
      (configured['results'] as List).map((result) => result['configured']),
      [true, true],
    );
    final stopped = await timerTool(leader, 'stop_agents', {
      'agent_ids': [child.id, leaf.id],
    });
    expect(stopped['results'], hasLength(2));
    expect(child.assistant.manuallyPaused, isTrue);
    expect(leaf.assistant.manuallyPaused, isTrue);
    expect(middle.assistant.manuallyPaused, isFalse);
    final deleted = await timerTool(leader, 'delete_agents', {
      'agent_ids': [child.id, middle.id, child.id],
    });
    expect(deleted['results'], hasLength(2));
    expect(workspace.find(child.id), isNull);
    expect(workspace.find(middle.id), isNull);
    expect(leaf.parentId, leader.id);
    expect(workspace.find(outside.id), same(outside));
  });

  test(
    'public workspace tools do not prescribe a discussion scenario',
    () async {
      final leader = await create('Leader');
      final definitions = leader.assistant.workspaceToolDefinitions;
      final names = definitions.map(
        (definition) => (definition['function'] as Map)['name'],
      );
      expect(
        names,
        containsAll(['start_timer', 'get_timer', 'wait_timer', 'cancel_timer']),
      );
      expect(names.where((name) => '$name'.contains('discussion')), isEmpty);
      for (final definition in definitions) {
        final description =
            ((definition['function'] as Map)['description'] as String)
                .toLowerCase();
        expect(description, isNot(contains('discussion')));
        expect(description, isNot(contains('debate')));
        expect(description, isNot(contains('root main')));
        expect(description, isNot(contains('root agent')));
        expect(description, isNot(contains('root groups')));
      }
    },
  );

  for (final objective in [
    'Observe service health',
    'Wait for a file',
    'Review a document',
  ]) {
    test(
      'timer accepts a standalone non-discussion objective: $objective',
      () async {
        final leader = await create('Leader');
        final started = await timerTool(leader, 'start_timer', {
          'duration_seconds': 10,
          'objective': objective,
        });
        expect(started['objective'], objective);
        expect(started['status'], 'running');
        expect(workspace.sessions, hasLength(1));
        now = now.add(const Duration(seconds: 10));
        expect((await timerTool(leader, 'get_timer'))['status'], 'expired');
        expect(requests, isEmpty);
      },
    );
  }

  test(
    'guidance rejects interruptions of peers, ancestors and unmanaged agents',
    () async {
      final leader = await create('Leader');
      final child = await create('Child', parent: leader.id);
      final grandchild = await create('Grandchild', parent: child.id);
      final leaf = await create('Leaf', parent: grandchild.id);
      final sibling = await create('Sibling', parent: leader.id);
      final outside = await create('Outside');
      workspace.connectTasks(child.id, sibling.id);
      workspace.connectTasks(child.id, leaf.id);
      for (final pair in [
        (child, leader),
        (child, sibling),
        (child, leaf),
        (leader, outside),
      ]) {
        await expectLater(
          timerTool(pair.$1, 'send_agent_message', {
            'agent_id': pair.$2.id,
            'message': 'Interrupt',
            'mode': 'guide',
          }),
          throwsStateError,
        );
        expect(pair.$2.assistant.pendingGuidance, isEmpty);
        expect(pair.$2.assistant.busy, isFalse);
      }
      await expectLater(
        timerTool(leader, 'send_agent_message', {
          'agent_id': child.id,
          'message': 'Invalid',
          'mode': 'invalid',
        }),
        throwsFormatException,
      );
      workspace.stop(grandchild.id);
      await expectLater(
        timerTool(child, 'send_agent_message', {
          'agent_id': grandchild.id,
          'message': 'Try to resume a manually stopped agent',
          'mode': 'guide',
        }),
        throwsStateError,
      );
      expect(grandchild.assistant.manuallyPaused, isTrue);
      expect(grandchild.assistant.pendingGuidance, isEmpty);
    },
  );

  void requestTimerWait(String timerId) {
    nextModelTool = {
      'id': 'wait-timer-call',
      'type': 'function',
      'function': {
        'name': 'wait_timer',
        'arguments': jsonEncode({'timer_id': timerId}),
      },
    };
  }

  for (final fromMain in [true, false]) {
    test(
      '${fromMain ? 'Main' : 'Direct parent'} guidance preserves a child timer wait and its queued messages',
      () async {
        final leader = await create('Leader');
        final parent = await create('Parent', parent: leader.id);
        final child = await create('Child', parent: parent.id);
        final sender = fromMain ? leader : parent;
        final timer = await timerTool(child, 'start_timer', {
          'duration_seconds': 60,
          'objective': 'Discuss',
        });
        requestTimerWait(timer['timer_id'] as String);
        final operation = child.assistant.sendMessage('Original premise');
        await waitUntil(() => requests.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final queued = await timerTool(sender, 'send_agent_message', {
          'agent_id': child.id,
          'message': 'Keep this supplement',
        });
        expect(queued['delivery_status'], 'queued');
        expect(requests, hasLength(1));
        final guided = await timerTool(sender, 'send_agent_message', {
          'agent_id': child.id,
          'message': 'Correct the premise now',
          'mode': 'guide',
        });
        expect(guided['mode'], 'guide');
        expect(guided['reply_completed'], isFalse);
        expect(guided['delivery_status'], 'queued');
        expect(child.assistant.busy, isTrue);
        expect(requests, hasLength(1));
        final beforeDeadline = await timerTool(child, 'get_timer');
        expect(beforeDeadline['status'], 'running');
        expect(beforeDeadline['deadline'], timer['deadline']);
        now = now.add(const Duration(seconds: 60));
        await timerTool(child, 'get_timer');
        await operation;
        await waitUntil(() => !child.assistant.busy);
        expect(requests, hasLength(3));
        expect(
          jsonEncode(requests[1]['messages']),
          contains('Correct the premise now'),
        );
        expect(jsonEncode(requests[1]['messages']), contains(sender.id));
        expect(
          jsonEncode(requests.last['messages']),
          contains('Keep this supplement'),
        );
        expect(child.assistant.pendingGuidance, isEmpty);
        final afterGuidance = await timerTool(child, 'get_timer');
        expect(afterGuidance['status'], 'expired');
        expect(afterGuidance['deadline'], timer['deadline']);
      },
    );
  }

  test(
    'model timer wait blocks early final output and wakes exactly at deadline',
    () async {
      final leader = await create('Leader');
      final started = await timerTool(leader, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Discuss',
      });
      requestTimerWait(started['timer_id'] as String);
      final operation = leader.assistant.sendMessage('Discuss for one minute');
      await waitUntil(() => requests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(leader.assistant.busy, isTrue);
      expect(leader.result, isEmpty);
      expect(requests, hasLength(1));
      now = now.add(const Duration(seconds: 59));
      await timerTool(leader, 'get_timer');
      expect(leader.result, isEmpty);
      now = now.add(const Duration(seconds: 1));
      await timerTool(leader, 'get_timer');
      await operation;
      expect(leader.result, 'Done');
      expect(requests, hasLength(2));
      expect(leader.assistant.pendingGuidance, isEmpty);
      expect(
        leader.assistant.messages.where((message) => message.role == 'user'),
        hasLength(1),
      );
    },
  );

  for (final entry in ['canvas', 'chat', 'all', 'at-deadline']) {
    test(
      '$entry stopping during a model timer wait releases it without a follow-up request',
      () async {
        final leader = await create('Leader');
        final started = await timerTool(leader, 'start_timer', {
          'duration_seconds': 60,
          'objective': 'Discuss',
        });
        requestTimerWait(started['timer_id'] as String);
        final operation = leader.assistant.sendMessage(
          'Discuss for one minute',
        );
        await waitUntil(() => requests.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        switch (entry) {
          case 'canvas':
            workspace.stop(leader.id);
          case 'chat':
            leader.assistant.stopGeneration();
          case 'all':
            workspace.stopAll();
          case 'at-deadline':
            now = now.add(const Duration(minutes: 1));
            final expiry = timerTool(leader, 'get_timer');
            workspace.stop(leader.id);
            expect((await expiry)['status'], 'expired');
        }
        await operation;
        now = now.add(const Duration(minutes: 2));
        expect(
          (await timerTool(leader, 'get_timer'))['status'],
          entry == 'at-deadline' ? 'expired' : 'cancelled',
        );
        expect(leader.assistant.busy, isFalse);
        expect(requests, hasLength(1));
      },
    );
  }

  test('a detached child keeps its own pending wait and deadline', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    final started = await timerTool(child, 'start_timer', {
      'duration_seconds': 60,
      'objective': 'Discuss',
    });
    final detachedWait = timerTool(child, 'wait_timer', {
      'timer_id': started['timer_id'],
    });
    workspace.promoteToRoot(child.id);
    expect(
      (await timerTool(child, 'get_timer'))['deadline'],
      started['deadline'],
    );
    now = now.add(const Duration(minutes: 1));
    expect((await timerTool(child, 'get_timer'))['status'], 'expired');
    expect((await detachedWait)['status'], 'expired');
    expect(child.assistant.messages, isEmpty);
    expect(requests, isEmpty);
  });

  test(
    'timer is private to its owner and repeated starts keep the deadline',
    () async {
      final leader = await create('Leader');
      final child = await create('Child', parent: leader.id);
      final started = await timerTool(leader, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Discuss design',
      });
      expect(started['remaining_seconds'], 60);
      expect(started['owner_id'], leader.id);
      now = now.add(const Duration(seconds: 20));
      final duplicate = await timerTool(leader, 'start_timer', {
        'duration_seconds': 100,
        'objective': 'Different',
      });
      expect(duplicate['timer_id'], started['timer_id']);
      expect(duplicate['remaining_seconds'], 40);
      expect(duplicate['objective'], 'Discuss design');
      await expectLater(timerTool(child, 'get_timer'), throwsStateError);
      final childTimer = await timerTool(child, 'start_timer', {
        'duration_seconds': 30,
        'objective': 'Child-only objective',
      });
      for (final name in ['get_timer', 'wait_timer', 'cancel_timer']) {
        await expectLater(
          timerTool(child, name, {'timer_id': started['timer_id']}),
          throwsStateError,
        );
        await expectLater(
          timerTool(leader, name, {'timer_id': childTimer['timer_id']}),
          throwsStateError,
        );
      }
      expect((await timerTool(child, 'get_timer'))['remaining_seconds'], 30);
      expect(requests, isEmpty);
      await leader.assistant.sendMessage('Continue timed discussion');
      expect(jsonEncode(requests.last['messages']), contains('active_timers'));
      expect(
        jsonEncode(requests.last['messages']),
        isNot(contains('Child-only objective')),
      );
      expect(
        jsonEncode(requests.last['messages']),
        contains('remaining_seconds'),
      );
    },
  );

  test('main and child waits complete at their distinct deadlines', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    final started = await timerTool(leader, 'start_timer', {
      'duration_seconds': 60,
      'objective': 'Discuss',
    });
    var finished = false;
    final waiting =
        timerTool(leader, 'wait_timer', {'timer_id': started['timer_id']}).then(
          (result) {
            finished = true;
            return result;
          },
        );
    final childTimer = await timerTool(child, 'start_timer', {
      'duration_seconds': 90,
      'objective': 'Work independently',
    });
    var childFinished = false;
    final childWait =
        timerTool(child, 'wait_timer', {
          'timer_id': childTimer['timer_id'],
        }).then((result) {
          childFinished = true;
          return result;
        });
    now = now.add(const Duration(seconds: 59));
    expect((await timerTool(leader, 'get_timer'))['status'], 'running');
    expect(finished, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect((await timerTool(leader, 'get_timer'))['status'], 'expired');
    expect((await waiting)['remaining_seconds'], 0);
    expect(childFinished, isFalse);
    now = now.add(const Duration(seconds: 30));
    expect((await timerTool(child, 'get_timer'))['status'], 'expired');
    expect((await childWait)['status'], 'expired');
    expect(requests, isEmpty);
    expect(child.assistant.messages, isEmpty);
  });

  test(
    'timer cancellation releases waits and stop all prevents later wakeup',
    () async {
      final leader = await create('Leader');
      final started = await timerTool(leader, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Discuss',
      });
      final waiting = timerTool(leader, 'wait_timer', {
        'timer_id': started['timer_id'],
      });
      await timerTool(leader, 'cancel_timer', {
        'timer_id': started['timer_id'],
      });
      expect((await waiting)['status'], 'cancelled');
      now = now.add(const Duration(minutes: 1));
      expect((await timerTool(leader, 'get_timer'))['status'], 'cancelled');
      final second = await timerTool(leader, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Again',
      });
      workspace.stopAll();
      now = now.add(const Duration(minutes: 2));
      expect(
        (await timerTool(leader, 'get_timer', {
          'timer_id': second['timer_id'],
        }))['status'],
        'cancelled',
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'changing the workflow main and undoing it leave personal timers intact',
    () async {
      final leader = await create('Leader');
      final successor = await create('Successor', parent: leader.id);
      final leaderTimer = await timerTool(leader, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Discuss',
      });
      final successorTimer = await timerTool(successor, 'start_timer', {
        'duration_seconds': 90,
        'objective': 'Review',
      });
      final before = workspace.captureTopologyEdit();
      expect(workspace.makeWorkflowMain(successor.id), isTrue);
      final after = workspace.captureTopologyEdit();
      expect(
        (await timerTool(successor, 'get_timer'))['timer_id'],
        successorTimer['timer_id'],
      );
      await expectLater(
        timerTool(successor, 'cancel_timer', {
          'timer_id': leaderTimer['timer_id'],
        }),
        throwsStateError,
      );
      await workspace.restoreTopologyEdit(before, previous: after);
      expect(
        (await timerTool(leader, 'get_timer'))['deadline'],
        leaderTimer['deadline'],
      );
      expect(
        (await timerTool(successor, 'get_timer'))['deadline'],
        successorTimer['deadline'],
      );
    },
  );

  test('stopping one agent cancels only its own timer', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    for (final agent in [leader, child]) {
      await timerTool(agent, 'start_timer', {
        'duration_seconds': 60,
        'objective': 'Work independently',
      });
    }
    workspace.stop(child.id);
    expect((await timerTool(child, 'get_timer'))['status'], 'cancelled');
    expect((await timerTool(leader, 'get_timer'))['status'], 'running');
    await timerTool(child, 'start_timer', {
      'duration_seconds': 90,
      'objective': 'Resume work',
    });
    workspace.stop(leader.id);
    expect((await timerTool(leader, 'get_timer'))['status'], 'cancelled');
    expect((await timerTool(child, 'get_timer'))['status'], 'running');
    workspace.stopAll();
    expect((await timerTool(child, 'get_timer'))['status'], 'cancelled');
  });

  test('restarted timer expires without automatic model requests', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    await timerTool(child, 'start_timer', {
      'duration_seconds': 60,
      'objective': 'Discuss',
    });
    await workspace.flush();
    workspace.dispose();
    now = now.add(const Duration(minutes: 2));
    workspace = AiWorkspaceProvider(scope.provider, clock: () => now);
    await workspace.initialized;
    final restored = workspace.find(child.id)!;
    final result = await timerTool(restored, 'get_timer');
    expect(result['status'], 'expired');
    expect(result['recovered_after_restart'], true);
    expect(requests, isEmpty);
    expect(restored.assistant.messages, isEmpty);
    await expectLater(
      timerTool(workspace.find(leader.id)!, 'get_timer'),
      throwsStateError,
    );
  });

  test('old shared timer storage is not restored as personal timers', () async {
    final leader = await create('Leader');
    final child = await create('Child', parent: leader.id);
    scope.provider.workspacePreferences.setValue(
      'ai.timers.v1',
      jsonEncode([
        {
          'timer_id': 'legacy-shared',
          'owner_id': leader.id,
          'participant_ids': [leader.id, child.id],
          'objective': 'Old group timer',
          'started_at': now.toIso8601String(),
          'deadline': now.add(const Duration(minutes: 1)).toIso8601String(),
          'status': 'running',
        },
      ]),
    );
    await workspace.flush();
    workspace.dispose();
    workspace = AiWorkspaceProvider(scope.provider, clock: () => now);
    await workspace.initialized;
    for (final id in [leader.id, child.id]) {
      await expectLater(
        timerTool(workspace.find(id)!, 'get_timer'),
        throwsStateError,
      );
    }
    expect(requests, isEmpty);
  });

  test(
    'restore ignores obsolete queued events without removing chat history',
    () async {
      final leader = await create('Leader');
      final leadershipEvent = jsonEncode({'event': 'agent_leadership_update'});
      leader.assistant.restoreWorkspaceConversation({
        ...leader.assistant.snapshotWorkspaceConversation(),
        'history': [
          {'role': 'user', 'content': 'Existing message'},
        ],
        'pendingWorkspaceEvents': [
          jsonEncode({'event': 'timer_expired'}),
          leadershipEvent,
        ],
      });
      final restored = leader.assistant.snapshotWorkspaceConversation();
      expect(restored, isNot(contains('pendingWorkspaceEvents')));
      expect(restored['history'], [
        {'role': 'user', 'content': 'Existing message'},
      ]);
    },
  );

  test(
    'topology includes the merged workflow and separates triangle peer edges',
    () async {
      final leader = await create('A');
      final child = await create('B', parent: leader.id);
      final successor = await create('C', parent: leader.id);
      final outside = await create('Outside');
      final hidden = await create('Hidden', parent: outside.id);
      workspace.connectTasks(child.id, successor.id);
      workspace.connectTasks(child.id, outside.id);
      final graph = await topology(child);
      expect(graph['primary_agent_id'], leader.id);
      expect(
        graph['scope_agent_ids'],
        unorderedEquals([
          leader.id,
          child.id,
          successor.id,
          outside.id,
          hidden.id,
        ]),
      );
      expect(graph['management_edges'], hasLength(4));
      expect(graph['communication_edges'], hasLength(5));
      expect(
        (graph['nodes'] as List).where(
          (node) => (node as Map)['agent_id'] == hidden.id,
        ),
        hasLength(1),
      );
    },
  );

  test('manual main change preserves a triangle and survives export', () async {
    final leader = await create('A');
    final child = await create('B', parent: leader.id);
    final successor = await create('C', parent: leader.id);
    final grandchild = await create('D', parent: child.id);
    workspace.connectTasks(child.id, successor.id);
    expect(workspace.makeWorkflowMain(successor.id), isTrue);
    expect(leader.parentId, successor.id);
    expect(child.parentId, leader.id);
    expect(grandchild.parentId, child.id);
    expect(successor.parentId, isNull);
    expect(successor.kind, AiWorkspaceKind.primary);
    expect(leader.kind, AiWorkspaceKind.permanent);
    expect(workspace.connections, hasLength(4));
    expect(workspace.isConnected(leader.id, child.id), isTrue);
    expect(requests, isEmpty);
    final exported = workspace.exportData();
    final mapping = await workspace.importData(exported);
    expect(workspace.find(mapping[leader.id])!.parentId, mapping[successor.id]);
    expect(workspace.find(mapping[child.id])!.parentId, mapping[leader.id]);
    expect(
      workspace.isConnected(mapping[child.id]!, mapping[successor.id]!),
      isTrue,
    );
  });

  test(
    'a deep manual main change is undoable without affecting other branches',
    () async {
      final leader = await create('A');
      final child = await create('B', parent: leader.id);
      final successor = await create('C', parent: child.id);
      final branch = await create('Branch', parent: leader.id);
      final outside = await create('Outside');
      final assistant = successor.assistant;
      List<String> linkPairs() => [
        for (final edge in workspace.connections)
          ([edge.fromId, edge.toId]..sort()).join(':'),
      ];
      final links = linkPairs();
      final before = workspace.captureTopologyEdit();
      expect(workspace.makeWorkflowMain(successor.id), isTrue);
      final after = workspace.captureTopologyEdit();
      expect(child.parentId, successor.id);
      expect(leader.parentId, child.id);
      expect(branch.parentId, leader.id);
      expect(outside.kind, AiWorkspaceKind.primary);
      expect(linkPairs(), unorderedEquals(links));
      await workspace.restoreTopologyEdit(before, previous: after);
      expect(leader.parentId, isNull);
      expect(child.parentId, leader.id);
      expect(successor.parentId, child.id);
      await workspace.restoreTopologyEdit(after, previous: before);
      expect(successor.parentId, isNull);
      expect(leader.parentId, child.id);
      expect(successor.assistant, same(assistant));
    },
  );

  test('missing, closed and already-main agents are not eligible', () async {
    final leader = await create('A');
    final child = await create('B', parent: leader.id);
    child.closed = true;
    for (final id in ['missing-agent', leader.id, child.id]) {
      expect(workspace.canMakeWorkflowMain(id), isFalse);
      expect(workspace.makeWorkflowMain(id), isFalse);
    }
    expect(leader.parentId, isNull);
    expect(child.parentId, leader.id);
  });

  test('AI cannot request or undo a change of the workflow main', () async {
    final leader = await create('A');
    final child = await create('B', parent: leader.id);
    final graph = await topology(leader);
    expect(graph, isNot(contains('undo_transfer_id')));
    for (final caller in [leader, child]) {
      for (final name in ['transfer_leadership', 'undo_leadership_transfer']) {
        expect(
          jsonEncode(caller.assistant.workspaceToolDefinitions),
          isNot(contains(name)),
        );
        await expectLater(
          caller.assistant.workspaceToolHandler!(name, {
            'agent_id': child.id,
            'expected_revision': graph['revision'],
            'summary': 'Work',
            'transfer_id': 'obsolete',
          }),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Unknown workspace tool',
            ),
          ),
        );
      }
      expect(caller.assistant.pendingApproval, isNull);
    }
    expect(leader.parentId, isNull);
    expect(child.parentId, leader.id);
  });

  test('cycles retain one main and its managed children', () async {
    expect(AiWorkspaceKind.values, [
      AiWorkspaceKind.primary,
      AiWorkspaceKind.permanent,
    ]);
    final first = await create('A');
    final second = await create('B');
    final third = await create('C');
    workspace.connectTasks(first.id, second.id);
    workspace.connectTasks(second.id, third.id);
    workspace.connectTasks(third.id, first.id);
    expect(workspace.primaries, [first]);
    expect([second.parentId, third.parentId], [first.id, second.id]);
    await first.assistant.workspaceToolHandler!('stop_agent', {
      'agent_id': third.id,
    });
    await first.assistant.workspaceToolHandler!('delete_agent', {
      'agent_id': second.id,
    });
    expect(third.parentId, first.id);
    expect(workspace.primaries, [first]);
  });

  test(
    'main and child roles survive import reload export copy and recycle',
    () async {
      final root = await create('Root');
      final child = await create('Child', parent: root.id);
      final peer = await create('Peer');
      workspace.connectTasks(child.id, peer.id);
      await child.assistant.sendMessage('Retain history');
      final exported = workspace.exportData();
      final mapping = await workspace.importData(exported);
      final importedRoot = workspace.find(mapping[root.id])!;
      final importedChild = workspace.find(mapping[child.id])!;
      expect(importedRoot.kind, AiWorkspaceKind.primary);
      expect(importedChild.kind, AiWorkspaceKind.permanent);
      expect(importedChild.parentId, importedRoot.id);
      expect(
        workspace.isConnected(importedChild.id, mapping[peer.id]!),
        isTrue,
      );
      expect(importedChild.assistant.messages, isNotEmpty);
      expect(
        ((workspace.exportData(agentId: importedChild.id)['sessions'] as List)
                .single
            as Map)['kind'],
        'primary',
      );
      final copy = await workspace.duplicate(importedChild.id, title: 'Copy');
      expect(copy.kind, AiWorkspaceKind.permanent);
      workspace.remove(importedChild.id);
      await workspace.restoreRecycledAgent(importedChild.id);
      expect(workspace.find(importedChild.id)!.kind, AiWorkspaceKind.permanent);
      await workspace.flush();
      workspace.dispose();
      await storage.saveWorkflow(exported);
      workspace = AiWorkspaceProvider(scope.provider);
      await workspace.initialized;
      expect(workspace.persistenceError, isNull);
      expect(workspace.find(root.id)!.kind, AiWorkspaceKind.primary);
      expect(workspace.find(child.id)!.kind, AiWorkspaceKind.permanent);
      expect(workspace.isConnected(child.id, peer.id), isTrue);
      expect(
        (workspace.exportData()['sessions'] as List).map((raw) => raw['kind']),
        everyElement(isIn(['primary', 'permanent'])),
      );
    },
  );

  test('recycled child retains its role and parent after restart', () async {
    final root = await create('Root');
    final child = await create('Child', parent: root.id);
    workspace.remove(child.id);
    await workspace.flush();
    workspace.dispose();
    workspace = AiWorkspaceProvider(scope.provider);
    await workspace.initialized;
    expect(workspace.recycledAgents.single.record['kind'], 'permanent');
    await workspace.restoreRecycledAgent(child.id);
    expect(workspace.find(child.id)!.kind, AiWorkspaceKind.permanent);
    expect(workspace.find(child.id)!.parentId, root.id);
  });

  test('relationship notifications follow role changes without starting generation', () async {
    final root = await create('Root');
    final child = await create('Child', parent: root.id);
    expect(requests, isEmpty);
    await child.assistant.sendMessage('First');
    expect(updates().last['role'], 'child');
    await child.assistant.sendMessage('Unchanged');
    expect(updates(), hasLength(1));
    final count = requests.length;
    workspace.promoteToRoot(child.id);
    expect(requests, hasLength(count));
    await child.assistant.sendMessage('Promoted');
    expect(updates().last['role'], 'primary');
    workspace.reparent(child.id, root.id);
    await child.assistant.sendMessage('Rejoined');
    expect(updates(), hasLength(3));
    expect(updates().last['role'], 'child');
    for (var index = 0; index < 8; index++) {
      await child.assistant.sendMessage('History $index');
    }
    await child.assistant.compactContext();
    await child.assistant.sendMessage('Compacted');
    expect(updates().last['role'], 'child');
    expect(updates().last['primary_agent_id'], root.id);
  });
}
