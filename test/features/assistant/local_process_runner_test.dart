import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/assistant_tools.dart';
import 'package:lilygobox/features/assistant/data/local_process_runner.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';

Map<String, Object?> command(
  String script,
  String directory, {
  int timeout = 10,
  int yieldMs = 5000,
}) => {
  'executable': Platform.isWindows ? 'powershell.exe' : '/bin/sh',
  'arguments': Platform.isWindows
      ? ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script]
      : ['-c', script],
  'working_directory': directory,
  'reason': 'Verify local execution',
  'timeout_seconds': timeout,
  'yield_ms': yieldMs,
};

void main() {
  late Directory root;
  late AssistantTools tools;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lilygobox-process-');
    tools = AssistantTools();
  });
  tearDown(() async {
    await tools.dispose();
    await root.delete(recursive: true);
  });

  test(
    'commands use one execution permission, independent of model declarations',
    () async {
      final prepared = await tools.prepare('run_command', {
        ...command('echo harmless', root.path),
        'capabilities': ['execution'],
      });
      expect(await tools.requiredApprovals(prepared, AiPermissions()), [
        AiPermissionCategory.execution,
      ]);
      final configured = AiPermissions(
        mode: AiApprovalMode.custom,
        execution: true,
        fullFiles: false,
        network: false,
      );
      expect(await tools.requiredApprovals(prepared, configured), isEmpty);
      expect(await tools.isAllowed(prepared, configured), isTrue);
      expect(
        await tools.requiredApprovals(
          prepared,
          AiPermissions(
            mode: AiApprovalMode.custom,
            execution: false,
            fullFiles: true,
            network: true,
          ),
        ),
        [AiPermissionCategory.execution],
      );
    },
  );

  test(
    'full file access is custom-mode only and does not require folder grants',
    () async {
      final path = '${root.path}/file.txt';
      expect(
        await AiPermissions(fullFiles: true).allowsFile(path, write: true),
        isFalse,
      );
      final full = AiPermissions(mode: AiApprovalMode.custom, fullFiles: true);
      expect(await full.allowsFile(path, write: true), isTrue);
      expect(await full.allowsFile(path, write: false), isTrue);
      final missing = await tools.requiredApprovals(
        await tools.prepare('write_file', {
          'path': path,
          'content': 'hello',
          'expected_content': null,
        }),
        full,
      );
      expect(missing, isEmpty);
    },
  );

  test(
    'command arguments are frozen and unsupported directories fail before approval',
    () async {
      final args = command('echo hello', root.path);
      final prepared = await tools.prepare('run_command', args);
      (args['arguments'] as List).clear();
      expect(prepared.arguments['arguments'], isNotEmpty);
      await expectLater(
        tools.prepare('run_command', {
          ...command('echo hello', '${root.path}/missing'),
        }),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        tools.prepare('run_command', {
          ...command('echo hello', root.path),
          'timeout_seconds': 0,
        }),
        throwsFormatException,
      );
    },
  );

  Future<String> executeApproved(
    AiPreparedTool tool, {
    bool Function()? isCancelled,
  }) => tools.execute(
    tool,
    commandSafetyApproved: true,
    isCancelled: isCancelled,
  );

  Future<Map<String, dynamic>> finish(Map<String, dynamic> result) async {
    for (var i = 0; result['running'] == true && i < 20; i++) {
      final poll = await tools.prepare('read_process', {
        'process_id': result['process_id'],
        'wait_ms': 1000,
      });
      result = jsonDecode(await executeApproved(poll)) as Map<String, dynamic>;
    }
    expect(result['running'], isFalse);
    return result;
  }

  test(
    'executes a real process and reports stdout, stderr, exit code and cursor',
    () async {
      final script = Platform.isWindows
          ? "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Write-Output 'output-marker'; [Console]::Error.WriteLine('error-marker'); exit 7"
          : "printf 'output-marker'; printf 'error-marker' >&2; exit 7";
      final result = await finish(
        jsonDecode(
              await executeApproved(
                await tools.prepare('run_command', command(script, root.path)),
              ),
            )
            as Map<String, dynamic>,
      );
      expect(result['ok'], isFalse);
      expect(result['exit_code'], 7);
      expect(result['output'], contains('output-marker'));
      expect(result['output'], contains('error-marker'));
      final tail =
          jsonDecode(
                await executeApproved(
                  await tools.prepare('read_process', {
                    'process_id': result['process_id'],
                    'cursor': result['output_cursor'],
                    'wait_ms': 0,
                  }),
                ),
              )
              as Map;
      expect(tail['output'], isEmpty);
    },
  );

  test(
    'long processes can receive stdin and are polled without new approvals',
    () async {
      final script = Platform.isWindows
          ? r'$line = [Console]::ReadLine(); Write-Output $line'
          : r'read line; printf "%s" "$line"';
      final started =
          jsonDecode(
                await executeApproved(
                  await tools.prepare(
                    'run_command',
                    command(script, root.path, yieldMs: 0),
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(started['running'], isTrue);
      final input = await tools.prepare('write_process_input', {
        'process_id': started['process_id'],
        'input': 'stdin-marker\n',
      });
      expect(await tools.requiredApprovals(input, AiPermissions()), isEmpty);
      await executeApproved(input);
      final result = await finish(started);
      expect(result['output'], contains('stdin-marker'));
      expect(result['exit_code'], 0);
      await expectLater(
        tools
            .prepare('read_process', {'process_id': 'other'})
            .then((tool) => executeApproved(tool)),
        throwsStateError,
      );
    },
  );

  test('output buffer stays bounded and reports truncation', () async {
    final script = Platform.isWindows
        ? "[Console]::Write(('x' * 80000))"
        : "head -c 80000 /dev/zero | tr '\\0' x";
    final result = await finish(
      jsonDecode(
            await executeApproved(
              await tools.prepare('run_command', command(script, root.path)),
            ),
          )
          as Map<String, dynamic>,
    );
    expect(
      (result['output'] as String).length,
      lessThanOrEqualTo(LocalProcessRunner.maxOutputCharacters),
    );
    expect(result['output_truncated'], isTrue);
    expect(result['output_cursor'], greaterThanOrEqualTo(80000));
  });

  test(
    'timeouts terminate the process and preserve the failure result',
    () async {
      final script = Platform.isWindows
          ? 'Start-Sleep -Seconds 30'
          : 'sleep 30';
      final result = await finish(
        jsonDecode(
              await executeApproved(
                await tools.prepare(
                  'run_command',
                  command(script, root.path, timeout: 1),
                ),
              ),
            )
            as Map<String, dynamic>,
      );
      expect(result['timed_out'], isTrue);
      expect(result['ok'], isFalse);
    },
  );

  test(
    'cancellation during process startup cannot leave a running command',
    () async {
      final prepared = await tools.prepare(
        'run_command',
        command(
          Platform.isWindows ? 'Start-Sleep -Seconds 30' : 'sleep 30',
          root.path,
          yieldMs: 0,
        ),
      );
      final launching = executeApproved(prepared);
      final assertion = expectLater(launching, throwsStateError);
      await tools.cancelProcesses();
      await assertion;
    },
  );

  test(
    'cancelling a running command terminates it and exposes stopped state',
    () async {
      final started =
          jsonDecode(
                await executeApproved(
                  await tools.prepare(
                    'run_command',
                    command(
                      Platform.isWindows
                          ? 'Start-Sleep -Seconds 30'
                          : 'sleep 30',
                      root.path,
                      yieldMs: 0,
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      await tools.cancelProcesses();
      final result = await finish(started);
      expect(result['stopped'], isTrue);
      expect(result['ok'], isFalse);
    },
  );

  test(
    'explicit stop is a successful operation and releases the process',
    () async {
      final started =
          jsonDecode(
                await executeApproved(
                  await tools.prepare(
                    'run_command',
                    command(
                      Platform.isWindows
                          ? 'Start-Sleep -Seconds 30'
                          : 'sleep 30',
                      root.path,
                      yieldMs: 0,
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final result =
          jsonDecode(
                await executeApproved(
                  await tools.prepare('stop_process', {
                    'process_id': started['process_id'],
                  }),
                ),
              )
              as Map;
      expect(result['ok'], isTrue);
      expect(result['stopped'], isTrue);
      expect(result['running'], isFalse);
    },
  );

  test(
    'clearing a conversation invalidates previous process handles and logs',
    () async {
      final started =
          jsonDecode(
                await executeApproved(
                  await tools.prepare(
                    'run_command',
                    command('echo private-marker', root.path),
                  ),
                ),
              )
              as Map<String, dynamic>;
      await tools.cancelProcesses(forget: true);
      await expectLater(
        executeApproved(
          await tools.prepare('read_process', {
            'process_id': started['process_id'],
            'wait_ms': 0,
          }),
        ),
        throwsStateError,
      );
    },
  );
}
