import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../network/download_sources.dart';
import '../storage/cache_directories.dart';

enum AppReleaseChannel { alpha, beta, stable }

final appReleaseChannel = switch (const String.fromEnvironment(
  'LILYGOBOX_RELEASE_CHANNEL',
  defaultValue: 'stable',
)) {
  'alpha' => AppReleaseChannel.alpha,
  'beta' => AppReleaseChannel.beta,
  _ => AppReleaseChannel.stable,
};

extension AppReleaseChannelValue on AppReleaseChannel {
  String get value => switch (this) {
    AppReleaseChannel.alpha => 'alpha',
    AppReleaseChannel.beta => 'beta',
    AppReleaseChannel.stable => 'stable',
  };
}

String appReleaseVersion(
  String packageVersion, {
  String? versionOverride,
  AppReleaseChannel? channel,
}) {
  final override =
      versionOverride ??
      const String.fromEnvironment('LILYGOBOX_RELEASE_VERSION');
  if (override.isNotEmpty) return override;
  final releaseChannel = channel ?? appReleaseChannel;
  if (releaseChannel == AppReleaseChannel.stable) return packageVersion;
  final match = RegExp(
    r'^v?(\d+\.\d+\.\d+)(?:-(?:alpha|beta)\.\d+)?$',
  ).firstMatch(packageVersion);
  if (match == null) return packageVersion;
  return '${match.group(1)}-${releaseChannel.value}.1';
}

enum AppUpdateFailureKind {
  network,
  timeout,
  manifestNotFound,
  server,
  http,
  invalidManifest,
  download,
  integrity,
  installerLaunch,
  unknown,
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.kind, {this.statusCode});

  final AppUpdateFailureKind kind;
  final int? statusCode;
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.releaseNotes,
  });

  final String version;
  final String fileName;
  final Uri downloadUrl;
  final int sizeBytes;
  final String sha256;
  final List<String> releaseNotes;
}

class AppUpdateService {
  const AppUpdateService({http.Client? client, Directory? updateDirectory})
    : _client = client,
      _customUpdateDirectory = updateDirectory;

  final http.Client? _client;
  final Directory? _customUpdateDirectory;

  static Uri manifestUri(AppReleaseChannel channel) {
    final name = channel.value;
    return Uri.parse(
      'https://github.com/Xinyuan-LilyGO/lilygobox-flutter/releases/download/'
      'app-update-$name/lilygobox-app-update-manifest-$name-v1.json',
    );
  }

  Future<AppUpdate?> check({
    required String currentVersion,
    AppReleaseChannel? channel,
  }) async {
    final selectedChannel = channel ?? appReleaseChannel;
    final client = _client ?? http.Client();
    try {
      http.Response? response;
      final sources = githubDownloadSources(manifestUri(selectedChannel));
      for (var index = 0; index < sources.length; index++) {
        try {
          response = await client
              .get(
                sources[index],
                headers: const {'Accept': 'application/json'},
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode < HttpStatus.internalServerError ||
              index == sources.length - 1) {
            break;
          }
        } on TimeoutException {
          if (index == sources.length - 1) {
            throw const AppUpdateException(AppUpdateFailureKind.timeout);
          }
        } on SocketException {
          if (index == sources.length - 1) {
            throw const AppUpdateException(AppUpdateFailureKind.network);
          }
        } on HandshakeException {
          if (index == sources.length - 1) {
            throw const AppUpdateException(AppUpdateFailureKind.network);
          }
        } on http.ClientException {
          if (index == sources.length - 1) {
            throw const AppUpdateException(AppUpdateFailureKind.network);
          }
        }
      }
      if (response == null) {
        throw const AppUpdateException(AppUpdateFailureKind.network);
      }
      if (response.statusCode != HttpStatus.ok) {
        final kind = response.statusCode == HttpStatus.notFound
            ? AppUpdateFailureKind.manifestNotFound
            : response.statusCode >= HttpStatus.internalServerError
            ? AppUpdateFailureKind.server
            : AppUpdateFailureKind.http;
        throw AppUpdateException(kind, statusCode: response.statusCode);
      }
      late final AppUpdate update;
      try {
        if (response.bodyBytes.length > 32 * 1024) {
          throw const FormatException('Update manifest is too large');
        }
        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic> ||
            data['kind'] != 'lilygobox#appUpdateManifest' ||
            data['channel'] != selectedChannel.value) {
          throw const FormatException('Invalid update manifest');
        }
        final release = data['release'];
        final version = release is Map<String, dynamic>
            ? release['version']
            : null;
        final windows = data['windows'];
        final x64 = windows is Map<String, dynamic> ? windows['x64'] : null;
        final fileName = x64 is Map<String, dynamic> ? x64['fileName'] : null;
        final url = x64 is Map<String, dynamic> ? x64['downloadUrl'] : null;
        final sizeBytes = x64 is Map<String, dynamic> ? x64['sizeBytes'] : null;
        final hashes = x64 is Map<String, dynamic> ? x64['hashes'] : null;
        final sha256Hash = x64 is Map<String, dynamic>
            ? x64['sha256']
            : hashes is Map<String, dynamic>
            ? hashes['sha256']
            : null;
        if (version is! String ||
            fileName is! String ||
            url is! String ||
            sizeBytes is! int ||
            sha256Hash is! String) {
          throw const FormatException('Invalid update manifest');
        }
        if (!RegExp(r'^[A-Za-z0-9._-]+\.exe$').hasMatch(fileName) ||
            sizeBytes <= 0 ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256Hash)) {
          throw const FormatException('Invalid update asset metadata');
        }
        final versionParts = _versionParts(version);
        final versionChannel = versionParts[3] == 0
            ? AppReleaseChannel.alpha
            : versionParts[3] == 1
            ? AppReleaseChannel.beta
            : AppReleaseChannel.stable;
        if (versionChannel != selectedChannel) {
          throw const FormatException(
            'Update version does not match its channel',
          );
        }
        final downloadUrl = Uri.tryParse(url);
        if (downloadUrl == null ||
            downloadUrl.scheme != 'https' ||
            downloadUrl.host != 'github.com') {
          throw const FormatException('Invalid update URL');
        }
        final notes = (data['releaseNotes'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
        update = AppUpdate(
          version: version,
          fileName: fileName,
          downloadUrl: downloadUrl,
          sizeBytes: sizeBytes,
          sha256: sha256Hash.toLowerCase(),
          releaseNotes: notes,
        );
      } on FormatException {
        throw const AppUpdateException(AppUpdateFailureKind.invalidManifest);
      } on TypeError {
        throw const AppUpdateException(AppUpdateFailureKind.invalidManifest);
      }
      return _compareVersion(update.version, currentVersion) > 0
          ? update
          : null;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<File> downloadInstaller(
    AppUpdate update, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sources = githubDownloadSources(update.downloadUrl);
    for (var index = 0; index < sources.length; index++) {
      if (isCancelled?.call() ?? false) {
        throw const AppUpdateException(AppUpdateFailureKind.download);
      }
      try {
        return await _downloadInstallerFromSource(
          update,
          source: sources[index],
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } on AppUpdateException catch (error) {
        if (index == sources.length - 1 ||
            !const {
              AppUpdateFailureKind.network,
              AppUpdateFailureKind.timeout,
              AppUpdateFailureKind.server,
            }.contains(error.kind)) {
          rethrow;
        }
        if (isCancelled?.call() ?? false) {
          throw const AppUpdateException(AppUpdateFailureKind.download);
        }
      }
    }
    throw const AppUpdateException(AppUpdateFailureKind.download);
  }

  Directory _installerDirectory(AppUpdate update) {
    _versionParts(update.version);
    return Directory('${_updateDirectory.path}/${update.version}');
  }

  Future<File> _downloadInstallerFromSource(
    AppUpdate update, {
    required Uri source,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!Platform.isWindows) {
      throw const AppUpdateException(AppUpdateFailureKind.download);
    }
    final client = _client ?? http.Client();
    final directory = _installerDirectory(update);
    final target = File('${directory.path}/${update.fileName}');
    final partial = File('${target.path}.part');
    try {
      await directory.create(recursive: true);
      if (await _isValidInstaller(target, update)) return target;
      if (await target.exists()) await target.delete();
      final request = http.Request('GET', source);
      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.listen((_) {}).cancel();
        throw AppUpdateException(
          response.statusCode >= HttpStatus.internalServerError
              ? AppUpdateFailureKind.server
              : AppUpdateFailureKind.http,
          statusCode: response.statusCode,
        );
      }
      final sink = partial.openWrite();
      final digestSink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 2),
        )) {
          if (isCancelled?.call() ?? false) {
            throw const AppUpdateException(AppUpdateFailureKind.download);
          }
          received += chunk.length;
          if (received > update.sizeBytes) {
            throw const AppUpdateException(AppUpdateFailureKind.integrity);
          }
          sink.add(chunk);
          digestInput.add(chunk);
          onProgress?.call(received, update.sizeBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
        digestInput.close();
      }
      if (received != update.sizeBytes ||
          digestSink.digest.toString() != update.sha256) {
        throw const AppUpdateException(AppUpdateFailureKind.integrity);
      }
      if (isCancelled?.call() ?? false) {
        throw const AppUpdateException(AppUpdateFailureKind.download);
      }
      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(AppUpdateFailureKind.timeout);
    } on SocketException {
      throw const AppUpdateException(AppUpdateFailureKind.network);
    } on HandshakeException {
      throw const AppUpdateException(AppUpdateFailureKind.network);
    } on http.ClientException {
      throw const AppUpdateException(AppUpdateFailureKind.network);
    } on FileSystemException {
      throw const AppUpdateException(AppUpdateFailureKind.download);
    } finally {
      if (_client == null) client.close();
      try {
        if (await partial.exists()) await partial.delete();
      } on FileSystemException {
        // 文件仍被占用时由下次启动清理，不覆盖原本的下载结果。
      }
    }
  }

  Future<File?> findCachedInstaller(AppUpdate update) async {
    final file = File('${_installerDirectory(update).path}/${update.fileName}');
    try {
      if (await _isValidInstaller(file, update)) return file;
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return null;
    }
    return null;
  }

  Future<bool> _isValidInstaller(File file, AppUpdate update) async {
    try {
      if (!await file.exists() || await file.length() != update.sizeBytes) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == update.sha256;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> launchInstallerAfterExit(File installer) async {
    if (!Platform.isWindows) {
      throw const AppUpdateException(AppUpdateFailureKind.download);
    }
    if (!await installer.exists()) {
      throw const AppUpdateException(AppUpdateFailureKind.download);
    }
    final script = File(
      '${Directory.systemTemp.path}/lilygobox-update-$pid.vbs',
    );
    final log = File('${Directory.systemTemp.path}/lilygobox-update-$pid.log');
    final application = Platform.resolvedExecutable;
    if (await log.exists()) await log.delete();
    await script.writeAsString(r'''
Option Explicit
Dim args, parentPid, installerPath, applicationPath, logPath, attempt
Dim fileSystem, logFile, shell, wmi, applicationProcess, installerExitCode
Set args = WScript.Arguments
parentPid = CLng(args(0))
installerPath = args(1)
applicationPath = args(2)
logPath = args(3)
Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set logFile = fileSystem.OpenTextFile(logPath, 8, True)
Set shell = CreateObject("WScript.Shell")
Sub WriteLog(message)
  logFile.WriteLine Now & " " & message
End Sub
Function FindApplicationProcess(service, processId, executablePath)
  Dim processes, item
  Set FindApplicationProcess = Nothing
  Set processes = service.ExecQuery("SELECT * FROM Win32_Process WHERE ProcessId = " & processId)
  For Each item In processes
    If LCase(item.ExecutablePath) = LCase(executablePath) Then
      Set FindApplicationProcess = item
    End If
  Next
End Function
Sub RestartApplication()
  If fileSystem.FileExists(applicationPath) Then
    shell.Run Chr(34) & applicationPath & Chr(34), 1, False
    WriteLog "Application relaunch requested."
  End If
End Sub
On Error Resume Next
WriteLog "Updater started. ParentPid=" & parentPid
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
If Err.Number <> 0 Then
  WriteLog "Could not query the application process: " & Err.Description
  Err.Clear
  RestartApplication
  logFile.Close
  WScript.Quit 1
End If
For attempt = 1 To 20
  Set applicationProcess = FindApplicationProcess(wmi, parentPid, applicationPath)
  If Err.Number <> 0 Then Exit For
  If applicationProcess Is Nothing Then Exit For
  WScript.Sleep 500
Next
If Err.Number <> 0 Then
  WriteLog "Could not wait for the application process: " & Err.Description
  Err.Clear
ElseIf Not applicationProcess Is Nothing Then
  WriteLog "Application did not exit after 10 seconds; terminating its process."
  applicationProcess.Terminate
  If Err.Number <> 0 Then
    WriteLog "Could not terminate the application process: " & Err.Description
    Err.Clear
    RestartApplication
    logFile.Close
    WScript.Quit 1
  End If
End If
WriteLog "Application process exited."
If Not fileSystem.FileExists(installerPath) Then
  WriteLog "Downloaded installer is missing."
  RestartApplication
  logFile.Close
  WScript.Quit 1
End If
installerExitCode = shell.Run(Chr(34) & installerPath & Chr(34), 1, True)
If Err.Number <> 0 Then
  WriteLog "Could not start installer: " & Err.Description
  Err.Clear
  RestartApplication
  logFile.Close
  WScript.Quit 1
End If
WriteLog "Installer exited. ExitCode=" & installerExitCode
logFile.Close
WScript.Quit 0
''');
    try {
      await Process.start('wscript.exe', [
        '//B',
        '//NoLogo',
        script.path,
        pid.toString(),
        installer.path,
        application,
        log.path,
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      if (await script.exists()) await script.delete();
      throw const AppUpdateException(AppUpdateFailureKind.installerLaunch);
    }
    for (var attempt = 0; attempt < 200; attempt++) {
      if (await log.exists()) {
        final output = await log.readAsString();
        if (output.contains('Updater started.')) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (await script.exists()) await script.delete();
    throw const AppUpdateException(AppUpdateFailureKind.installerLaunch);
  }

  Directory get _updateDirectory {
    if (_customUpdateDirectory case final directory?) return directory;
    return AppCacheDirectories.updates;
  }

  /// 仅在启动时调用：安装成功以实际运行版本为准，取消安装仍保留新包。
  /// 不扫描安装目录；不跟随链接；被安装器占用的文件留待下次清理。
  Future<void> cleanInstallerCache({
    required String currentVersion,
    DateTime? now,
  }) async {
    _versionParts(currentVersion);
    final directory = _updateDirectory;
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 30));
    final pattern = RegExp(
      r'^LilygoBox-(\d+\.\d+\.\d+(?:-(alpha|beta)\.\d+)?)-windows-x64-setup\.exe(\.part)?$',
    );
    final versionPattern = RegExp(r'^(\d+\.\d+\.\d+(?:-(alpha|beta)\.\d+)?)$');
    final retained = <String, (String, FileSystemEntity)>{};
    final installerName = 'LilygoBox-windows-x64-setup.exe';

    Future<void> removeManagedFiles(FileSystemEntity entity) async {
      if (entity is File) {
        await entity.delete();
        return;
      }
      if (entity is! Directory) return;
      await for (final child in entity.list(followLinks: false)) {
        if (child is File &&
            (child.uri.pathSegments.last == installerName ||
                child.uri.pathSegments.last == '$installerName.part')) {
          await child.delete();
        }
      }
      if (await entity.list(followLinks: false).isEmpty) await entity.delete();
    }

    try {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File && entity is! Directory) continue;
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        final match = (entity is Directory ? versionPattern : pattern)
            .firstMatch(name);
        if (match == null) continue;
        try {
          final version = match.group(1)!;
          final expired = (await entity.stat()).modified.isBefore(cutoff);
          var hasInstaller = entity is File;
          if (entity is Directory) {
            await for (final child in entity.list(followLinks: false)) {
              final childName = child.uri.pathSegments.last;
              if (child is File && childName == '$installerName.part') {
                await child.delete();
              } else if (child is File && childName == installerName) {
                hasInstaller = true;
              }
            }
          }
          if (!hasInstaller) {
            if (entity is Directory &&
                await entity.list(followLinks: false).isEmpty) {
              await entity.delete();
            }
            continue;
          }
          if ((entity is File && match.group(3) != null) ||
              _compareVersion(version, currentVersion) <= 0 ||
              expired) {
            await removeManagedFiles(entity);
            continue;
          }
          final channel = match.group(2) ?? 'stable';
          final previous = retained[channel];
          if (previous == null) {
            retained[channel] = (version, entity);
          } else if (_compareVersion(version, previous.$1) > 0) {
            retained[channel] = (version, entity);
            await removeManagedFiles(previous.$2);
          } else {
            await removeManagedFiles(entity);
          }
        } on FileSystemException {
          // 占用或权限问题不影响启动，也不影响其他缓存文件的清理。
        }
      }
    } on FileSystemException {
      // 缓存目录不可访问时继续启动应用。
    }
  }

  static int _compareVersion(String left, String right) {
    final a = _versionParts(left);
    final b = _versionParts(right);
    for (var index = 0; index < 3; index++) {
      final result = a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    final aRank = a[3];
    final bRank = b[3];
    final rank = aRank.compareTo(bRank);
    return rank == 0 ? a[4].compareTo(b[4]) : rank;
  }

  static List<int> _versionParts(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta)\.(\d+))?$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid application version: $value');
    }
    final label = match.group(4);
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      label == null
          ? 2
          : label.startsWith('alpha')
          ? 0
          : 1,
      int.parse(match.group(5) ?? '0'),
    ];
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
