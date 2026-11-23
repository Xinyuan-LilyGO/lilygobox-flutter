import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/memory_conflict.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> waitForStorage(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Background storage maintenance did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('storage usage reuses reads until a write or manual refresh', () async {
    final store = AgentStorage(path: ':memory:');
    addTearDown(store.close);
    final first = store.readStats();
    expect(store.readStats(), same(first));
    expect((await first)['memories'], 0);
    await store.memories('owner');
    expect(store.readStats(), same(first));
    await store.putMemory(id: 'first', owner: 'owner', content: 'Test');
    final updated = store.readStats();
    expect((await updated)['memories'], 1);
    final manual = store.readStats(force: true);
    expect(manual, isNot(same(updated)));
    await manual;
    await store.deleteMemory('first');
    expect((await store.readStats())['memories'], 0);
  });

  test(
    'complete memory IDs take precedence over content and remain owner-scoped',
    () async {
      final store = AgentStorage(path: ':memory:');
      addTearDown(store.close);
      const id = '0123456789abcdef0123456789abcdef';
      await store.putMemory(id: id, owner: 'agent-a', content: 'Exact memory');
      await store.putMemory(
        id: 'other',
        owner: 'agent-a',
        content: 'Reference $id',
      );
      await store.putMemory(
        id: 'foreign',
        owner: 'agent-b',
        content: 'Reference $id',
      );

      expect(
        (await store.memories('agent-a', query: ' $id ')).single['id'],
        id,
      );
      expect(await store.memories('agent-b', query: id), isEmpty);
      expect(await store.memories('agent-a', query: id, offset: 1), isEmpty);
      expect(
        (await store.memories('agent-b', query: 'Reference')).single['id'],
        'foreign',
      );
    },
  );

  test(
    'automatic memory batches append scoped deduplicated facts and source turn',
    () async {
      final store = AgentStorage(path: ':memory:');
      addTearDown(store.close);
      await store.putMemory(
        id: 'manual',
        owner: 'agent-a',
        content: 'Existing fact',
        source: 'manual',
      );
      final result = await store.saveAutoMemories(
        owner: 'agent-a',
        turnId: 'turn-1',
        candidates: [
          'Existing fact',
          'New fact\r\nsecond line',
          ' New fact\nsecond line ',
          '  ',
        ],
      );
      expect(result, {'added': 1, 'skipped': 3});
      final rows = await store.memories('agent-a');
      expect(rows, hasLength(2));
      final manual = rows.singleWhere((r) => r['id'] == 'manual');
      expect(manual['source'], 'manual');
      expect(manual['revision'], 1);
      final automatic = rows.singleWhere((r) => r['id'] != 'manual');
      expect(automatic['content'], 'New fact\nsecond line');
      expect(jsonDecode(automatic['source'] as String), {
        'automatic': true,
        'turnId': 'turn-1',
      });
      expect(
        await store.saveAutoMemories(
          owner: 'agent-a',
          turnId: 'turn-2',
          candidates: ['New fact\nsecond line'],
        ),
        {'added': 0, 'skipped': 1},
      );
      expect(
        await store.saveAutoMemories(
          owner: 'agent-b',
          turnId: 'turn-3',
          candidates: ['New fact\nsecond line'],
        ),
        {'added': 1, 'skipped': 0},
      );
      expect(
        await store.request('exportSnapshot'),
        isNot(contains('versions')),
      );
      expect(await store.memories('agent-a', query: 'second'), hasLength(1));
    },
  );

  test(
    'invalid automatic memory batch rolls back every candidate and search row',
    () async {
      final store = AgentStorage(path: ':memory:');
      addTearDown(store.close);
      await expectLater(
        store.request('saveAutoMemories', {
          'owner': 'agent',
          'turnId': 'turn',
          'candidates': ['Should roll back', 42],
        }),
        throwsStateError,
      );
      expect(await store.memories('agent'), isEmpty);
      expect(await store.memories('agent', query: 'rollback'), isEmpty);
      expect(await store.request('allMemories'), isEmpty);
      await expectLater(
        store.saveAutoMemories(
          owner: 'agent',
          turnId: 'turn',
          candidates: List.filled(33, 'fact'),
        ),
        throwsStateError,
      );
      await expectLater(
        store.saveAutoMemories(
          owner: 'agent',
          turnId: 'turn',
          candidates: ['x' * 16385],
        ),
        throwsStateError,
      );
      expect(await store.memories('agent'), isEmpty);
      expect(
        await store.saveAutoMemories(
          owner: 'agent',
          turnId: 'valid',
          candidates: ['Valid fact'],
        ),
        {'added': 1, 'skipped': 0},
      );
    },
  );

  test(
    'idle maintenance removes orphans but retains recycle and current memories',
    () async {
      final dir = await Directory.systemTemp.createTemp('storage-idle-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(
        path: path,
        maintenanceIdleDelay: const Duration(milliseconds: 80),
        maintenanceMaxDelay: const Duration(milliseconds: 400),
        maintenanceInterval: const Duration(milliseconds: 40),
      );
      addTearDown(store.close);
      await store.saveWorkflow({'old': 'orphan body ' * 100});
      final data = {
        'sessions': [
          {
            'id': 'active',
            'conversation': {
              'messages': ['live body ' * 100],
            },
          },
        ],
        'recycleBin': [
          {
            'id': 'recycled',
            'conversation': {
              'messages': ['recycled body ' * 100],
            },
          },
        ],
      };
      await store.saveWorkflow(data);
      await store.putMemory(
        id: 'memory',
        owner: 'recycled',
        content: 'old memory',
      );
      await store.putMemory(
        id: 'memory',
        owner: 'recycled',
        content: 'new memory',
      );
      final check = sqlite3.open(path);
      addTearDown(check.close);
      check.execute(
        "INSERT INTO objects VALUES('small-orphan', randomblob(65536))",
      );
      await store.saveWorkflow(data);
      await waitForStorage(
        () =>
            check.select('SELECT COUNT(*) AS n FROM objects').single['n'] == 2,
      );
      expect(await store.request('readWorkflowData'), data);
      expect(
        (await store.memories('recycled')).single['content'],
        'new memory',
      );
      expect(
        check.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_versions'",
        ),
        isEmpty,
      );
      // Small reusable pages stay available instead of rewriting the database.
      expect(
        check.select('PRAGMA freelist_count').single.values.single,
        greaterThan(0),
      );
    },
  );

  test(
    'continuous writes cannot postpone orphan collection indefinitely',
    () async {
      final dir = await Directory.systemTemp.createTemp('storage-stream-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(
        path: path,
        maintenanceIdleDelay: const Duration(seconds: 2),
        maintenanceMaxDelay: const Duration(milliseconds: 150),
        maintenanceInterval: const Duration(milliseconds: 40),
      );
      addTearDown(store.close);
      await store.saveWorkflow({'obsolete': 'streaming orphan ' * 100});
      final check = sqlite3.open(path);
      addTearDown(check.close);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var writes = 0;
      do {
        await store.saveWorkflow({'current': ++writes});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } while (check.select('SELECT COUNT(*) AS n FROM objects').single['n'] !=
              0 &&
          DateTime.now().isBefore(deadline));
      expect(check.select('SELECT COUNT(*) AS n FROM objects').single['n'], 0);
      expect(writes, greaterThan(1));
      expect(await store.request('readWorkflowData'), {'current': writes});
    },
  );

  test(
    'automatic vacuum reclaims substantial free space only when idle',
    () async {
      final dir = await Directory.systemTemp.createTemp('storage-vacuum-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(
        path: path,
        maintenanceIdleDelay: const Duration(milliseconds: 100),
        maintenanceMaxDelay: const Duration(seconds: 1),
        maintenanceInterval: const Duration(milliseconds: 40),
      );
      addTearDown(store.close);
      await store.saveWorkflow({'keep': 'saved workflow'});
      final check = sqlite3.open(path);
      addTearDown(check.close);
      check.execute(
        "INSERT INTO objects VALUES('orphan', randomblob(10485760))",
      );
      await store.saveWorkflow({'keep': 'saved workflow'});
      final before = File(path).lengthSync();
      expect(before, greaterThan(8 * 1024 * 1024));
      await waitForStorage(() => File(path).lengthSync() < before ~/ 2);
      expect(check.select('SELECT hash FROM objects'), isEmpty);
      expect(await store.request('readWorkflowData'), {
        'keep': 'saved workflow',
      });
    },
  );

  test(
    'maintenance errors retry without terminating the storage worker',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'storage-maintenance-error-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(
        path: path,
        maintenanceIdleDelay: const Duration(milliseconds: 30),
        maintenanceMaxDelay: const Duration(milliseconds: 100),
        maintenanceInterval: const Duration(milliseconds: 40),
      );
      addTearDown(store.close);
      await store.saveWorkflow({'orphan': 'retry body ' * 100});
      await store.saveWorkflow({'keep': true});
      final check = sqlite3.open(path);
      addTearDown(check.close);
      check.execute("INSERT INTO state VALUES('broken', 'not JSON')");
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(check.select('SELECT hash FROM objects'), isNotEmpty);
      await store.putMemory(
        id: 'after-error',
        owner: 'agent',
        content: 'still works',
      );
      expect((await store.memories('agent')).single['content'], 'still works');
      check.execute("DELETE FROM state WHERE key='broken'");
      await waitForStorage(
        () => check.select('SELECT hash FROM objects').isEmpty,
      );
      expect(await store.request('readWorkflowData'), {'keep': true});
    },
  );

  test(
    'manual clean reports actual reclaimed bytes and preserves live data',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'storage-clean-result-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(path: path);
      addTearDown(store.close);
      final recycledRecord = {
        'id': 'agent',
        'conversation': {
          'messages': ['recycled chat content ' * 100],
        },
      };
      await store.saveWorkflow({
        'keep': 'live content ' * 100,
        'recycleBin': [
          {'record': jsonEncode(recycledRecord)},
        ],
      });
      await store.putMemory(
        id: 'memory',
        owner: 'agent',
        content: 'first version',
      );
      await store.putMemory(
        id: 'memory',
        owner: 'agent',
        content: 'second version',
      );
      final check = sqlite3.open(path);
      addTearDown(check.close);
      check.execute(
        "INSERT INTO objects VALUES('orphan', randomblob(1048576))",
      );
      int bytes() => [File(path), File('$path-wal')]
          .where((file) => file.existsSync())
          .fold(0, (sum, file) => sum + file.lengthSync());
      final before = bytes();
      final result = await store.request('clean') as Map;
      expect(result['objectsRemoved'], 1);
      expect(result['bytesFreed'], before - bytes());
      expect(result['bytesFreed'], greaterThan(0));
      expect(await store.request('readWorkflowData'), {
        'keep': 'live content ' * 100,
        'recycleBin': [
          {'record': recycledRecord},
        ],
      });
      expect(
        (await store.memories('agent')).single['content'],
        'second version',
      );
      expect(await store.request('clean'), {
        'objectsRemoved': 0,
        'bytesFreed': 0,
      });
    },
  );

  test(
    'closing cancels pending maintenance and next startup reclaims leftovers',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'storage-maintenance-close-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/main.db';
      final store = AgentStorage(path: path);
      await store.saveWorkflow({'old': 'closed orphan ' * 100});
      await store.saveWorkflow({'keep': true});
      await store.close();
      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(check.select('SELECT hash FROM objects'), isNotEmpty);
      final reopened = AgentStorage(
        path: path,
        maintenanceIdleDelay: const Duration(milliseconds: 30),
        maintenanceMaxDelay: const Duration(milliseconds: 100),
      );
      addTearDown(reopened.close);
      await reopened.ready;
      await waitForStorage(
        () => check.select('SELECT hash FROM objects').isEmpty,
      );
      expect(await reopened.request('readWorkflowData'), {'keep': true});
    },
  );
  test('agent memories stay isolated and global writes are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('agent-memory-scopes-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/main.db';
    final store = AgentStorage(path: path);
    await store.putMemory(
      id: 'a',
      owner: 'agent-a',
      content: 'purple preference',
    );
    await store.putMemory(
      id: 'b',
      owner: 'agent-b',
      content: 'blue preference',
    );
    expect(
      (await store.memories('agent-a', query: 'preference')).single['id'],
      'a',
    );
    expect((await store.memories('agent-b')).single['id'], 'b');
    await expectLater(
      store.putMemory(
        id: 'invalid',
        owner: 'global',
        content: 'shared preference',
      ),
      throwsStateError,
    );
    await store.close();
    final reopened = AgentStorage(path: path);
    expect(await reopened.request('allMemories'), hasLength(2));
    expect((await reopened.memories('agent-a')).single['id'], 'a');
    expect((await reopened.memories('agent-b')).single['id'], 'b');
    await reopened.close();
  });

  test('SQLite preserves large complete workflow and current memory across restart', () async {
    final dir = await Directory.systemTemp.createTemp('agent-storage-test-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/main.db';
    final store = AgentStorage(path: path);
    final content = List.filled(110000, '长').join();
    final source = jsonEncode({
      'messages': [
        for (var i = 0; i < 230; i++) {'id': i, 'content': content},
      ],
    });
    await store.saveWorkflow(source);
    expect(jsonDecode((await store.readWorkflow())!), jsonDecode(source));
    await store.putMemory(id: 'a', owner: 'agent', content: '界面使用实心图标');
    await store.putMemory(id: 'a', owner: 'agent', content: '界面统一使用实心图标');
    final found = await store.memories('agent', query: '图标');
    expect(found.single['revision'], 2);
    expect(found.single['hash'], memoryContentHash('界面统一使用实心图标'));
    final stats = await store.request('stats') as Map;
    final breakdown = stats['breakdown'] as Map;
    expect(breakdown['objects'], greaterThan(0));
    expect(breakdown['state'], greaterThan(0));
    expect(breakdown['memories'], utf8.encode('界面统一使用实心图标').length);
    expect(breakdown.containsKey('versions'), isFalse);
    expect(
      breakdown.values.cast<int>().fold<int>(0, (sum, size) => sum + size),
      lessThanOrEqualTo(stats['bytes'] as int),
    );
    await store.close();
    final reopened = AgentStorage(path: path);
    expect((await reopened.memories('agent')).single['content'], '界面统一使用实心图标');
    expect(await reopened.readWorkflow(), isNotNull);
    await reopened.close();
  });
  test('storage overview separates chat, context and workflow without double counting', () async {
    final dir = await Directory.systemTemp.createTemp('storage-overview-');
    addTearDown(() => dir.delete(recursive: true));
    final store = AgentStorage(path: '${dir.path}/main.db');
    addTearDown(store.close);
    await store.saveWorkflow({
      'sessions': [
        {
          'id': 'agent-a',
          'conversation': {
            'messages': [
              {'content': 'A saved chat message'},
            ],
            'history': [
              {'content': 'A saved context message'},
            ],
            'summary': 'Context summary',
            'contextBudgetTokens': 32000,
          },
        },
      ],
    });
    final stats = await store.request('stats') as Map;
    final state = stats['stateBreakdown'] as Map;
    final parts = stats['breakdown'] as Map;
    expect(state['conversations'], greaterThan(0));
    expect(state['context'], greaterThan(0));
    expect(state['workflow'], greaterThan(0));
    expect(state['recycleBin'], 0);
    expect(
      state.values.cast<int>().fold<int>(0, (sum, size) => sum + size),
      parts['state'],
    );
  });
  test('storage overview counts card library objects only once', () async {
    final store = AgentStorage(path: ':memory:');
    addTearDown(store.close);
    final sharedText = '共享的角色描述 ' * 60;
    final chatText = 'Unrelated chat content ' * 60;
    final cardAvatar = 'Imported avatar data ' * 60;
    Map<String, Object?> workflow(List<Object?> library) => {
      'roleplayLibrary': library,
      'sessions': [
        {
          'id': 'agent',
          'conversation': {
            'messages': [
              {'content': sharedText},
              {'content': chatText},
            ],
          },
        },
      ],
    };
    await store.saveWorkflow(workflow([]));
    final empty = await store.readStats();
    final beforeState = empty['stateBreakdown'] as Map;
    final beforeParts = empty['breakdown'] as Map;
    expect(beforeState['roleplayLibrary'], 0);
    expect(beforeParts['roleplayObjects'], 0);

    final cards = [
      for (final name in ['角色一', '角色二'])
        {
          'card': {
            'name': name,
            'description': sharedText,
            'avatar': cardAvatar,
          },
        },
    ];
    await store.saveWorkflow(workflow(cards));
    final populated = await store.readStats();
    final state = populated['stateBreakdown'] as Map;
    final parts = populated['breakdown'] as Map;
    final conversationObjects = parts['objects'] as int;
    expect(state['roleplayLibrary'], greaterThan(0));
    expect(state['workflow'], beforeState['workflow']);
    expect(state['conversations'], beforeState['conversations']);
    expect(conversationObjects, inExclusiveRange(0, beforeParts['objects']));
    expect(parts['roleplayObjects'], greaterThan(0));
    expect(populated['objects'], 3);
    expect(
      state.values.cast<int>().fold<int>(0, (sum, size) => sum + size),
      parts['state'],
    );

    await store.saveWorkflow(workflow([cards.first]));
    final oneCard = await store.readStats();
    expect(
      (oneCard['breakdown'] as Map)['roleplayObjects'],
      parts['roleplayObjects'],
    );
    expect(
      (oneCard['stateBreakdown'] as Map)['roleplayLibrary'],
      lessThan(state['roleplayLibrary']),
    );

    await store.saveWorkflow(workflow([]));
    await store.request('clean');
    final cleared = await store.readStats();
    expect(cleared['stateBreakdown'], beforeState);
    expect(cleared['breakdown'], beforeParts);
  });
  test(
    'recycle bin payload is separate from workflow and counted once',
    () async {
      final dir = await Directory.systemTemp.createTemp('storage-recycle-');
      addTearDown(() => dir.delete(recursive: true));
      final store = AgentStorage(path: '${dir.path}/main.db');
      addTearDown(store.close);
      final workflow = <String, Object?>{
        'sessions': <Object?>[],
        'recycleBin': <Object?>[],
      };
      await store.saveWorkflow(workflow);
      final before = await store.request('stats') as Map;
      final beforeState = before['stateBreakdown'] as Map;
      expect(beforeState['recycleBin'], 0);
      await store.saveWorkflow({
        ...workflow,
        'recycleBin': [
          {
            'record': {
              'id': 'recycled-agent',
              'title': '已删除的智能体',
              'conversation': {'messages': <Object?>[]},
            },
            'deletedAt': '2026-11-16T12:00:00.000',
            'connections': <Object?>[],
          },
        ],
      });
      final stats = await store.request('stats') as Map;
      final state = stats['stateBreakdown'] as Map;
      expect(state['recycleBin'], greaterThan(0));
      expect(state['workflow'], beforeState['workflow']);
      expect(
        state.values.cast<int>().fold<int>(0, (sum, size) => sum + size),
        (stats['breakdown'] as Map)['state'],
      );
      await store.saveWorkflow(workflow);
      final cleared = await store.request('stats') as Map;
      expect((cleared['stateBreakdown'] as Map)['recycleBin'], 0);
      expect(
        (cleared['stateBreakdown'] as Map)['workflow'],
        beforeState['workflow'],
      );
    },
  );
  test(
    'encoded recycle snapshots preserve schema across updates and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'encoded-recycle-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/main.db';
      final store = AgentStorage(path: path);
      addTearDown(store.close);
      final record = {
        'id': 'recycled-agent',
        'title': 'Recycled agent',
        'conversation': {
          'messages': [
            {'content': 'Complete recycled history ' * 1000},
          ],
        },
      };
      final encoded = jsonEncode(record);
      Map<String, Object?> workflow(Object source, int position) => {
        'sessions': <Object?>[],
        'canvas': {
          'active': [position, position],
        },
        'recycleBin': [
          {
            'record': source,
            'deletedAt': '2026-11-16T12:00:00.000',
            'connections': <Object?>[],
          },
        ],
      };
      for (var position = 0; position < 3; position++) {
        await store.saveWorkflow(workflow(encoded, position));
        expect(
          await store.request('readWorkflowData'),
          workflow(record, position),
        );
      }
      final changed = {...record, 'title': 'Changed recycled agent'};
      await store.saveWorkflow(workflow(jsonEncode(changed), 4));
      expect(await store.request('readWorkflowData'), workflow(changed, 4));
      await store.saveWorkflow({'sessions': [], 'recycleBin': []});
      await store.saveWorkflow(workflow(encoded, 5));
      await store.close();
      final reopened = AgentStorage(path: path);
      addTearDown(reopened.close);
      expect(await reopened.request('readWorkflowData'), workflow(record, 5));
    },
  );
  test('failed import does not cache recycle objects rolled back by its transaction', () async {
    final store = AgentStorage(path: ':memory:');
    addTearDown(store.close);
    await store.saveWorkflow({'sessions': [], 'recycleBin': []});
    final record = {
      'id': 'recycled-agent',
      'conversation': {
        'messages': [
          {'content': 'New object in a rolled back transaction ' * 1000},
        ],
      },
    };
    final workflow = {
      'sessions': <Object?>[],
      'recycleBin': [
        {'record': jsonEncode(record)},
      ],
    };
    await expectLater(
      store.commitImport(workflow, [
        {'id': 'invalid', 'owner': 'global', 'content': 'Rejected memory'},
      ]),
      throwsStateError,
    );
    expect(await store.request('readWorkflowData'), {
      'sessions': [],
      'recycleBin': [],
    });
    await store.saveWorkflow(workflow);
    expect(await store.request('readWorkflowData'), {
      'sessions': [],
      'recycleBin': [
        {'record': record},
      ],
    });
  });
  test(
    'conversation codec retains attachments, tools, elapsed and timeline',
    () {
      final message = AiMessage(
        id: 'm',
        role: 'assistant',
        content: 'done',
        elapsed: const Duration(seconds: 12),
        status: AiResponseStatus.completed,
        attachments: [
          AiImageAttachment(
            name: 'image.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
          ),
        ],
        processEvents: [
          AiProcessEvent(
            type: AiProcessEventType.action,
            elapsed: const Duration(seconds: 2),
            operationId: 'op',
            action: AiProcessingStep(
              name: 'run_command',
              arguments: {'executable': 'echo'},
              succeeded: true,
              output: 'result',
            ),
          ),
        ],
      );
      final restored = ConversationCodec.read(
        jsonDecode(jsonEncode(ConversationCodec.message(message))) as Map,
      );
      expect(restored.elapsed, message.elapsed);
      expect(restored.attachments.single.bytes, [1, 2, 3]);
      expect(restored.processEvents.single.action!.output, 'result');
    },
  );
  test('7z packages roundtrip and corruption is rejected', () async {
    final dir = await Directory.systemTemp.createTemp('agent-package-test-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/data.7z';
    final data = {
      'type': 'memory',
      'memories': [
        {
          'id': 'a',
          'content': '记住使用实心图标',
          'owner': 'agent',
          'hash': memoryContentHash('记住使用实心图标'),
        },
      ],
    };
    await AgentPackage.write(path, data);
    expect(await AgentPackage.read(path), data);
    final bytes = await File(path).readAsBytes();
    bytes[0] = 0;
    await File(path).writeAsBytes(bytes);
    await expectLater(AgentPackage.read(path), throwsA(isA<FormatException>()));
  });
  test('import distinguishes identical data from diverged versions', () {
    final current = {
      'id': 'local',
      'lineage': 'original',
      'owner': 'target',
      'content': 'new local',
    };
    final plan = planMemoryImport(
      [
        {
          'id': 'a',
          'lineage': 'original',
          'owner': 'source',
          'content': 'new remote',
        },
        {'id': 'b', 'owner': 'source', 'content': 'new local'},
      ],
      [current],
      (_) => 'target',
    );
    expect(plan.first.conflict, isTrue);
    expect(plan.first.resolution, MemoryResolution.skip);
    expect(plan.last.duplicate, isTrue);
  });
}
