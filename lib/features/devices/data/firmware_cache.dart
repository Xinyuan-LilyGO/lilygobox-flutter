import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/storage/cache_directories.dart';

enum FirmwareCacheStatus { missing, valid, invalid }

/// 仅缓存校验完整的组件；提供给 HTTP 服务的始终是独立的临时副本。
class FirmwareCache {
  FirmwareCache({Directory? directory})
    : directory = directory ?? AppCacheDirectories.firmware;

  final Directory directory;

  Future<Directory> createTransferDirectory() async {
    try {
      final transfers = Directory('${directory.path}/transfers');
      await transfers.create(recursive: true);
      return await transfers.createTemp('transfer-');
    } on FileSystemException {
      // 缓存不可写时仍允许本次更新，临时副本由任务收尾删除。
      return Directory.systemTemp.createTemp('lilygobox-ota-');
    }
  }

  /// 下载任务限时十分钟；只清理超过一天的遗留副本，避开当前传输。
  Future<void> clean({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final temporaryCutoff = current.subtract(const Duration(days: 1));
    final cacheCutoff = current.subtract(const Duration(days: 30));
    try {
      if (!await directory.exists()) return;
      await for (final entry in directory.list(followLinks: false)) {
        try {
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (entry is File && RegExp(r'^[a-f0-9]{64}\.bin$').hasMatch(name)) {
            if ((await entry.stat()).modified.isBefore(cacheCutoff)) {
              await entry.delete();
            }
          } else if (entry is Directory && name.startsWith('.write-')) {
            if ((await entry.stat()).modified.isBefore(temporaryCutoff)) {
              await entry.delete(recursive: true);
            }
          } else if (entry is Directory && name == 'transfers') {
            await for (final transfer in entry.list(followLinks: false)) {
              if (transfer is Directory &&
                  transfer.uri.pathSegments
                      .where((s) => s.isNotEmpty)
                      .last
                      .startsWith('transfer-') &&
                  (await transfer.stat()).modified.isBefore(temporaryCutoff)) {
                await transfer.delete(recursive: true);
              }
            }
          }
        } on FileSystemException {
          // 清理失败不阻止本次下载或其他组件的缓存复用。
        }
      }
    } on FileSystemException {
      // 缓存目录不可访问时交由正常下载流程处理。
    }
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
  ) async =>
      await inspect(scope, component, version, size, hash) ==
      FirmwareCacheStatus.valid;

  Future<FirmwareCacheStatus> inspect(
    String scope,
    String component,
    String version,
    int size,
    String hash,
  ) async {
    final file = _file(scope, component, version, size, hash);
    try {
      if (!await file.exists()) return FirmwareCacheStatus.missing;
      if (await file.length() == size &&
          (await sha256.bind(file.openRead()).first).toString() ==
              hash.toLowerCase()) {
        return FirmwareCacheStatus.valid;
      }
      await file.delete();
    } on FileSystemException {
      return FirmwareCacheStatus.invalid;
    }
    return FirmwareCacheStatus.invalid;
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
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File &&
                RegExp(
                  r'^[a-f0-9]{64}\.bin$',
                ).hasMatch(entry.uri.pathSegments.last),
          )
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
