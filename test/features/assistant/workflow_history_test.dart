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
  tearDown(() {
    workspaces.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  test(
    'undo deletion retains IDs conversation and descendants without replay',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'one',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final child = await workspaces.create(
        title: 'Child',
        task: 'two',
        parentId: root.id,
        startImmediately: false,
      );
      await root.assistant.sendMessage('Original conversation');
      final before = workspaces.captureTopologyEdit();
      final originalMessages = [...root.assistant.messages];
      final requestCount = requests.length;
      workspaces.remove(root.id);
      final after = workspaces.captureTopologyEdit();
      expect(workspaces.find(root.id), isNull);
      await workspaces.restoreTopologyEdit(before);
      expect(workspaces.find(root.id), same(root));
      expect(workspaces.find(child.id), same(child));
      expect(child.parentId, root.id);
      expect(child.kind, AiWorkspaceKind.permanent);
      expect(root.assistant.messages, originalMessages);
      expect(requests, hasLength(requestCount));
      await workspaces.restoreTopologyEdit(after);
      expect(workspaces.find(root.id), isNull);
      expect(child.kind, AiWorkspaceKind.primary);
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
    },
  );

  test(
    'creation redo preserves independent original object and live chat updates',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'one',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final before = workspaces.captureTopologyEdit();
      final child = await workspaces.create(
        title: 'New child',
        task: 'two',
        parentId: root.id,
        startImmediately: false,
      );
      final after = workspaces.captureTopologyEdit();
      await root.assistant.sendMessage('Arrived after the edit');
      final messages = [...root.assistant.messages];
      await workspaces.restoreTopologyEdit(before);
      expect(workspaces.find(child.id), isNull);
      expect(root.assistant.messages, messages);
      await workspaces.restoreTopologyEdit(after);
      expect(workspaces.find(child.id), same(child));
      expect(root.assistant.messages, messages);
      expect(child.busy, isFalse);
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
    },
  );

  test(
    'role connection and rename edits restore together and snapshots match values',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'one',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final other = await workspaces.create(
        title: 'Other',
        task: 'two',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final before = workspaces.captureTopologyEdit();
      final same = workspaces.captureTopologyEdit();
      expect(before.matches(same), isTrue);
      workspaces.releaseTopologyEdit(same);
      final merge = workspaces.connectionMergeFor(root.id, other.id);
      workspaces.connectTasks(root.id, other.id, confirmedMerge: merge);
      workspaces.rename(other.id, 'Edited');
      final after = workspaces.captureTopologyEdit();
      expect(before.matches(after), isFalse);
      await workspaces.restoreTopologyEdit(before);
      expect(other.kind, AiWorkspaceKind.primary);
      expect(other.parentId, isNull);
      expect(other.title, 'Other');
      expect(workspaces.connections, isEmpty);
      await workspaces.restoreTopologyEdit(after);
      expect(other.kind, AiWorkspaceKind.permanent);
      expect(other.parentId, root.id);
      expect(other.title, 'Edited');
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
      await expectLater(
        workspaces.restoreTopologyEdit(before),
        throwsStateError,
      );
    },
  );
  test(
    'delta restore leaves model-created tasks and unrelated live edits intact',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'one',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final before = workspaces.captureTopologyEdit();
      workspaces.rename(root.id, 'Renamed');
      final after = workspaces.captureTopologyEdit();
      final external = await workspaces.create(
        title: 'Model child',
        task: 'external work',
        parentId: root.id,
        startImmediately: false,
      );
      await workspaces.restoreTopologyEdit(before, previous: after);
      expect(root.title, 'Root');
      expect(workspaces.find(external.id), same(external));
      expect(external.parentId, root.id);
      await workspaces.restoreTopologyEdit(after, previous: before);
      expect(root.title, 'Renamed');
      expect(workspaces.find(external.id), same(external));
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
    },
  );
  test(
    'undo rename patches only title and keeps later parent changes',
    () async {
      final root = await workspaces.create(
        title: 'Root',
        task: 'one',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final other = await workspaces.create(
        title: 'Other',
        task: 'two',
        kind: AiWorkspaceKind.primary,
        startImmediately: false,
      );
      final before = workspaces.captureTopologyEdit();
      workspaces.rename(root.id, 'Renamed');
      final after = workspaces.captureTopologyEdit();
      workspaces.reparent(root.id, other.id);
      await workspaces.restoreTopologyEdit(before, previous: after);
      expect(root.title, 'Root');
      expect(root.parentId, other.id);
      expect(root.kind, AiWorkspaceKind.permanent);
      workspaces.releaseTopologyEdit(before);
      workspaces.releaseTopologyEdit(after);
    },
  );
}
