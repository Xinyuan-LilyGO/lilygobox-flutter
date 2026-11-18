import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
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
