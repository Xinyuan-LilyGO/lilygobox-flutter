/*
 * @Description: 校验并执行 AI 的时间、网页与本地文件工具。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-12 15:00:41
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/permissions.dart';
import 'webpage_reader.dart';

/// 固化待批准参数，执行前再次校验实际路径，防止批准期间目标发生变化。
class AiPreparedTool {
  const AiPreparedTool(this.name, this.arguments, {this.target});
  final String name;
  final Map<String, Object?> arguments;
  final String? target;
  bool get writesFile => name == 'write_file';
}

class AssistantTools {
  static const maxFileBytes = 1024 * 1024;

  Future<AiPreparedTool> prepare(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final args = Map<String, Object?>.unmodifiable(arguments);
    if (const {'read_file', 'list_directory', 'write_file'}.contains(name)) {
      final path = args['path'];
      if (path is! String) throw const FormatException('Missing path');
      final target = await canonicalAiPath(path);
      if (name == 'write_file') {
        if (isProtectedAiWritePath(path) || isProtectedAiWritePath(target)) {
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
    if (!const {'read_webpage', 'get_current_time'}.contains(name)) {
      throw const FormatException('Unsupported tool');
    }
    return AiPreparedTool(name, args);
  }

  Future<bool> isAllowed(
    AiPreparedTool tool,
    AiPermissions permissions,
  ) async => tool.target != null
      ? permissions.allowsFile(
          tool.arguments['path'] as String,
          write: tool.writesFile,
        )
      : tool.name == 'read_webpage'
      ? permissions.allowsNetwork()
      : true;

  Future<String> execute(
    AiPreparedTool tool, {
    Future<void>? abort,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) {
        throw StateError('Cancelled before execution');
      }
    }

    checkCancelled();
    if (tool.target != null &&
        await canonicalAiPath(tool.arguments['path'] as String) !=
            tool.target) {
      throw const FileSystemException('Target changed after approval');
    }
    switch (tool.name) {
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
          if (await canonicalAiPath(tool.arguments['path'] as String) !=
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
