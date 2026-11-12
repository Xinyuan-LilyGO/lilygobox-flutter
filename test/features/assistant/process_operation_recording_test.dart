import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/process_timeline.dart';

import 'assistant_test_scope.dart';

void main() {
  test(
    'repeated same-name calls retain distinct IDs, real arguments and model-visible results',
    () async {
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      final requests = <Map<String, dynamic>>[];
      final scope = await createAssistantTestScope(
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
                  'message': requests.length < 3
                      ? {
                          'content': null,
                          'tool_calls': [
                            {
                              'id': 'reused-server-id',
                              'type': 'function',
                              'function': {
                                'name': 'get_current_time',
                                'arguments': '{}',
                              },
                            },
                          ],
                        }
                      : {'content': 'Finished checking the time.'},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(() {
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
      });
      await scope.provider.initialized;
      await scope.provider.saveService(
        name: 'Test',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test',
        models: ['test'],
        apiKey: 'key',
      );
      await scope.provider.sendMessage('Check the time twice');
      final events = scope.provider.messages.last.processEvents;
      final starts = events
          .where((e) => e.status == AiResponseStatus.executingTools)
          .toList();
      final results = events
          .where((e) => e.type == AiProcessEventType.action)
          .toList();
      expect(starts, hasLength(2));
      expect(results, hasLength(2));
      expect(starts.map((e) => e.operationId).toSet(), hasLength(2));
      final historyResults = (requests.last['messages'] as List)
          .where((m) => m['role'] == 'tool')
          .toList();
      for (var i = 0; i < 2; i++) {
        expect(starts[i].operationId, isNotNull);
        expect(starts[i].operationId, results[i].operationId);
        expect(starts[i].toolArguments, isEmpty);
        expect(results[i].action!.output, historyResults[i]['content']);
        expect(jsonDecode(results[i].action!.output), contains('local_time'));
      }
      final timeline = buildAiProcessTimeline(events);
      final operations = timeline
          .where((entry) => entry.event.operationId != null)
          .toList();
      expect(operations, hasLength(2));
      for (final operation in operations) {
        expect(operation.events.map((step) => step.status), [
          AiResponseStatus.preparingTools,
          AiResponseStatus.executingTools,
          null,
        ]);
      }
      expect(
        timeline.where((e) => e.event.type == AiProcessEventType.action),
        hasLength(2),
      );
      expect(
        timeline.where(
          (e) => e.event.status == AiResponseStatus.executingTools,
        ),
        isEmpty,
      );
    },
  );

  for (final allow in [true, false]) {
    test(
      'approval remains actionable and is retained inside its operation (allow=$allow)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lilygobox-operation-',
        );
        final file = File('${directory.path}/sample.txt');
        await file.writeAsString('FILE_CONTENT_MARKER');
        addTearDown(() async {
          await file.delete();
          await directory.delete();
        });
        final theme = ThemeProvider();
        final language = LanguageProvider();
        final shell = AppShellProvider();
        final split = SplitViewProvider();
        var requests = 0;
        final scope = await createAssistantTestScope(
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
                    'message': requests == 1
                        ? {
                            'content': null,
                            'tool_calls': [
                              {
                                'id': 'file',
                                'type': 'function',
                                'function': {
                                  'name': 'read_file',
                                  'arguments': jsonEncode({'path': file.path}),
                                },
                              },
                            ],
                          }
                        : {'content': 'Operation finished.'},
                  },
                ],
              }),
              200,
            );
          }),
        );
        addTearDown(() {
          scope.dispose();
          theme.dispose();
          language.dispose();
          shell.dispose();
          split.dispose();
        });
        await scope.provider.initialized;
        await scope.provider.saveService(
          name: 'Test',
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test',
          models: ['test'],
          apiKey: 'key',
        );
        final send = scope.provider.sendMessage('Read the file');
        for (
          var attempt = 0;
          attempt < 100 && scope.provider.pendingApproval == null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final approval = scope.provider.pendingApproval;
        expect(approval, isNotNull);
        final pending = buildAiProcessTimeline(
          scope.provider.messages.last.processEvents,
        ).where((entry) => entry.event.operationId != null).single;
        expect(pending.event.status, AiResponseStatus.awaitingApproval);
        expect(pending.events.map((event) => event.status), [
          AiResponseStatus.preparingTools,
          AiResponseStatus.awaitingApproval,
        ]);
        await scope.provider.resolveTool(approval!.id, approve: allow);
        await send;
        expect(scope.provider.pendingApproval, isNull);
        final done = buildAiProcessTimeline(
          scope.provider.messages.last.processEvents,
        ).where((entry) => entry.event.operationId != null).single;
        expect(done.id, pending.id);
        expect(done.event.action!.succeeded, allow);
        expect(done.events.map((event) => event.status), [
          AiResponseStatus.preparingTools,
          AiResponseStatus.awaitingApproval,
          if (allow) AiResponseStatus.executingTools,
          null,
        ]);
      },
    );
  }
}
