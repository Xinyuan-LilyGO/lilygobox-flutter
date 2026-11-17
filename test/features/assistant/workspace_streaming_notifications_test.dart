import 'dart:async';
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
  test(
    'streaming updates the conversation without rebuilding the workspace',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      final stream = StreamController<List<int>>();
      final started = Completer<void>();
      final scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          started.complete();
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final workspaces = AiWorkspaceProvider(scope.provider);
      addTearDown(() async {
        workspaces.dispose();
        await stream.close();
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
      });
      await workspaces.initialized;
      final serviceId = await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      final task = await workspaces.create(
        title: 'Streaming',
        task: 'Reply',
        serviceId: serviceId,
        model: 'test',
        startImmediately: false,
      );
      var notifications = 0;
      workspaces.addListener(() => notifications++);
      final sending = task.assistant.sendMessage('Reply');
      await started.future;
      void emit(String text) => stream.add(
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': text},
              },
            ],
          })}\n\n',
        ),
      );
      emit('First');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(task.assistant.messages.last.content, 'First');
      final baseline = notifications;
      for (var index = 0; index < 10; index++) {
        emit(' delta');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(task.assistant.messages.last.content, 'First${' delta' * 10}');
      expect(notifications, baseline);
      stream.add(utf8.encode('data: [DONE]\n\n'));
      await stream.close();
      await sending;
      expect(task.status, 'completed');
      expect(notifications, greaterThan(baseline));
      expect(task.result, 'First${' delta' * 10}');
    },
  );
}
