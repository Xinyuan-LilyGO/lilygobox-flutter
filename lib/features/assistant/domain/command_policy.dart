import 'dart:convert';

/// 命令规则只约束当前可分析的调用，不替代操作系统沙箱。
enum AiCommandDecision { allow, prompt, forbidden }

enum AiCommandRisk { forceDelete, discardChanges, diskWrite, opaqueScript }

enum AiCommandPolicyProblem {
  forbidden,
  invalidRules,
  approvalRequired,
  changed,
}

class AiCommandPolicyFailure implements Exception {
  const AiCommandPolicyFailure(this.problem, {this.rules = const []});
  final AiCommandPolicyProblem problem;
  final List<String> rules;
  Map<String, Object?> toJson() => {
    'ok': false,
    'error_code': 'command_${problem.name}',
    if (rules.isNotEmpty) 'rules': rules,
  };
  @override
  String toString() => 'Command policy: ${problem.name}';
}

class AiCommandRule {
  AiCommandRule({required List<String> prefix, required this.decision})
    : prefix = List.unmodifiable(prefix);
  final List<String> prefix;
  final AiCommandDecision decision;
  String get label => jsonEncode(prefix);
}

class AiCommandAssessment {
  AiCommandAssessment({
    required this.decision,
    required List<AiCommandRisk> risks,
    required List<String> rules,
    required this.revision,
  }) : risks = List.unmodifiable(risks),
       rules = List.unmodifiable(rules);
  final AiCommandDecision decision;
  final List<AiCommandRisk> risks;
  final List<String> rules;
  final String revision;
  bool get needsApproval => decision == AiCommandDecision.prompt;
}

class AiCommandPolicy {
  AiCommandPolicy({List<AiCommandRule> rules = const [], this.revision = ''})
    : rules = List.unmodifiable(rules);
  final List<AiCommandRule> rules;
  final String revision;

  factory AiCommandPolicy.fromJson(Object? json, {String revision = ''}) {
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json.keys.any((key) => key != 'version' && key != 'rules') ||
        json['rules'] is! List ||
        (json['rules'] as List).length > 256) {
      throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
    }
    final rules = <AiCommandRule>[];
    for (final value in json['rules'] as List) {
      if (value is! Map<String, dynamic> ||
          value.keys.any((key) => key != 'prefix' && key != 'decision') ||
          value['prefix'] is! List ||
          (value['prefix'] as List).isEmpty ||
          (value['prefix'] as List).length > 64 ||
          (value['prefix'] as List).any(
            (part) =>
                part is! String ||
                part.isEmpty ||
                part.length > 1024 ||
                part.contains(String.fromCharCode(0)),
          ) ||
          !AiCommandDecision.values.any(
            (item) => item.name == value['decision'],
          )) {
        throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
      }
      rules.add(
        AiCommandRule(
          prefix: (value['prefix'] as List).cast<String>(),
          decision: AiCommandDecision.values.firstWhere(
            (item) => item.name == value['decision'],
          ),
        ),
      );
    }
    return AiCommandPolicy(rules: rules, revision: revision);
  }

  AiCommandAssessment assess(
    String executable,
    List<String> arguments, {
    required bool windows,
  }) {
    var decision = AiCommandDecision.allow;
    final risks = <AiCommandRisk>{};
    final matched = <String>{};
    void risk(AiCommandRisk value) {
      risks.add(value);
      if (decision.index < AiCommandDecision.prompt.index) {
        decision = AiCommandDecision.prompt;
      }
    }

    void visit(List<String> command, int depth) {
      if (command.isEmpty) return;
      if (depth > 8) {
        risk(AiCommandRisk.opaqueScript);
        return;
      }
      for (final rule in rules) {
        if (_matches(rule.prefix, command, windows)) {
          matched.add(rule.label);
          if (rule.decision.index > decision.index) decision = rule.decision;
        }
      }
      final name = _name(command.first).toLowerCase();
      final args = command.skip(1).toList();
      final lower = args.map((arg) => arg.toLowerCase()).toList();
      final force = lower.any(
        (arg) =>
            arg == '--force' ||
            arg == '--recursive' ||
            RegExp(r'^-[a-z]*[fr][a-z]*$').hasMatch(arg),
      );
      if ((name == 'rm' && force) ||
          (const {
                'remove-item',
                'ri',
                'erase',
                'del',
                'rd',
                'rmdir',
              }.contains(name) &&
              lower.any(
                (arg) =>
                    arg == '-force' ||
                    arg == '-recurse' ||
                    arg == '-r' ||
                    RegExp(r'^-fo(?:r(?:c(?:e)?)?)?$').hasMatch(arg) ||
                    arg == '-f' ||
                    arg == '/s' ||
                    arg == '/f' ||
                    arg == '/q',
              ))) {
        risk(AiCommandRisk.forceDelete);
      }
      if (name == 'git') {
        final gitArgs = _gitArguments(args);
        if (gitArgs.length != args.length && gitArgs.isNotEmpty) {
          visit([command.first, ...gitArgs], depth + 1);
        }
        if (gitArgs.isNotEmpty) {
          final action = gitArgs.first;
          final flags = gitArgs.skip(1).toList();
          if ((action == 'reset' && flags.contains('--hard')) ||
              (action == 'checkout' &&
                  (flags.contains('--') ||
                      flags.contains('-f') ||
                      flags.contains('--force'))) ||
              (action == 'clean' &&
                  flags.any(
                    (arg) =>
                        arg == '--force' ||
                        RegExp(r'^-[a-z]*f[a-z]*$').hasMatch(arg),
                  )) ||
              (action == 'restore' &&
                  !flags.contains('--help') &&
                  !flags.contains('-h'))) {
            risk(AiCommandRisk.discardChanges);
          }
        }
      }
      if (const {
            'format',
            'format-volume',
            'clear-disk',
            'initialize-disk',
            'diskpart',
            'wipefs',
            'fdisk',
            'sfdisk',
            'parted',
          }.contains(name) ||
          name == 'mkfs' ||
          name.startsWith('mkfs.') ||
          (name == 'dd' &&
              args.any(
                (arg) =>
                    arg.startsWith('of=/dev/') ||
                    arg.toLowerCase().contains('physicaldrive'),
              ))) {
        risk(AiCommandRisk.diskWrite);
      }
      if (const {
            'eval',
            'invoke-expression',
            'iex',
            'invoke-command',
            'icm',
            'start-process',
            'saps',
            'start',
            'call',
            'xargs',
            'forfiles',
            'wsl',
            'ssh',
            'docker',
          }.contains(name) ||
          (name == 'find' && args.any((arg) => arg.startsWith('-exec'))) ||
          (name == 'env' &&
              args.any(
                (arg) => arg == '-S' || arg.startsWith('--split-string'),
              ))) {
        risk(AiCommandRisk.opaqueScript);
      }
      if (const {
        'sudo',
        'doas',
        'env',
        'command',
        'exec',
        'nohup',
      }.contains(name)) {
        var i = 0;
        while (i < args.length) {
          final arg = args[i];
          if (arg == '--') {
            i++;
            break;
          }
          if ((name == 'sudo' &&
                  const {'-u', '-g', '-h', '-p'}.contains(arg)) ||
              (name == 'env' &&
                  const {'-u', '--unset', '-C', '--chdir'}.contains(arg))) {
            i += 2;
            continue;
          }
          if (arg.startsWith('-') ||
              (name == 'env' &&
                  RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(arg))) {
            i++;
            continue;
          }
          break;
        }
        if (i < args.length) {
          visit(args.sublist(i), depth + 1);
        } else {
          risk(AiCommandRisk.opaqueScript);
        }
        return;
      }
      final shell = const {
        'sh',
        'bash',
        'dash',
        'zsh',
        'ksh',
        'cmd',
        'powershell',
        'pwsh',
      }.contains(name);
      if (shell) {
        String? script;
        final powershell = name == 'powershell' || name == 'pwsh';
        for (var i = 0; i < args.length; i++) {
          final flag = args[i].toLowerCase();
          final encoded =
              powershell &&
              const {'-enc', '-e', '-ec', '-encodedcommand'}.contains(flag);
          final isCommand = powershell
              ? const {'-c', '-command'}.contains(flag)
              : name == 'cmd'
              ? const {'/c', '/k', '/r'}.contains(flag)
              : RegExp(r'^-[a-z]*c[a-z]*$').hasMatch(flag);
          if (encoded || isCommand) {
            if (i + 1 >= args.length) break;
            if (encoded) {
              try {
                final bytes = base64Decode(args[i + 1]);
                if (bytes.length.isOdd) throw const FormatException();
                script = String.fromCharCodes(
                  List.generate(
                    bytes.length ~/ 2,
                    (j) => bytes[j * 2] | bytes[j * 2 + 1] << 8,
                  ),
                );
              } catch (_) {
                risk(AiCommandRisk.opaqueScript);
              }
            } else {
              script = powershell || name == 'cmd'
                  ? args.sublist(i + 1).join(' ')
                  : args[i + 1];
            }
            break;
          }
        }
        if (script == null) {
          risk(AiCommandRisk.opaqueScript);
          return;
        }
        final parsed = _splitScript(
          script,
          powershell: powershell,
          cmd: name == 'cmd',
        );
        if (parsed.opaque) risk(AiCommandRisk.opaqueScript);
        for (final words in parsed.commands) {
          visit(words, depth + 1);
        }
        return;
      }
      if (RegExp(
            r'^(python\d*(?:\.\d+)?|node|nodejs|ruby|perl|php|dart|wscript|cscript|mshta)$',
          ).hasMatch(name) ||
          RegExp(
            r'\.(ps1|bat|cmd|sh|py|js|vbs)$',
            caseSensitive: false,
          ).hasMatch(command.first)) {
        risk(AiCommandRisk.opaqueScript);
      }
    }

    visit([executable, ...arguments], 0);
    return AiCommandAssessment(
      decision: decision,
      risks: risks.toList(),
      rules: matched.toList(),
      revision: revision,
    );
  }
}

String _name(String value) {
  final name = value.replaceAll('\\', '/').split('/').last;
  return (name.toLowerCase().endsWith('.exe') ||
          name.toLowerCase().endsWith('.com'))
      ? name.substring(0, name.length - 4)
      : name;
}

bool _matches(List<String> prefix, List<String> command, bool windows) {
  if (prefix.length > command.length) return false;
  var expected = prefix.first;
  var actual = command.first;
  if (expected.contains('/') || expected.contains('\\')) {
    if (windows) {
      expected = expected.replaceAll('\\', '/');
      actual = actual.replaceAll('\\', '/');
    }
  } else {
    expected = _name(expected);
    actual = _name(actual);
  }
  if (windows) {
    expected = expected.toLowerCase();
    actual = actual.toLowerCase();
  }
  if (expected != actual) return false;
  for (var i = 1; i < prefix.length; i++) {
    if (prefix[i] != command[i]) return false;
  }
  return true;
}

List<String> _gitArguments(List<String> args) {
  var i = 0;
  while (i < args.length && args[i].startsWith('-')) {
    if (const {
      '-C',
      '-c',
      '--git-dir',
      '--work-tree',
      '--namespace',
    }.contains(args[i])) {
      i += 2;
    } else {
      i++;
    }
  }
  return i < args.length ? args.sublist(i) : const [];
}

/// 只拆分可确定的字面量命令；遇到变量、重定向和脚本结构时额外要求批准。
({List<List<String>> commands, bool opaque}) _splitScript(
  String script, {
  required bool powershell,
  required bool cmd,
}) {
  final commands = <List<String>>[];
  var words = <String>[];
  var word = StringBuffer();
  var started = false;
  var quote = '';
  var opaque = false;
  void flushWord() {
    if (started) {
      words.add(word.toString());
      word = StringBuffer();
      started = false;
    }
  }

  void flushCommand() {
    flushWord();
    if (words.isNotEmpty) commands.add(words);
    words = <String>[];
  }

  for (var i = 0; i < script.length; i++) {
    final c = script[i];
    if (quote.isNotEmpty) {
      if (c == quote) {
        if (powershell &&
            quote == "'" &&
            i + 1 < script.length &&
            script[i + 1] == "'") {
          word.write(c);
          i++;
        } else {
          quote = '';
        }
      } else {
        if (quote == '"' &&
            (c == r'$' ||
                c == String.fromCharCode(96) ||
                (cmd && c == '%') ||
                (!powershell && !cmd && c == '\\'))) {
          opaque = true;
        }
        word.write(c);
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      started = true;
      continue;
    }
    if (c == '\\' && !powershell && !cmd) {
      if (i + 1 < script.length) {
        word.write(script[++i]);
        started = true;
      } else {
        opaque = true;
      }
      continue;
    }
    if ((powershell && c == String.fromCharCode(96)) || (cmd && c == '^')) {
      opaque = true;
      if (i + 1 < script.length) {
        word.write(script[++i]);
        started = true;
      }
      continue;
    }
    if (c == ';' || c == '\n' || c == '\r' || c == '|' || c == '&') {
      flushCommand();
      continue;
    }
    if (c.trim().isEmpty) {
      flushWord();
      continue;
    }
    if (const {r'$', '(', ')', '{', '}', '<', '>', '*', '?', '%'}.contains(c)) {
      opaque = true;
    }
    if (c == '#') opaque = true;
    word.write(c);
    started = true;
  }
  flushCommand();
  return (commands: commands, opaque: opaque || quote.isNotEmpty);
}
