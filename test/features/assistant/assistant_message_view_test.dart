import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late AssistantTestScope scope;

  setUp(() {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
  });

  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  test(
    'messages reuses a read-only live view across restore and clear',
    () async {
      scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
      );
      await scope.provider.initialized;
      final messages = scope.provider.messages;
      expect(messages, isEmpty);
      scope.provider.restoreWorkspaceConversation({
        'messages': [
          for (var index = 0; index < 10000; index++)
            ConversationCodec.message(
              AiMessage(
                id: 'history-$index',
                role: 'user',
                content: 'Stored message $index',
              ),
            ),
        ],
        'history': <Map<String, Object?>>[],
      });
      expect(messages, hasLength(10000));
      for (var read = 0; read < 1000; read++) {
        expect(scope.provider.messages, same(messages));
      }
      final explicitSnapshot = messages.toList();
      const replacement = AiMessage(
        id: 'external',
        role: 'user',
        content: 'edit',
      );
      expect(() => messages.add(replacement), throwsUnsupportedError);
      expect(() => messages[0] = replacement, throwsUnsupportedError);
      expect(messages.clear, throwsUnsupportedError);
      expect(() => messages.length = 1, throwsUnsupportedError);
      expect(messages.first.id, 'history-0');
      expect(messages.last.id, 'history-9999');
      scope.provider.clearConversation();
      expect(scope.provider.messages, same(messages));
      expect(messages, isEmpty);
      expect(explicitSnapshot, hasLength(10000));
      expect(explicitSnapshot.last.content, 'Stored message 9999');
    },
  );

  test(
    'live messages observes appended and replaced streaming responses',
    () async {
      final stream = StreamController<List<int>>();
      scope = await createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
        client: MockClient.streaming(
          (request, body) async => http.StreamedResponse(stream.stream, 200),
        ),
      );
      addTearDown(stream.close);
      await scope.provider.initialized;
      scope.provider.autoSaveMemory = false;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['test'],
        apiKey: 'key',
      );
      final messages = scope.provider.messages;
      final request = scope.provider.sendMessage('Start');
      expect(messages, hasLength(2));
      final initialReply = messages.last;
      stream.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n'),
      );
      for (
        var attempt = 0;
        attempt < 100 && messages.last.content.isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(messages.last.content, 'Partial');
      expect(messages.last, isNot(same(initialReply)));
      final partial = messages.last;
      final snapshot = messages.toList();
      stream.add(
        utf8.encode('data: {"choices":[{"delta":{"content":" updated"}}]}\n\n'),
      );
      stream.add(utf8.encode('data: [DONE]\n\n'));
      await stream.close();
      await request;
      expect(scope.provider.messages, same(messages));
      expect(messages.last.content, 'Partial updated');
      expect(messages.last.status, AiResponseStatus.completed);
      expect(partial.content, 'Partial');
      expect(snapshot.last, same(partial));
    },
  );
}
