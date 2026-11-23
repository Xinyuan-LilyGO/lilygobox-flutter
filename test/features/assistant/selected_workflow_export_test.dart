import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/data/roleplay_card_importer.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/roleplay_card.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';

import 'assistant_test_scope.dart';

void main() {
  late Directory directory;
  late AgentStorage storage;
  late AssistantTestScope scope;
  late AiWorkspaceProvider workspaces;
  late AgentStorageController controller;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('selected-workflow-');
    storage = AgentStorage(path: '${directory.path}/main.db');
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
    );
    await scope.provider.initialized;
    await scope.provider.saveService(
      name: 'Fixture',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6.1-sol'],
      apiKey: 'fixture-private-key',
    );
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
    controller = AgentStorageController(workspaces);
  });

  tearDown(() async {
    controller.dispose();
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

  Future<AiAgentWorkspace> create(String title, {String? parent}) async {
    final session = await workspaces.create(
      title: title,
      task: 'Task for $title',
      kind: parent == null
          ? AiWorkspaceKind.primary
          : AiWorkspaceKind.permanent,
      parentId: parent,
      startImmediately: false,
    );
    session.assistant.restoreWorkspaceConversation({
      'messages': [
        ConversationCodec.message(
          AiMessage(
            id: 'message-${session.id}',
            role: 'user',
            content: 'Chat for $title',
          ),
        ),
      ],
      'history': [
        {'role': 'user', 'content': 'Context for $title'},
      ],
      'summary': 'Summary for $title',
    });
    await storage.putMemory(
      id: 'memory-${session.id}',
      owner: session.id,
      content: 'Remember $title',
    );
    return session;
  }

  test(
    'selected workflow exports only selected data and imports intact',
    () async {
      final root = await create('UNSELECTED ROOT SECRET');
      final first = await create('First selected', parent: root.id);
      final child = await create('Selected child', parent: first.id);
      final peer = await create('Selected peer', parent: root.id);
      final excluded = await create(
        'UNSELECTED CHILD SECRET',
        parent: first.id,
      );
      workspaces.connectTasks(child.id, peer.id);
      workspaces.connectTasks(peer.id, excluded.id);
      workspaces.updateCanvasPositions({
        root.id: [0, 0],
        first.id: [100, 100],
        child.id: [200, 200],
        peer.id: [300, 300],
        excluded.id: [400, 400],
      });
      final selected = {first.id, child.id, peer.id};
      final path = '${directory.path}/selection.7z';
      await controller.export(path, 'workflow', selectedIds: selected);
      final package = await controller.inspect(path);
      expect(package['type'], 'workflow');
      final serialized = jsonEncode(package);
      expect(serialized, isNot(contains('UNSELECTED ROOT SECRET')));
      expect(serialized, isNot(contains('UNSELECTED CHILD SECRET')));
      expect(serialized, isNot(contains(root.id)));
      expect(serialized, isNot(contains(excluded.id)));
      final workflow = package['workflow'] as Map;
      expect(workflow.containsKey('recycleBin'), isFalse);
      final records = (workflow['sessions'] as List).cast<Map>();
      expect(records.map((r) => r['id']).toSet(), selected);
      final firstRecord = records.singleWhere((r) => r['id'] == first.id);
      final childRecord = records.singleWhere((r) => r['id'] == child.id);
      final peerRecord = records.singleWhere((r) => r['id'] == peer.id);
      expect(firstRecord['kind'], 'primary');
      expect(firstRecord['parentId'], isNull);
      expect(peerRecord['kind'], 'permanent');
      expect(peerRecord['parentId'], child.id);
      expect(childRecord['parentId'], first.id);
      expect(childRecord['kind'], 'permanent');
      expect((workflow['canvas'] as Map).keys.toSet(), selected);
      expect(workflow['connections'], isEmpty);
      expect(
        (package['memories'] as List).map((m) => m['owner']).toSet(),
        selected,
      );
      final before = workspaces.sessions.length;
      await controller.import(package);
      final imported = workspaces.sessions.skip(before).toList();
      expect(imported, hasLength(3));
      final importedFirst = imported.singleWhere((s) => s.title == first.title);
      final importedChild = imported.singleWhere((s) => s.title == child.title);
      final importedPeer = imported.singleWhere((s) => s.title == peer.title);
      expect(importedFirst.parentId, isNull);
      expect(importedFirst.kind, AiWorkspaceKind.primary);
      expect(importedChild.parentId, importedFirst.id);
      expect(importedPeer.parentId, importedChild.id);
      expect(
        workspaces.connections.any(
          (e) =>
              e.isHierarchy &&
              e.fromId == importedChild.id &&
              e.toId == importedPeer.id,
        ),
        isTrue,
      );
      for (final session in imported) {
        expect(session.id, isNot(isIn(selected)));
        expect(
          session.assistant.messages.single.content,
          'Chat for ${session.title}',
        );
        final conversation = session.assistant.snapshotWorkspaceConversation();
        expect(
          (conversation['history'] as List).single['content'],
          'Context for ${session.title}',
        );
        expect(conversation['summary'], 'Summary for ${session.title}');
        expect(
          (await storage.memories(session.id)).single['content'],
          'Remember ${session.title}',
        );
      }
      expect(workspaces.canvasPositions[importedFirst.id], [100, 100]);
    },
  );

  test(
    'chat, agent and workflow packages include only their bound cards',
    () async {
      const rawCard =
          '{"name":"Shared card","description":"",'
          '"personality":"","scenario":"","first_mes":"Hi {{user}}!",'
          '"mes_example":""}\n';
      final card = await AiRoleplayCardImporter.parse(
        Uint8List.fromList(utf8.encode(rawCard)),
        retainOriginal: true,
      );
      final childCard = AiRoleplayCard.fromFields({'name': 'Child-only card'});
      final unusedCard = AiRoleplayCard.fromFields({
        'name': 'Shared card',
        'description': 'Unrelated local roleplay data',
      });
      final primary = await create('Primary');
      final child = await create('Child', parent: primary.id);
      final peer = await create('Peer');
      workspaces.addRoleplayTemplate(
        AiRoleplayBinding(card: unusedCard, playerName: 'Guest'),
      );
      primary.assistant.bindRoleplay(
        AiRoleplayBinding(
          card: card,
          playerName: 'Reader',
          includeProfile: true,
        ),
      );
      expect(
        primary.assistant.startRoleplayOpening(0, clearExisting: true),
        isTrue,
      );
      primary.assistant.setRoleplayEnabled(false);
      child.assistant.bindRoleplay(
        AiRoleplayBinding(card: childCard, playerName: 'Guest'),
      );
      peer.assistant.bindRoleplay(
        AiRoleplayBinding(card: card, playerName: 'Second reader'),
      );
      controller.owner = primary.id;

      final reference = sha256.convert(utf8.encode(rawCard)).toString();
      final childReference = sha256
          .convert(utf8.encode(jsonEncode(childCard.toTavernJson())))
          .toString();
      final expected = {
        'chat': {reference},
        'agent': {reference, childReference},
        'workflow': {reference},
      };
      for (final entry in expected.entries) {
        final type = entry.key;
        final path = '${directory.path}/$type.7z';
        await controller.export(
          path,
          type,
          children: type == 'agent',
          selectedIds: type == 'workflow' ? {primary.id, peer.id} : null,
        );
        final package = await controller.inspect(path);
        final workflow = package['workflow'] as Map;
        expect(workflow.containsKey('roleplayLibrary'), isFalse);
        expect(jsonEncode(package), isNot(contains(unusedCard.description)));
        final cards = workflow['roleplayCards'] as Map;
        expect(cards.keys.toSet(), entry.value);
        expect(cards[reference], base64Encode(utf8.encode(rawCard)));
        if (type == 'agent') {
          final childData = jsonDecode(
            utf8.decode(base64Decode(cards[childReference] as String)),
          ) as Map;
          expect(childData['spec'], 'chara_card_v2');
          expect(childData['data']['name'], childCard.name);
        }
        final records = (workflow['sessions'] as List).cast<Map>();
        final primaryRecord = records.singleWhere(
          (record) => record['id'] == primary.id,
        );
        final roleplay = primaryRecord['conversation']['roleplay'] as Map;
        expect(roleplay['enabled'], isFalse);
        expect(roleplay['binding']['cardRef'], reference);
        expect((roleplay['binding'] as Map).containsKey('card'), isFalse);
      }

      final memoryPath = '${directory.path}/memory.7z';
      await controller.export(memoryPath, 'memory');
      final memoryPackage = await controller.inspect(memoryPath);
      expect(memoryPackage['workflow'], isNull);
      expect(jsonEncode(memoryPackage), isNot(contains(reference)));

      final incoming = await controller.inspect(
        '${directory.path}/workflow.7z',
      );
      final destination = AgentStorage(path: '${directory.path}/target.db');
      final targetScope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        storage: destination,
      );
      final target = AiWorkspaceProvider(targetScope.provider);
      final importer = AgentStorageController(target);
      try {
        await target.initialized;
        final corrupted =
            jsonDecode(jsonEncode(incoming)) as Map<String, dynamic>;
        final corruptedCards = corrupted['workflow']['roleplayCards'] as Map;
        corruptedCards[reference] = base64Encode(utf8.encode('altered card'));
        await expectLater(importer.import(corrupted), throwsFormatException);
        expect(target.sessions, isEmpty);
        expect(target.roleplayTemplates, isEmpty);

        await importer.import(incoming);
        final saved = await destination.request('readWorkflowData') as Map;
        final savedLibrary = (saved['roleplayLibrary'] as List).cast<Map>();
        expect(savedLibrary, hasLength(1));
        expect(
          savedLibrary.single['card']['originalFile'],
          base64Encode(utf8.encode(rawCard)),
        );
        final importedPrimary = target.sessions
            .singleWhere((session) => session.title == primary.title)
            .assistant;
        final importedPeer = target.sessions
            .singleWhere((session) => session.title == peer.title)
            .assistant;
        expect(importedPrimary.roleplayEnabled, isFalse);
        expect(importedPrimary.roleplayBinding!.includeProfile, isTrue);
        expect(importedPrimary.roleplayBinding!.storyActive, isTrue);
        expect(importedPrimary.messages.single.content, 'Hi Reader!');
        expect(importedPeer.roleplayEnabled, isTrue);
        expect(importedPeer.roleplayBinding!.includeProfile, isFalse);
        expect(importedPeer.roleplayBinding!.playerName, 'Second reader');
      } finally {
        importer.dispose();
        target.dispose();
        targetScope.dispose();
        await destination.close();
      }
    },
  );

  test(
    'selected workflow rejects empty unknown recycled and other package types',
    () async {
      final active = await create('Active');
      final recycled = await create('Recycled');
      workspaces.removeMany([recycled.id]);
      final path = '${directory.path}/invalid.7z';
      await expectLater(
        controller.export(path, 'workflow', selectedIds: {}),
        throwsStateError,
      );
      await expectLater(
        controller.export(
          path,
          'workflow',
          selectedIds: {active.id, 'missing'},
        ),
        throwsStateError,
      );
      await expectLater(
        controller.export(path, 'workflow', selectedIds: {recycled.id}),
        throwsStateError,
      );
      controller.owner = active.id;
      await expectLater(
        controller.export(path, 'agent', selectedIds: {active.id}),
        throwsArgumentError,
      );
      expect(File(path).existsSync(), isFalse);
    },
  );
}
