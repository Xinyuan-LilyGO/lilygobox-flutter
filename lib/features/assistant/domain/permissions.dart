/*
 * @Description: 定义 AI 会话批准策略与文件访问范围并校验授权路径。
 * @Author: LILYGO_L
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-11 18:24:14
 */

import 'dart:io';

/// 批准策略与文件访问范围独立，未命中授权范围时仍需要逐次批准。
enum AiApprovalMode { onRequest, custom }

enum AiFileAccess { none, readOnly, readWrite }

/// 本机命令统一授权；文件与网页工具分别检查各自的访问范围。
enum AiPermissionCategory { execution, fullFiles, network }

class AiPermissions {
  AiPermissions({
    this.mode = AiApprovalMode.onRequest,
    this.network = true,
    this.execution = false,
    bool commandNoApproval = false,
    this.fullFiles = false,
    this.files = AiFileAccess.readOnly,
    List<String> folders = const [],
    Map<String, AiFileAccess> folderAccess = const {},
  }) : commandNoApproval = execution && commandNoApproval,
       folders = List.unmodifiable(folders),
       folderAccess = Map.unmodifiable({
         for (final folder in folders) folder: folderAccess[folder] ?? files,
       });

  final AiApprovalMode mode;
  final bool network;
  final bool execution;

  /// 仅在自定义模式且允许运行本机命令时跳过命令确认。
  final bool commandNoApproval;
  bool get skipsCommandApproval =>
      allowsCategory(AiPermissionCategory.execution) && commandNoApproval;
  final bool fullFiles;

  bool allowsCategory(AiPermissionCategory category) =>
      mode == AiApprovalMode.custom &&
      switch (category) {
        AiPermissionCategory.execution => execution,
        AiPermissionCategory.fullFiles => fullFiles,
        AiPermissionCategory.network => network,
      };
  final AiFileAccess files;
  final List<String> folders;

  /// 每个目录独立保存权限；files 只作为新增目录的默认值。
  final Map<String, AiFileAccess> folderAccess;

  AiFileAccess accessForFolder(String folder) => folderAccess[folder]!;

  AiPermissions copyWith({
    AiApprovalMode? mode,
    bool? network,
    bool? execution,
    bool? commandNoApproval,
    bool? fullFiles,
    AiFileAccess? files,
    List<String>? folders,
    Map<String, AiFileAccess>? folderAccess,
  }) => AiPermissions(
    mode: mode ?? this.mode,
    network: network ?? this.network,
    execution: execution ?? this.execution,
    commandNoApproval: commandNoApproval ?? this.commandNoApproval,
    fullFiles: fullFiles ?? this.fullFiles,
    files: files ?? this.files,
    folders: folders ?? this.folders,
    folderAccess: folderAccess ?? this.folderAccess,
  );

  bool allowsNetwork() => mode == AiApprovalMode.onRequest || network;

  Future<bool> allowsFile(String path, {required bool write}) async {
    if (mode != AiApprovalMode.custom) return false;
    final target = await canonicalAiPath(path);
    if (fullFiles) return true;
    final lexicalTarget = _absolute(path);
    // 优先采用最具体的目录设置，避免父目录授权覆盖子目录的限制。
    final ordered = [...folders]
      ..sort((a, b) => _absolute(b).length.compareTo(_absolute(a).length));
    for (final folder in ordered) {
      if (!_within(lexicalTarget, _absolute(folder))) continue;
      final root = await canonicalAiPath(folder);
      // 同时检查词法路径和实际路径，禁止通过目录链接借用另一目录的授权。
      if (!_within(target, root)) return false;
      final access = accessForFolder(folder);
      return access != AiFileAccess.none &&
          (!write || access == AiFileAccess.readWrite);
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
