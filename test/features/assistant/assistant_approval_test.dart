import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/assistant_tools.dart';
import 'package:lilygobox/features/assistant/data/command_policy_store.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';

import 'assistant_test_scope.dart';

void main() {
  late AssistantTestScope scope;
  late Directory root;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late Completer<void> awaiting;
  late List<Map<String, dynamic>> requests;
  var toolName = 'write_file';
  var twoCalls = false;
  late Map<String, Object?> arguments;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lilygobox-approval-');
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    awaiting = Completer<void>();
    requests = [];
    twoCalls = false;
    toolName = 'write_file';
    arguments = {
      'path': '${root.path}/a.txt',
      'content': 'approved',
      'expected_content': null,
    };
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      tools: AssistantTools(
        commandPolicy: AiCommandPolicyStore(
          file: File('${root.path}/command-rules.json'),
        ),
      ),
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final useTool =
            requests.length == 1 || (twoCalls && requests.length == 2);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': useTool
                    ? {
                        'content': '',
                        'tool_calls': [
                          {
                            'id': 'call-${requests.length}',
                            'type': 'function',
                            'function': {
                              'name': toolName,
                              'arguments': jsonEncode(arguments),
                            },
                          },
                        ],
                      }
                    : {'content': 'Done'},
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
      models: ['test-model'],
      apiKey: 'key',
    );
    scope.provider.addListener(() {
      if (!awaiting.isCompleted && scope.provider.pendingApproval != null) {
        awaiting.complete();
      }
    });
  });
  tearDown(() async {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    await root.delete(recursive: true);
  });
  AiMessage pending() => scope.provider.pendingApproval!;

  test('no file changes happen until an exact one-time approval', () async {
    final send = scope.provider.sendMessage('Write a file');
    await awaiting.future.timeout(const Duration(seconds: 5));
    expect(await File(arguments['path'] as String).exists(), isFalse);
    final id = pending().id;
    await scope.provider.resolveTool(id, approve: true);
    await scope.provider.resolveTool(id, approve: true);
    await send;
    expect(await File(arguments['path'] as String).readAsString(), 'approved');
    expect(requests, hasLength(2));
    expect(scope.provider.pendingApproval, isNull);
    expect(
      scope.provider.messages.where((message) => message.toolName != null),
      isEmpty,
    );
  });

  test('denial returns tool failure and leaves the file untouched', () async {
    final send = scope.provider.sendMessage('Write');
    await awaiting.future;
    await scope.provider.resolveTool(pending().id, approve: false);
    await send;
    expect(await File(arguments['path'] as String).exists(), isFalse);
    final history = requests.last['messages'] as List;
    expect(
      history.where((item) => item['role'] == 'tool').single['content'],
      contains('denied'),
    );
  });

  test(
    'stopping cancels outstanding approval without executing or hanging',
    () async {
      final send = scope.provider.sendMessage('Write');
      await awaiting.future;
      final id = pending().id;
      scope.provider.stopGeneration();
      await send.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(id, approve: true);
      expect(scope.provider.busy, isFalse);
      expect(await File(arguments['path'] as String).exists(), isFalse);
      expect(requests, hasLength(1));
    },
  );

  test(
    'custom write scope runs directly and clear resets permissions',
    () async {
      scope.provider.setPermissions(
        AiPermissions(
          mode: AiApprovalMode.custom,
          files: AiFileAccess.readWrite,
          folders: [root.path],
        ),
      );
      await scope.provider.sendMessage('Write');
      expect(
        await File(arguments['path'] as String).readAsString(),
        'approved',
      );
      expect(
        scope.provider.messages.where((message) => message.toolName != null),
        isEmpty,
      );
      scope.provider.clearConversation();
      expect(scope.provider.permissions.mode, AiApprovalMode.onRequest);
      expect(scope.provider.permissions.folders, isEmpty);
    },
  );

  test(
    'custom scope always requests approval for operations outside it',
    () async {
      scope.provider.setPermissions(AiPermissions(mode: AiApprovalMode.custom));
      final send = scope.provider.sendMessage('Write');
      await awaiting.future.timeout(const Duration(seconds: 5));
      expect(await File(arguments['path'] as String).exists(), isFalse);
      await scope.provider.resolveTool(pending().id, approve: false);
      await send;
      expect(await File(arguments['path'] as String).exists(), isFalse);
      expect(scope.provider.pendingApproval, isNull);
    },
  );

  test('ordinary setting tools still run without confirmation', () async {
    toolName = 'set_theme';
    arguments = {'theme': 'light'};
    await scope.provider.sendMessage('Light theme');
    expect(
      scope.provider.messages.where((message) => message.toolName != null),
      isEmpty,
    );
    expect(requests, hasLength(2));
  });

  test(
    'one-time approval does not grant later calls the same permission',
    () async {
      toolName = 'read_file';
      arguments = {'path': '${root.path}/a.txt'};
      twoCalls = true;
      await File(arguments['path'] as String).writeAsString('data');
      final send = scope.provider.sendMessage('Read twice');
      await awaiting.future;
      final first = pending().id;
      await scope.provider.resolveTool(first, approve: true);
      final second = Completer<void>();
      void listener() {
        if (!second.isCompleted &&
            (scope.provider.pendingApproval != null &&
                scope.provider.pendingApproval!.id != first)) {
          second.complete();
        }
      }

      scope.provider.addListener(listener);
      listener();
      await second.future.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(pending().id, approve: false);
      await send;
      scope.provider.removeListener(listener);
      expect(
        scope.provider.messages.where((message) => message.toolName != null),
        isEmpty,
      );
      expect(scope.provider.pendingApproval, isNull);
      expect(requests, hasLength(3));
    },
  );

  Map<String, Object?> localCommand() {
    final marker = '${root.path}/executed.txt';
    return {
      'executable': Platform.isWindows ? 'powershell.exe' : '/bin/sh',
      'arguments': Platform.isWindows
          ? [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              "[IO.File]::WriteAllText('${marker.replaceAll("'", "''")}', 'executed')",
            ]
          : ['-c', 'printf executed > "$marker"'],
      'working_directory': root.path,
      'reason': 'Verify category approvals',
      'yield_ms': 5000,
    };
  }

  for (final rejected in [AiPermissionCategory.execution]) {
    test(
      'rejecting ${rejected.name} prevents the command from starting',
      () async {
        toolName = 'run_command';
        arguments = localCommand();
        final seen = <String>[];
        final handled = <String>{};
        void listener() {
          final request = scope.provider.pendingApproval;
          if (request == null || !handled.add(request.id)) return;
          final category =
              request.toolArguments!['permission_category'] as String;
          seen.add(category);
          expect(File('${root.path}/executed.txt').existsSync(), isFalse);
          scheduleMicrotask(
            () => scope.provider.resolveTool(
              request.id,
              approve: category != rejected.name,
            ),
          );
        }

        scope.provider.addListener(listener);
        await scope.provider.sendMessage('Run command');
        scope.provider.removeListener(listener);
        expect(seen, [AiPermissionCategory.execution.name]);
        expect(await File('${root.path}/executed.txt').exists(), isFalse);
        expect(scope.provider.pendingApproval, isNull);
        expect(
          scope.provider.messages.last.processingSteps.single.succeeded,
          isFalse,
        );
      },
    );
  }

  test('a command requests one execution approval before launch', () async {
    toolName = 'run_command';
    arguments = localCommand();
    final seen = <String>[];
    final handled = <String>{};
    void listener() {
      final request = scope.provider.pendingApproval;
      if (request == null || !handled.add(request.id)) return;
      seen.add(request.toolArguments!['permission_category'] as String);
      expect(File('${root.path}/executed.txt').existsSync(), isFalse);
      scheduleMicrotask(
        () => scope.provider.resolveTool(request.id, approve: true),
      );
    }

    scope.provider.addListener(listener);
    await scope.provider.sendMessage('Run command');
    scope.provider.removeListener(listener);
    expect(seen, [AiPermissionCategory.execution.name]);
    expect(await File('${root.path}/executed.txt').readAsString(), 'executed');
    expect(scope.provider.permissions.execution, isFalse);
    expect(scope.provider.permissions.fullFiles, isFalse);
  });

  test('file and network grants do not authorize command execution', () async {
    toolName = 'run_command';
    arguments = localCommand();
    arguments['arguments'] = Platform.isWindows
        ? ['-NoProfile', '-Command', 'Write-Output harmless']
        : ['-c', 'echo harmless'];
    scope.provider.setPermissions(
      AiPermissions(
        mode: AiApprovalMode.custom,
        execution: false,
        fullFiles: true,
        network: true,
      ),
    );
    final sending = scope.provider.sendMessage('Run command');
    await awaiting.future.timeout(const Duration(seconds: 5));
    expect(pending().toolArguments!['permission_category'], 'execution');
    await scope.provider.resolveTool(pending().id, approve: false);
    await sending;
    expect(await File('${root.path}/executed.txt').exists(), isFalse);
  });
  AiPermissions fullyAuthorized() => AiPermissions(
    mode: AiApprovalMode.custom,
    execution: true,
    fullFiles: true,
    network: true,
  );
  test(
    'opaque commands still require a visible one-time safety approval under full access',
    () async {
      toolName = 'run_command';
      arguments = localCommand();
      scope.provider.setPermissions(fullyAuthorized());
      final sending = scope.provider.sendMessage('Run command');
      await awaiting.future.timeout(const Duration(seconds: 5));
      expect(pending().toolArguments!['command_safety_approval'], isTrue);
      expect(
        pending().toolArguments!['command_risks'],
        contains('opaqueScript'),
      );
      expect(File('${root.path}/executed.txt').existsSync(), isFalse);
      await scope.provider.resolveTool(pending().id, approve: false);
      await sending;
      expect(File('${root.path}/executed.txt').existsSync(), isFalse);
      expect(scope.provider.permissions.execution, isTrue);
    },
  );
  for (final promptRule in [false, true]) {
    test(
      'command bypass runs opaque scripts without approval (prompt:$promptRule)',
      () async {
        toolName = 'run_command';
        arguments = localCommand();
        scope.provider.setPermissions(
          fullyAuthorized().copyWith(commandNoApproval: true),
        );
        if (promptRule) {
          await File('${root.path}/command-rules.json').writeAsString(
            jsonEncode({
              'version': 1,
              'rules': [
                {
                  'prefix': [arguments['executable']],
                  'decision': 'prompt',
                },
              ],
            }),
          );
        }
        var approvalRequests = 0;
        void rejectUnexpectedApproval() {
          if (scope.provider.pendingApproval case final request?) {
            approvalRequests++;
            scheduleMicrotask(
              () => scope.provider.resolveTool(request.id, approve: false),
            );
          }
        }

        scope.provider.addListener(rejectUnexpectedApproval);
        await scope.provider.sendMessage('Run command');
        scope.provider.removeListener(rejectUnexpectedApproval);
        expect(approvalRequests, 0);
        expect(
          await File('${root.path}/executed.txt').readAsString(),
          'executed',
        );
        expect(scope.provider.pendingApproval, isNull);
      },
    );
  }

  test('command bypass still rejects explicitly forbidden commands', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(
      fullyAuthorized().copyWith(commandNoApproval: true),
    );
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.sendMessage('Run command');
    expect(awaiting.isCompleted, isFalse);
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(
      jsonDecode(
        scope.provider.messages.last.processingSteps.single.output,
      )['error_code'],
      'command_forbidden',
    );
  });

  test(
    'one-time safety approval executes without changing capability switches',
    () async {
      toolName = 'run_command';
      arguments = localCommand();
      scope.provider.setPermissions(fullyAuthorized());
      final sending = scope.provider.sendMessage('Run command');
      await awaiting.future.timeout(const Duration(seconds: 5));
      await scope.provider.resolveTool(pending().id, approve: true);
      await sending;
      expect(
        await File('${root.path}/executed.txt').readAsString(),
        'executed',
      );
      expect(scope.provider.pendingApproval, isNull);
    },
  );
  test(
    'forbidden commands never show an allow button and return a structured failure',
    () async {
      toolName = 'run_command';
      arguments = localCommand();
      scope.provider.setPermissions(fullyAuthorized());
      await File('${root.path}/command-rules.json').writeAsString(
        jsonEncode({
          'version': 1,
          'rules': [
            {
              'prefix': [arguments['executable']],
              'decision': 'forbidden',
            },
          ],
        }),
      );
      await scope.provider.sendMessage('Run command');
      expect(awaiting.isCompleted, isFalse);
      expect(File('${root.path}/executed.txt').existsSync(), isFalse);
      expect(scope.provider.pendingApproval, isNull);
      final step = scope.provider.messages.last.processingSteps.single;
      expect(step.succeeded, isFalse);
      expect(jsonDecode(step.output)['error_code'], 'command_forbidden');
    },
  );
  test('policy changes while awaiting approval prevent execution', () async {
    toolName = 'run_command';
    arguments = localCommand();
    scope.provider.setPermissions(fullyAuthorized());
    final sending = scope.provider.sendMessage('Run command');
    await awaiting.future.timeout(const Duration(seconds: 5));
    await File('${root.path}/command-rules.json').writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': [arguments['executable']],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await scope.provider.resolveTool(pending().id, approve: true);
    await sending;
    expect(File('${root.path}/executed.txt').existsSync(), isFalse);
    expect(
      jsonDecode(
        scope.provider.messages.last.processingSteps.single.output,
      )['error_code'],
      'command_forbidden',
    );
  });
}
