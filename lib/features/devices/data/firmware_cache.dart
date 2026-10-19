import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 仅缓存校验完整的组件；提供给 HTTP 服务的始终是独立的临时副本。
class FirmwareCache {
  FirmwareCache({Directory? directory})
    : directory = directory ?? _defaultDirectory();

  final Directory directory;

  static Directory _defaultDirectory() {
    final environment = Platform.environment;
    final String? base;
    if (Platform.isWindows) {
      base = environment['LOCALAPPDATA'];
      return Directory(
        '${base ?? Directory.systemTemp.path}/LILYGO/lilygobox/cache/firmware',
      );
    } else if (Platform.isMacOS) {
      final userDirectory = environment['HOME'];
      base = userDirectory == null ? null : '$userDirectory/Library/Caches';
    } else {
      final userDirectory = environment['HOME'];
      base =
          environment['XDG_CACHE_HOME'] ??
          (userDirectory == null ? null : '$userDirectory/.cache');
    }
    return Directory('${base ?? Directory.systemTemp.path}/lilygobox/firmware');
  }

  File _file(
    String scope,
    String component,
    String version,
    int size,
    String hash,
  ) {
    final key = sha256.convert(
      utf8.encode('$scope|$component|$version|$size|${hash.toLowerCase()}'),
    );
    return File('${directory.path}/$key.bin');
  }

  Future<bool> contains(
    String scope,
    String component,
    String version,
    int size,
    String hash,
  ) async {
    final file = _file(scope, component, version, size, hash);
    try {
      if (!await file.exists()) return false;
      if (await file.length() == size &&
          (await sha256.bind(file.openRead()).first).toString() ==
              hash.toLowerCase()) {
        return true;
      }
      await file.delete();
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<bool> restore(
    String scope,
    String component,
    String version,
    int size,
    String hash,
    File target,
  ) async {
    if (!await contains(scope, component, version, size, hash)) return false;
    try {
      await _file(scope, component, version, size, hash).copy(target.path);
      // 复制后也校验，避免校验与复制之间文件被替换。
      return await target.length() == size &&
          (await sha256.bind(target.openRead()).first).toString() ==
              hash.toLowerCase();
    } on FileSystemException {
      return false;
    }
  }

  Future<void> store(
    String scope,
    String component,
    String version,
    int size,
    String hash,
    File source,
  ) async {
    File? temporary;
    try {
      await directory.create(recursive: true);
      final target = _file(scope, component, version, size, hash);
      final scratch = await directory.createTemp('.write-');
      temporary = await source.copy('${scratch.path}/firmware.part');
      if (await temporary.length() != size ||
          (await sha256.bind(temporary.openRead()).first).toString() !=
              hash.toLowerCase()) {
        return;
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      // 固件缓存限制为最近 8 个组件，活动传输使用副本，不受淘汰影响。
      final entries = await directory
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.bin'))
          .cast<File>()
          .toList();
      final dated = <(File, DateTime)>[];
      for (final file in entries) {
        dated.add((file, (await file.stat()).modified));
      }
      dated.sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in dated.skip(8)) {
        await entry.$1.delete();
      }
    } on FileSystemException {
      // 缓存不可写不应阻止已验证固件的本次更新。
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.parent.exists()) {
            await temporary.parent.delete(recursive: true);
          }
        } on FileSystemException {
          // 系统占用时留给缓存目录后续清理。
        }
      }
    }
  }
}
