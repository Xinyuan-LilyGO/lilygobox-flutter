import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';

import 'assistant_test_scope.dart';

class _CardCopyStorage extends AgentStorage {
  _CardCopyStorage() : super(path: ':memory:');

  bool failCopy = false;

  @override
  Future<Object?> request(
    String operation, [
    Map<String, Object?> args = const {},
  ]) {
    if (operation == 'copyMemories' && failCopy) {
      failCopy = false;
      return Future.error(StateError('Memory copy failed'));
    }
    return super.request(operation, args);
  }
}

void main() {
  late AssistantTestScope scope;
  late _CardCopyStorage storage;
  late AiWorkspaceProvider workspaces;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late String serviceId;
  var requests = 0;

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    storage = _CardCopyStorage();
    requests = 0;
    scope = await createAssistantTestScope(
      storage: storage,
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'New response'},
              },
            ],
          }),
          200,
        );
      }),
    );
    await scope.provider.initialized;
    scope.provider.autoSaveMemory = false;
    serviceId = await scope.provider.saveService(
      name: 'Test',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6.1-sol'],
      apiKey: 'key',
    );
    workspaces = AiWorkspaceProvider(scope.provider);
    await workspaces.initialized;
  });

  tearDown(() async {
    await workspaces.flush();
    workspaces.dispose();
    await storage.close();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  Future<AiAgentWorkspace> task(String title, {String? parentId}) async {
    final agent = await workspaces.create(
      title: title,
      task: 'Instructions for $title',
      parentId: parentId,
      startImmediately: false,
    );
    agent.assistant.restoreWorkspaceConversation({
      ...agent.assistant.snapshotWorkspaceConversation(),
      'messages': [
        ConversationCodec.message(
          AiMessage(
            id: 'history-$title',
            role: 'user',
            content: 'Retained history for $title',
          ),
        ),
      ],
      'history': [
        {'role': 'user', 'content': 'Retained history for $title'},
      ],
      'contextBudgetTokens': 16384,
      'contextCompactionPercent': 75,
      'autoSaveMemory': false,
    });
    return agent;
  }

  for (final missing in [
    'service',
    'model',
    'selection',
    'pending selection',
  ]) {
    test('copy and paste do not require a configured $missing', () async {
      final source = await task('Unavailable');
      if (missing == 'service') {
        await scope.provider.removeService(serviceId);
      } else if (missing == 'model') {
        await scope.provider.saveService(
          id: serviceId,
          name: 'Changed',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test/v1',
          models: ['replacement-model'],
        );
      } else {
        source.assistant.markWorkspaceSelectionUnavailable(
          serviceId: missing == 'selection' ? '' : serviceId,
          model: missing == 'selection' ? '' : 'gpt-6.1-sol',
        );
      }
      expect(source.assistant.workspaceSelectionUnavailable, isTrue);
      final copy = await workspaces.duplicate(source.id, title: 'Duplicate');
      final pasted = await workspaces.pasteCards(
        workspaces.copyCards([source.id]),
        titleForCopy: (title) => '$title (2)',
      );
      for (final result in [copy, pasted.single]) {
        expect(result.task, source.task);
        expect(result.kind, source.kind);
        expect(result.parentId, source.parentId);
        expect(result.serviceId, source.serviceId);
        expect(result.model, source.model);
        expect(
          result.assistant.permissions,
          same(source.assistant.permissions),
        );
        expect(result.assistant.workspaceSelectionUnavailable, isTrue);
        expect(result.assistant.canSendMessage, isFalse);
        expect(
          result.assistant.messages.single.content,
          'Retained history for Unavailable',
        );
        expect(
          result.assistant.messages.single.id,
          isNot(source.assistant.messages.single.id),
        );
        expect(result.assistant.contextBudgetTokens, 16384);
        expect(result.assistant.contextCompactionPercent, 75);
        expect(result.busy, isFalse);
        await result.assistant.sendMessage('Must remain idle');
      }
      expect(requests, 0);
      if (missing == 'service') {
        await expectLater(
          workspaces.create(title: 'Needs a model', task: 'Run'),
          throwsStateError,
        );
      }
    });
  }

  test(
    'clipboard keeps histories memories and internal links after deletion',
    () async {
      final parent = await task('Parent');
      final child = await task('Child', parentId: parent.id);
      final sibling = await task('Sibling', parentId: parent.id);
      workspaces.connectCanvasTasks(child.id, sibling.id);
      await storage.putMemory(
        id: '0123456789abcdef0123456789abcdef',
        owner: child.id,
        content: 'Retained memory',
      );
      await scope.provider.removeService(serviceId);
      final cards = workspaces.copyCards([child.id, parent.id, sibling.id]);
      workspaces.removeMany([parent.id, child.id, sibling.id]);
      final pasted = await workspaces.pasteCards(
        cards,
        titleForCopy: (title) => title,
      );
      final copiedChild = pasted[0];
      final copiedParent = pasted[1];
      final copiedSibling = pasted[2];
      expect(copiedParent.parentId, isNull);
      expect(copiedParent.kind, AiWorkspaceKind.primary);
      expect(copiedChild.parentId, copiedParent.id);
      expect(copiedSibling.parentId, copiedParent.id);
      expect(copiedChild.kind, AiWorkspaceKind.permanent);
      expect(copiedSibling.kind, AiWorkspaceKind.permanent);
      expect(workspaces.isConnected(copiedChild.id, copiedSibling.id), isTrue);
      expect(
        pasted.every((agent) => agent.assistant.workspaceSelectionUnavailable),
        isTrue,
      );
      expect(
        copiedChild.assistant.messages.single.content,
        'Retained history for Child',
      );
      expect(
        (await storage.memories(copiedChild.id)).single['content'],
        'Retained memory',
      );
      expect(requests, 0);
      await workspaces.flush();
      workspaces.dispose();
      workspaces = AiWorkspaceProvider(scope.provider);
      await workspaces.initialized;
      expect(workspaces.find(copiedChild.id)!.parentId, copiedParent.id);
      expect(workspaces.isConnected(copiedChild.id, copiedSibling.id), isTrue);
      expect(
        workspaces.find(copiedChild.id)!.assistant.messages.single.content,
        'Retained history for Child',
      );
    },
  );

  test(
    'failed card paste leaves no new nodes links or recycled copies',
    () async {
      final parent = await task('Parent');
      final child = await task('Child', parentId: parent.id);
      final sibling = await task('Sibling', parentId: parent.id);
      workspaces.connectCanvasTasks(child.id, sibling.id);
      final before = jsonEncode(workspaces.exportData());
      storage.failCopy = true;
      await expectLater(
        workspaces.pasteCards(
          workspaces.copyCards([child.id, parent.id, sibling.id]),
          titleForCopy: (title) => '$title (2)',
        ),
        throwsStateError,
      );
      expect(jsonEncode(workspaces.exportData()), before);
      expect(workspaces.sessions, [parent, child, sibling]);
      expect(workspaces.recycledAgents, isEmpty);
      expect(requests, 0);
    },
  );

  test(
    'copied child becomes a main agent after its parent is deleted',
    () async {
      final parent = await task('Parent');
      final child = await task('Child', parentId: parent.id);
      final cards = workspaces.copyCards([child.id]);
      workspaces.removeMany([parent.id, child.id]);
      await scope.provider.removeService(serviceId);
      final copies = await workspaces.pasteCards(
        cards,
        titleForCopy: (title) => '$title (2)',
      );
      expect(copies.single.parentId, isNull);
      expect(copies.single.kind, AiWorkspaceKind.primary);
      expect(copies.single.assistant.workspaceSelectionUnavailable, isTrue);
      expect(
        copies.single.assistant.messages.single.content,
        'Retained history for Child',
      );
      expect(requests, 0);
    },
  );

  test(
    'template children retain their parent when duplicated or pasted',
    () async {
      final child = await task('Child', parentId: 'main');
      await scope.provider.removeService(serviceId);
      final duplicate = await workspaces.duplicate(
        child.id,
        title: 'Duplicate',
      );
      final pasted = await workspaces.pasteCards(
        workspaces.copyCards([child.id]),
        titleForCopy: (title) => '$title (2)',
      );
      for (final copy in [duplicate, pasted.single]) {
        expect(copy.parentId, 'main');
        expect(copy.kind, AiWorkspaceKind.permanent);
        expect(copy.assistant.workspaceSelectionUnavailable, isTrue);
      }
      expect(requests, 0);
    },
  );

  test(
    'ready card copies retain effort speed and can run after copying',
    () async {
      final source = await task('Ready');
      await source.assistant.setReasoningEffort(AiReasoningEffort.high);
      await source.assistant.setProcessingSpeed(AiProcessingSpeed.fast);
      final copy = await workspaces.duplicate(source.id, title: 'Ready copy');
      expect(copy.assistant.reasoningEffort, AiReasoningEffort.high);
      expect(copy.assistant.processingSpeed, AiProcessingSpeed.fast);
      expect(copy.assistant.canSendMessage, isTrue);
      expect(requests, 0);
      await copy.assistant.sendMessage('Continue copied history');
      expect(copy.assistant.messages.last.content, 'New response');
      expect(
        source.assistant.messages.single.content,
        'Retained history for Ready',
      );
      expect(requests, 1);
    },
  );
}
