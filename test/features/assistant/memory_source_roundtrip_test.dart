import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/domain/memory_conflict.dart';
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
    directory = await Directory.systemTemp.createTemp(
      'memory-source-roundtrip-',
    );
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

  Future<AiAgentWorkspace> create(String title) => workspaces.create(
    title: title,
    task: 'Remember durable preferences',
    kind: AiWorkspaceKind.primary,
    startImmediately: false,
  );

  for (final type in ['memory', 'workflow']) {
    test('$type repeated transfers keep provenance bounded and identities intact', () async {
      final originalAgent = await create('Original agent');
      const originalId = 'original-memory-id';
      const lineage = 'stable-memory-lineage';
      const content =
          'Use compact controls and preserve the current conversation.';
      final originalSource = jsonEncode({
        'messageId': 'private-original-message-id',
        'agentId': originalAgent.id,
        'source': {
          'importedFrom': 'older-private-agent-id',
          'source': {'messageId': 'older-private-message-id'},
        },
      });
      await storage.putMemory(
        id: originalId,
        owner: originalAgent.id,
        content: content,
        lineage: lineage,
        source: originalSource,
      );
      var currentOwner = originalAgent.id;
      final seenIds = <Object?>{originalId};
      for (var generation = 0; generation < 3; generation++) {
        controller.owner = currentOwner;
        final path = '${directory.path}/$type-$generation.tar.zst';
        await controller.export(
          path,
          type,
          selectedIds: type == 'workflow' ? {currentOwner} : null,
        );
        final package = await controller.inspect(path);
        final exported = (package['memories'] as List).single as Map;
        expect(exported['source'], '{"imported":true}');
        expect(exported['owner'], currentOwner);
        expect(exported['lineage'], lineage);
        expect(exported['hash'], memoryContentHash(content));

        // An incoming package can still contain arbitrary previous provenance.
        // Import must independently sanitize it, even if export already did so.
        exported['source'] = originalSource;
        if (type == 'memory') {
          controller.owner = (await create('Memory destination $generation'))
              .id;
        }
        final agentsBefore = workspaces.sessions.map((s) => s.id).toSet();
        await controller.import(package);
        currentOwner = type == 'memory'
            ? controller.owner
            : workspaces.sessions
                  .singleWhere((s) => !agentsBefore.contains(s.id))
                  .id;
        final imported = (await storage.memories(currentOwner)).single;
        expect(imported['owner'], currentOwner);
        expect(seenIds.add(imported['id']), isTrue);
        expect(imported['content'], content);
        expect(imported['hash'], memoryContentHash(content));
        expect(imported['lineage'], lineage);
        expect(imported['source'], '{"imported":true}');
        expect(jsonDecode(imported['source'] as String), {'imported': true});

        // Replaying this same fact into its owner must remain a duplicate.
        final replay = <String, dynamic>{
          'type': 'memory',
          'memories': [Map<String, Object?>.from(imported)],
        };
        controller.owner = currentOwner;
        final plan = await controller.plan(replay);
        expect(plan.single.duplicate, isTrue);
        expect(plan.single.resolution, MemoryResolution.skip);
        await controller.import(replay, plan: plan);
        expect((await storage.memories(currentOwner)).single, imported);
        expect(
          (await storage.memories(originalAgent.id)).single['source'],
          originalSource,
        );
      }
      expect(seenIds, hasLength(4));
    });
  }
}
