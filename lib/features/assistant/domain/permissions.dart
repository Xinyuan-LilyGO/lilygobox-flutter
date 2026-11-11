/*
 * @Description: 定义 AI 会话批准策略与文件访问范围并校验授权路径。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-11 18:24:14
 */

import 'dart:io';

/// 批准策略与文件访问范围独立，未命中授权范围时仍需要逐次批准。
enum AiApprovalMode { onRequest, custom }

enum AiFileAccess { none, readOnly, readWrite }

class AiPermissions {
  AiPermissions({
    this.mode = AiApprovalMode.onRequest,
    this.network = true,
    this.files = AiFileAccess.readOnly,
    List<String> folders = const [],
  }) : folders = List.unmodifiable(folders);

  final AiApprovalMode mode;
  final bool network;
  final AiFileAccess files;
  final List<String> folders;

  bool allowsNetwork() => mode == AiApprovalMode.onRequest || network;

  Future<bool> allowsFile(String path, {required bool write}) async {
    if (mode != AiApprovalMode.custom ||
        files == AiFileAccess.none ||
        (write && files != AiFileAccess.readWrite)) {
      return false;
    }
    final target = await canonicalAiPath(path);
    for (final folder in folders) {
      final root = await canonicalAiPath(folder);
      // 同时检查词法路径和实际路径，禁止通过目录链接借用另一目录的授权。
      if (_within(target, root) &&
          _within(_absolute(path), _absolute(folder))) {
        return true;
      }
    }
    return false;
  }
}

String _absolute(String path) =>
    File(path).absolute.uri.normalizePath().toFilePath();
String _comparison(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;
bool _within(String path, String root) {
  final candidate = _comparison(path);
  final parent = _comparison(root);
  return candidate == parent ||
      candidate.startsWith(
        parent.endsWith(Platform.pathSeparator)
            ? parent
            : '$parent${Platform.pathSeparator}',
      );
}

/// 新文件沿父目录解析；已有符号链接必须按实际目标检查。
Future<String> canonicalAiPath(String path) async {
  if (path.trim().isEmpty || !File(path).isAbsolute) {
    throw const FormatException('An absolute path is required.');
  }
  if (Platform.isWindows) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (!RegExp(r'^[a-zA-Z]:/').hasMatch(normalized) ||
        parts
            .skip(1)
            .any(
              (part) =>
                  part.contains(':') ||
                  (part != '.' &&
                      part != '..' &&
                      (part.endsWith('.') || part.endsWith(' '))) ||
                  RegExp(
                    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                    caseSensitive: false,
                  ).hasMatch(part),
            )) {
      throw const FormatException(
        'Only ordinary local file paths are supported',
      );
    }
  }
  final absolute = _absolute(path);
  final type = await FileSystemEntity.type(absolute, followLinks: false);
  if (type == FileSystemEntityType.link) {
    return Link(absolute).resolveSymbolicLinks();
  }
  if (type == FileSystemEntityType.file) {
    return File(absolute).resolveSymbolicLinks();
  }
  if (type == FileSystemEntityType.directory) {
    return Directory(absolute).resolveSymbolicLinks();
  }
  final parent = File(absolute).parent;
  if (parent.path == absolute) {
    throw const FileSystemException('Path does not exist');
  }
  final resolved = await canonicalAiPath(parent.path);
  final name = File(
    absolute,
  ).uri.pathSegments.where((part) => part.isNotEmpty).last;
  return '$resolved${resolved.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$name';
}

bool isProtectedAiWritePath(String path) {
  final segments = path.replaceAll('\\', '/').toLowerCase().split('/');
  return segments.any(
    const {'.git', '.codex', '.agents', '.aws', '.ssh'}.contains,
  );
}
