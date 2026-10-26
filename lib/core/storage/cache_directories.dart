import 'dart:io';

/// 可重新下载的数据统一放在用户本机缓存目录，不随配置漫游。
abstract final class AppCacheDirectories {
  static Directory get root {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final base = environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      return Directory('$base/LILYGO/lilygobox/cache');
    }
    final userDirectory = environment['HOME'];
    final base = Platform.isMacOS
        ? (userDirectory == null ? null : '$userDirectory/Library/Caches')
        : environment['XDG_CACHE_HOME'] ??
              (userDirectory == null ? null : '$userDirectory/.cache');
    return Directory('${base ?? Directory.systemTemp.path}/lilygobox');
  }

  static Directory get firmware => Directory('${root.path}/firmware');
  static Directory get updates => Directory('${root.path}/updates');
}
