/*
 * @Description: 校验并执行 AI 的时间、网页与本地文件工具。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-12 15:00:41
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/command_policy.dart';
import '../domain/permissions.dart';
import 'command_policy_store.dart';
import 'local_process_runner.dart';
import 'webpage_reader.dart';

/// 固化待批准参数，执行前再次校验实际路径，防止批准期间目标发生变化。
class AiPreparedTool {
  const AiPreparedTool(
    this.name,
    this.arguments, {
    this.target,
    this.commandAssessment,
  });
  final String name;
  final Map<String, Object?> arguments;
  final String? target;
  final AiCommandAssessment? commandAssessment;
  bool get writesFile => name == 'write_file';
}

class AssistantTools {
  AssistantTools({AiCommandPolicyStore? commandPolicy})
    : _commandPolicy = commandPolicy ?? AiCommandPolicyStore();

  final AiCommandPolicyStore _commandPolicy;
  static const maxFileBytes = 1024 * 1024;
  final LocalProcessRunner _processes = LocalProcessRunner();
  int _generation = 0;
  bool _disposed = false;
  Future<void> _processCleanup = Future<void>.value();

  Future<void> cancelProcesses({bool forget = false}) {
    _generation++;
    return _processCleanup = _processes.cancelAll(forget: forget);
  }

  Future<void> dispose() {
    _disposed = true;
    return cancelProcesses(forget: true);
  }

  Future<List<AiPermissionCategory>> requiredApprovals(
    AiPreparedTool tool,
    AiPermissions permissions,
  ) async {
    if (tool.name == 'run_command') {
      // 命令统一检查执行权限；不按模型自报用途重复申请设备、安装等权限。
      final assessment = tool.commandAssessment!;
      _checkForbidden(assessment);
      return [
        if (!permissions.allowsCategory(AiPermissionCategory.execution) ||
            (assessment.needsApproval && !permissions.skipsCommandApproval))
          AiPermissionCategory.execution,
      ];
    }
    if (await isAllowed(tool, permissions)) return const [];
    return [
      tool.name == 'read_webpage'
          ? AiPermissionCategory.network
          : AiPermissionCategory.fullFiles,
    ];
  }

  void _checkForbidden(AiCommandAssessment assessment) {
    if (assessment.decision == AiCommandDecision.forbidden) {
      throw AiCommandPolicyFailure(
        AiCommandPolicyProblem.forbidden,
        rules: assessment.rules,
      );
    }
  }

  static int _integer(
    Map<String, Object?> args,
    String key,
    int fallback,
    int min,
    int max,
  ) {
    final value = args[key] ?? fallback;
    if (value is! int || value < min || value > max) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  Future<AiPreparedTool> prepare(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final args = Map<String, Object?>.unmodifiable(arguments);
    if (name == 'run_command') {
      final executable = args['executable'];
      final inputArgs = args['arguments'];
      final directory = args['working_directory'];
      final reason = args['reason'];
      if (executable is! String ||
          executable.trim().isEmpty ||
          executable.contains('\u0000') ||
          executable.length > 32768 ||
          inputArgs is! List ||
          inputArgs.length > 256 ||
          inputArgs.any(
            (item) =>
                item is! String ||
                item.contains('\u0000') ||
                item.length > 32768,
          ) ||
          directory is! String ||
          reason is! String ||
          reason.trim().isEmpty ||
          reason.length > 1000) {
        throw const FormatException('Invalid command arguments');
      }
      if (inputArgs.fold<int>(
            executable.length,
            (total, item) => total + (item as String).length,
          ) >
          65536) {
        throw const FormatException('Command arguments exceed the limit');
      }
      final target = await canonicalAiPath(directory);
      if (!await Directory(target).exists()) {
        throw const FileSystemException('Working directory does not exist');
      }
      final commandArgs = Map<String, Object?>.unmodifiable({
        'executable': executable,
        'arguments': List<String>.unmodifiable(inputArgs.cast<String>()),
        'working_directory': directory,
        'reason': reason,
        'timeout_seconds': _integer(args, 'timeout_seconds', 600, 1, 3600),
        'yield_ms': _integer(args, 'yield_ms', 1000, 0, 5000),
      });
      final assessment = await _commandPolicy.assess(commandArgs);
      _checkForbidden(assessment);
      return AiPreparedTool(
        name,
        commandArgs,
        target: target,
        commandAssessment: assessment,
      );
    }
    if (const {
      'read_process',
      'write_process_input',
      'stop_process',
    }.contains(name)) {
      final id = args['process_id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('Missing process id');
      }
      if (name == 'write_process_input' &&
          (args['input'] is! String ||
              (args['input'] as String).length > 16384)) {
        throw const FormatException('Invalid process input');
      }
      return AiPreparedTool(
        name,
        Map.unmodifiable({
          ...args,
          'cursor': _integer(args, 'cursor', 0, 0, 1 << 53),
          'wait_ms': _integer(args, 'wait_ms', 1000, 0, 5000),
        }),
      );
    }
    if (const {'read_file', 'list_directory', 'write_file'}.contains(name)) {
      final path = args['path'];
      if (path is! String) throw const FormatException('Missing path');
      final target = await canonicalAiPath(path);
      if (name == 'write_file') {
        final policyPath = await canonicalAiPath(_commandPolicy.file.path);
        bool samePath(String a, String b) =>
            Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;
        if (isProtectedAiWritePath(path) ||
            isProtectedAiWritePath(target) ||
            samePath(target, policyPath)) {
          throw const FileSystemException(
            'Protected application or repository metadata',
          );
        }
        if (!args.containsKey('expected_content') ||
            args['content'] is! String ||
            utf8.encode(args['content'] as String).length > maxFileBytes ||
            (args['expected_content'] != null &&
                (args['expected_content'] is! String ||
                    utf8.encode(args['expected_content'] as String).length >
                        maxFileBytes))) {
          throw const FormatException('Invalid file content');
        }
      }
      return AiPreparedTool(name, args, target: target);
    }
    if (name == 'read_webpage') WebpageReader.validateUri(args['url']);
    if (!const {
      'read_webpage',
      'get_current_time',
      'get_execution_environment',
    }.contains(name)) {
      throw const FormatException('Unsupported tool');
    }
    return AiPreparedTool(name, args);
  }

  Future<bool> isAllowed(AiPreparedTool tool, AiPermissions permissions) async {
    if (tool.name == 'run_command') {
      return (await requiredApprovals(tool, permissions)).isEmpty;
    }
    if (tool.target != null) {
      return permissions.allowsFile(
        tool.arguments['path'] as String,
        write: tool.writesFile,
      );
    }
    return tool.name != 'read_webpage' || permissions.allowsNetwork();
  }

  Future<String> execute(
    AiPreparedTool tool, {
    Future<void>? abort,
    bool Function()? isCancelled,
    bool commandSafetyApproved = false,
  }) async {
    final generation = _generation;
    void checkCancelled() {
      if (_disposed ||
          generation != _generation ||
          isCancelled?.call() == true) {
        throw StateError('Cancelled before execution');
      }
    }

    checkCancelled();
    if (tool.target != null &&
        await canonicalAiPath(
              (tool.arguments['path'] ?? tool.arguments['working_directory'])
                  as String,
            ) !=
            tool.target) {
      throw const FileSystemException('Target changed after approval');
    }
    switch (tool.name) {
      case 'get_execution_environment':
        return jsonEncode({
          'operating_system': Platform.operatingSystem,
          'working_directory': Directory.current.path,
          'shell': Platform.isWindows ? 'powershell.exe' : '/bin/sh',
          'command_execution':
              'unsandboxed; all capability categories require authorization',
        });
      case 'run_command':
        await _processCleanup;
        checkCancelled();
        final assessment = await _commandPolicy.assess(tool.arguments);
        _checkForbidden(assessment);
        if (assessment.revision != tool.commandAssessment?.revision) {
          throw const AiCommandPolicyFailure(AiCommandPolicyProblem.changed);
        }
        if (assessment.needsApproval && !commandSafetyApproved) {
          throw const AiCommandPolicyFailure(
            AiCommandPolicyProblem.approvalRequired,
          );
        }
        checkCancelled();
        return jsonEncode(
          await _processes.start({
            ...tool.arguments,
            'working_directory': tool.target!,
          }, isCancelled: isCancelled),
        );
      case 'read_process':
        return jsonEncode(await _processes.read(tool.arguments));
      case 'write_process_input':
        return jsonEncode(await _processes.input(tool.arguments));
      case 'stop_process':
        return jsonEncode(
          await _processes.stop(tool.arguments['process_id'] as String),
        );
      case 'get_current_time':
        final now = DateTime.now();
        return jsonEncode({
          'local_time': now.toIso8601String(),
          'timezone': now.timeZoneName,
          'utc_offset_minutes': now.timeZoneOffset.inMinutes,
        });
      case 'list_directory':
        final entries = <Map<String, String>>[];
        await for (final entry in Directory(
          tool.target!,
        ).list(followLinks: false)) {
          entries.add({
            'path': entry.path,
            'type': entry is Directory
                ? 'directory'
                : entry is Link
                ? 'link'
                : 'file',
          });
          if (entries.length >= 200) break;
        }
        return jsonEncode({'entries': entries, 'limit': 200});
      case 'read_file':
        final bytes = await File(tool.target!)
            .openRead(0, maxFileBytes + 1)
            .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
        if (bytes.length > maxFileBytes) {
          throw const FileSystemException('File exceeds 1 MiB');
        }
        return utf8.decode(bytes);
      case 'write_file':
        final file = File(tool.target!);
        final expected = tool.arguments['expected_content'];
        if (await file.exists()) {
          if (await file.length() > maxFileBytes ||
              expected == null ||
              await file.readAsString() != expected) {
            throw const FileSystemException(
              'File changed; read it again before writing',
            );
          }
        } else if (expected != null) {
          throw const FileSystemException('File no longer exists');
        }
        checkCancelled();
        // 使用同目录临时文件替换，避免原地写入通过硬链接修改其他目录中的文件。
        final staging = await file.parent.createTemp('.lilygobox-write-');
        try {
          final temporary = File(
            '${staging.path}${Platform.pathSeparator}content',
          );
          await temporary.writeAsString(
            tool.arguments['content'] as String,
            flush: true,
          );
          checkCancelled();
          if (await canonicalAiPath(
                (tool.arguments['path'] ?? tool.arguments['working_directory'])
                    as String,
              ) !=
              tool.target) {
            throw const FileSystemException('Target changed before writing');
          }
          checkCancelled();
          await temporary.rename(file.path);
        } finally {
          await staging.delete(recursive: true);
        }
        return jsonEncode({'written': tool.target});
      case 'read_webpage':
        return WebpageReader().read(tool.arguments['url'], abort: abort);
      default:
        throw const FormatException('Unsupported tool');
    }
  }
}
