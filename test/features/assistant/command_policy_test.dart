import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/command_policy.dart';

void main() {
  AiCommandAssessment assess(
    List<String> words, {
    AiCommandPolicy? policy,
    bool windows = true,
  }) => (policy ?? AiCommandPolicy()).assess(
    words.first,
    words.skip(1).toList(),
    windows: windows,
  );
  AiCommandPolicy policy(List<Map<String, Object?>> rules) =>
      AiCommandPolicy.fromJson({'version': 1, 'rules': rules});

  for (final words in <List<String>>[
    ['git', 'status'],
    ['git', 'diff'],
    ['git', 'checkout', 'main'],
    ['git', 'reset', '--soft', 'HEAD~1'],
    ['esptool', '--help'],
    ['powershell.exe', '-NoProfile', '-Command', 'Write-Output "rm -rf /"'],
    ['cmd.exe', '/c', 'echo "git reset --hard"'],
    ['/bin/sh', '-c', "echo 'Remove-Item -Force x'"],
  ]) {
    test('ordinary arguments are not treated as destructive: $words', () {
      expect(assess(words).decision, AiCommandDecision.allow);
    });
  }
  for (final words in <List<String>>[
    ['rm', '-rf', 'target'],
    ['rm', '-r', 'target'],
    ['rm', '--recursive', 'target'],
    ['/bin/rm', '--force', 'target'],
    ['Remove-Item', '-Recurse', '-Force', 'target'],
    ['powershell.exe', '-Command', 'Remove-Item -Force "target"'],
    ['cmd.exe', '/c', 'rmdir /s /q target'],
    ['sudo', '-u', 'root', 'rm', '-rf', 'target'],
    ['env', 'X=1', 'rm', '--force', 'target'],
    ['git', '-C', 'repo', 'reset', '--hard'],
    ['git', 'checkout', '--', 'file'],
    ['git', 'clean', '-fdx'],
    ['git', 'restore', 'file'],
    ['format.com', 'D:'],
    ['diskpart'],
    ['dd', 'if=image.bin', 'of=/dev/sda'],
    ['sh', '-c', 'echo ready && git reset --hard'],
    ['pwsh', '-Command', 'Write-Output ready; Remove-Item -Force target'],
  ]) {
    test('dangerous invocation requires approval: $words', () {
      expect(assess(words).decision, AiCommandDecision.prompt);
    });
  }
  for (final words in <List<String>>[
    ['python', '-c', 'print(1)'],
    ['node', 'script.js'],
    ['dart', 'script.dart'],
    ['powershell', '-File', 'script.ps1'],
    ['powershell', '-EncodedCommand', 'invalid!'],
    ['sh', '-c', r'$command "$target"'],
    ['pwsh', '-Command', r'& $tool $args'],
    ['sh', '-c', 'echo hello > file'],
    ['cmd', '/c', r'%TOOL% %ARGS%'],
    ['cmd', '/c', r'"%TOOL%" /arg'],
    ['env', '-S', 'git reset --hard'],
    [
      'powershell',
      '-Command',
      "Start-Process git -ArgumentList 'reset --hard'",
    ],
  ]) {
    test('opaque script requires approval: $words', () {
      expect(assess(words).risks, contains(AiCommandRisk.opaqueScript));
    });
  }
  test('PowerShell encoded literal commands are inspected', () {
    final script = 'Remove-Item -Force target';
    final bytes = script.codeUnits
        .expand((unit) => [unit & 255, unit >> 8])
        .toList();
    final result = assess(['powershell.exe', '-enc', base64Encode(bytes)]);
    expect(result.risks, contains(AiCommandRisk.forceDelete));
  });
  test('strictest rule wins and allow cannot suppress built-in risks', () {
    final rules = policy([
      {
        'prefix': ['git'],
        'decision': 'forbidden',
      },
      {
        'prefix': ['git', 'status'],
        'decision': 'allow',
      },
      {
        'prefix': ['git', 'status'],
        'decision': 'prompt',
      },
    ]);
    expect(
      assess(['git', 'status'], policy: rules).decision,
      AiCommandDecision.forbidden,
    );
    expect(
      assess(
        ['rm', '-rf', 'target'],
        policy: policy([
          {
            'prefix': ['rm'],
            'decision': 'allow',
          },
        ]),
      ).decision,
      AiCommandDecision.prompt,
    );
  });
  test('literal arguments use token boundaries, not substring matching', () {
    final rules = policy([
      {
        'prefix': ['git', 'reset', '--hard'],
        'decision': 'forbidden',
      },
    ]);
    expect(
      assess(['git', 'reset', '--hard'], policy: rules).decision,
      AiCommandDecision.forbidden,
    );
    expect(
      assess(['git', 'reset', '--harder'], policy: rules).decision,
      AiCommandDecision.allow,
    );
    expect(
      assess(['echo', 'git reset --hard'], policy: rules).decision,
      AiCommandDecision.allow,
    );
  });
  test(
    'nested commands and Git global options cannot hide literal forbidden calls',
    () {
      final rules = policy([
        {
          'prefix': ['git', 'reset', '--hard'],
          'decision': 'forbidden',
        },
      ]);
      for (final words in <List<String>>[
        ['powershell', '-Command', 'git status; git reset --hard'],
        ['cmd', '/c', 'echo ready && git reset --hard'],
        ['sh', '-c', 'git status\ngit reset --hard'],
        ['env', 'X=1', 'git', '-C', 'repo', 'reset', '--hard'],
        ['git', '--git-dir=repo/.git', 'reset', '--hard'],
      ]) {
        expect(
          assess(words, policy: rules).decision,
          AiCommandDecision.forbidden,
          reason: words.toString(),
        );
      }
    },
  );
  test(
    'Windows command names are case insensitive, arguments remain exact',
    () {
      final rules = policy([
        {
          'prefix': ['git', 'status'],
          'decision': 'forbidden',
        },
      ]);
      expect(
        assess([r'C:\Tools\GIT.EXE', 'status'], policy: rules).decision,
        AiCommandDecision.forbidden,
      );
      expect(
        assess(['git', 'STATUS'], policy: rules).decision,
        AiCommandDecision.allow,
      );
      expect(
        assess(['GIT', 'status'], policy: rules, windows: false).decision,
        AiCommandDecision.allow,
      );
    },
  );
  test('absolute executable rules only match that executable path', () {
    final rules = policy([
      {
        'prefix': [r'C:\Tools\git.exe'],
        'decision': 'forbidden',
      },
    ]);
    expect(
      assess(['C:/Tools/git.exe', 'status'], policy: rules).decision,
      AiCommandDecision.forbidden,
    );
    expect(
      assess(['D:/Tools/git.exe', 'status'], policy: rules).decision,
      AiCommandDecision.allow,
    );
  });
  test(
    'deep wrappers require approval instead of silently skipping inspection',
    () {
      expect(
        assess([...List.filled(12, 'env'), 'echo', 'hi']).risks,
        contains(AiCommandRisk.opaqueScript),
      );
    },
  );
  test('malformed rules are rejected instead of silently ignored', () {
    for (final value in <Object?>[
      null,
      [],
      {'rules': []},
      {'version': 2, 'rules': []},
      {'version': 1, 'rules': [], 'unknown': true},
      {
        'version': 1,
        'rules': [
          {'prefix': [], 'decision': 'allow'},
        ],
      },
      {
        'version': 1,
        'rules': [
          {
            'prefix': ['git'],
            'decision': 'deny',
          },
        ],
      },
      {
        'version': 1,
        'rules': [
          {
            'prefix': [1],
            'decision': 'allow',
          },
        ],
      },
    ]) {
      expect(
        () => AiCommandPolicy.fromJson(value),
        throwsA(isA<AiCommandPolicyFailure>()),
      );
    }
  });
}
