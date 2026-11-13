import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/assistant_tools.dart';
import 'package:lilygobox/features/assistant/data/command_policy_store.dart';
import 'package:lilygobox/features/assistant/domain/command_policy.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';

void main() {
  late Directory root;
  late File rules;
  late File marker;
  late AssistantTools tools;
  final full = AiPermissions(
    mode: AiApprovalMode.custom,
    execution: true,
    fullFiles: true,
    network: true,
  );
  final shell = Platform.isWindows ? 'powershell.exe' : '/bin/sh';
  Map<String, Object?> command(String script) => {
    'executable': shell,
    'arguments': Platform.isWindows
        ? ['-NoProfile', '-NonInteractive', '-Command', script]
        : ['-c', script],
    'working_directory': root.path,
    'reason': 'Policy regression test',
    'yield_ms': 5000,
  };
  String writeMarker() => Platform.isWindows
      ? "[IO.File]::WriteAllText('${marker.path.replaceAll("'", "''")}', 'executed')"
      : "printf executed > '${marker.path}'";
  Future<void> saveRules(String decision) => rules.writeAsString(
    jsonEncode({
      'version': 1,
      'rules': [
        {
          'prefix': [shell],
          'decision': decision,
        },
      ],
    }),
  );
  Matcher problem(AiCommandPolicyProblem expected) =>
      isA<AiCommandPolicyFailure>().having(
        (failure) => failure.problem,
        'problem',
        expected,
      );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('command-policy-');
    rules = File('${root.path}/command-rules.json');
    marker = File('${root.path}/marker.txt');
    tools = AssistantTools(commandPolicy: AiCommandPolicyStore(file: rules));
  });
  tearDown(() async {
    await tools.dispose();
    await root.delete(recursive: true);
  });

  test(
    'full access cannot bypass a dangerous command, approval permits only the prepared call',
    () async {
      await marker.writeAsString('keep');
      final script = Platform.isWindows
          ? "Remove-Item -Force -LiteralPath '${marker.path}'"
          : "rm -f -- '${marker.path}'";
      final prepared = await tools.prepare('run_command', command(script));
      expect(
        prepared.commandAssessment!.risks,
        contains(AiCommandRisk.forceDelete),
      );
      expect(await tools.requiredApprovals(prepared, full), [
        AiPermissionCategory.execution,
      ]);
      expect(await tools.isAllowed(prepared, full), isFalse);
      await expectLater(
        tools.execute(prepared),
        throwsA(problem(AiCommandPolicyProblem.approvalRequired)),
      );
      expect(await marker.readAsString(), 'keep');
      final result = jsonDecode(
        await tools.execute(prepared, commandSafetyApproved: true),
      );
      expect(result['ok'], isTrue);
      expect(await marker.exists(), isFalse);
    },
  );
  test('forbidden fails before any approval or process start', () async {
    await saveRules('forbidden');
    await expectLater(
      tools.prepare('run_command', command(writeMarker())),
      throwsA(problem(AiCommandPolicyProblem.forbidden)),
    );
    expect(await marker.exists(), isFalse);
  });
  test('literal forbidden nested command cannot run', () async {
    await rules.writeAsString(
      jsonEncode({
        'version': 1,
        'rules': [
          {
            'prefix': ['git', 'reset', '--hard'],
            'decision': 'forbidden',
          },
        ],
      }),
    );
    await expectLater(
      tools.prepare(
        'run_command',
        command('${writeMarker()}; git reset --hard'),
      ),
      throwsA(problem(AiCommandPolicyProblem.forbidden)),
    );
    expect(await marker.exists(), isFalse);
  });
  test(
    'prompt rules apply even with all capability switches enabled',
    () async {
      await saveRules('prompt');
      final prepared = await tools.prepare(
        'run_command',
        command('echo policy-test'),
      );
      expect(await tools.requiredApprovals(prepared, full), [
        AiPermissionCategory.execution,
      ]);
      await expectLater(
        tools.execute(prepared),
        throwsA(problem(AiCommandPolicyProblem.approvalRequired)),
      );
      expect(
        jsonDecode(
          await tools.execute(prepared, commandSafetyApproved: true),
        )['ok'],
        isTrue,
      );
    },
  );
  test('allow rules do not grant missing capability permissions', () async {
    await saveRules('allow');
    final prepared = await tools.prepare(
      'run_command',
      command('echo policy-test'),
    );
    expect(await tools.requiredApprovals(prepared, AiPermissions()), [
      AiPermissionCategory.execution,
    ]);
    expect(await tools.requiredApprovals(prepared, full), isEmpty);
  });
  test(
    'new forbidden rule is enforced again immediately before launch',
    () async {
      final prepared = await tools.prepare(
        'run_command',
        command(writeMarker()),
      );
      await saveRules('forbidden');
      await expectLater(
        tools.execute(prepared, commandSafetyApproved: true),
        throwsA(problem(AiCommandPolicyProblem.forbidden)),
      );
      expect(await marker.exists(), isFalse);
    },
  );
  test('changed rules invalidate pending approval', () async {
    await saveRules('prompt');
    final prepared = await tools.prepare('run_command', command(writeMarker()));
    await rules.writeAsString(jsonEncode({'version': 1, 'rules': []}));
    await expectLater(
      tools.execute(prepared, commandSafetyApproved: true),
      throwsA(problem(AiCommandPolicyProblem.changed)),
    );
    expect(await marker.exists(), isFalse);
  });
  test(
    'malformed and oversized config fail closed; UTF-8 BOM is supported',
    () async {
      for (final contents in [
        'not json',
        '',
        '{"version":2,"rules":[]}',
        'x' * 65537,
      ]) {
        await rules.writeAsString(contents);
        await expectLater(
          tools.prepare('run_command', command(writeMarker())),
          throwsA(problem(AiCommandPolicyProblem.invalidRules)),
        );
      }
      await rules.writeAsString('\uFEFF{"version":1,"rules":[]}');
      expect(
        (await tools.prepare(
          'run_command',
          command('echo safe'),
        )).commandAssessment!.decision,
        AiCommandDecision.allow,
      );
      expect(await marker.exists(), isFalse);
    },
  );
  test('invalid config appearing after approval cannot execute', () async {
    final prepared = await tools.prepare('run_command', command(writeMarker()));
    await rules.writeAsString('invalid');
    await expectLater(
      tools.execute(prepared, commandSafetyApproved: true),
      throwsA(problem(AiCommandPolicyProblem.invalidRules)),
    );
    expect(await marker.exists(), isFalse);
  });
  test('built-in file tool cannot overwrite the command policy', () async {
    await expectLater(
      tools.prepare('write_file', {
        'path': rules.path,
        'content': '{"version":1,"rules":[]}',
        'expected_content': null,
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await rules.exists(), isFalse);
  });
  test('model supplied approval and rules fields are discarded', () async {
    final prepared = await tools.prepare('run_command', {
      ...command(writeMarker()),
      'commandSafetyApproved': true,
      'command_safety_approval': true,
      'rules': [],
      'decision': 'allow',
    });
    expect(prepared.arguments.containsKey('commandSafetyApproved'), isFalse);
    await expectLater(
      tools.execute(prepared),
      throwsA(problem(AiCommandPolicyProblem.approvalRequired)),
    );
    expect(await marker.exists(), isFalse);
  });
}
