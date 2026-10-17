import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class FirmwareChip {
  const FirmwareChip({required this.model, required this.revision});

  final String model;
  final String revision;
}

class FirmwareHardware {
  const FirmwareHardware({required this.main, required this.wireless});

  final FirmwareChip main;
  final FirmwareChip wireless;

  static FirmwareHardware? fromJson(Object? value) {
    if (value == null) return null;
    FirmwareChip chip(Object? value) {
      if (value is! Map<String, dynamic> ||
          !const ['esp32p4', 'esp32c5', 'esp32c6'].contains(value['model']) ||
          _chipRevision(value['revision']) == null) {
        throw const FormatException('Invalid device chip information');
      }
      return FirmwareChip(
        model: value['model'] as String,
        revision: value['revision'] as String,
      );
    }

    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid device chip information');
    }
    return FirmwareHardware(
      main: chip(value['main']),
      wireless: chip(value['wireless']),
    );
  }
}

class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.mainVersion,
    required this.mainUrl,
    required this.mainSize,
    required this.mainSha256,
    required this.wirelessVersion,
    required this.wirelessUrl,
    required this.wirelessSize,
    required this.wirelessSha256,
    required this.notes,
  });

  final String version;
  final String mainVersion;
  final Uri mainUrl;
  final int mainSize;
  final String mainSha256;
  final String wirelessVersion;
  final Uri wirelessUrl;
  final int wirelessSize;
  final String wirelessSha256;
  final List<String> notes;

  bool isNewerThan(String mainCurrent, String wirelessCurrent) =>
      needsMainUpdate(mainCurrent) || needsWirelessUpdate(wirelessCurrent);

  bool needsMainUpdate(String current) =>
      _compareVersion(mainVersion, current) > 0;
  bool needsWirelessUpdate(String current) =>
      _compareVersion(wirelessVersion, current) > 0;

  bool targetsReached(String mainCurrent, String wirelessCurrent) =>
      _versionPattern.hasMatch(_normalizeVersion(mainCurrent)) &&
      _versionPattern.hasMatch(_normalizeVersion(wirelessCurrent)) &&
      _compareVersion(mainCurrent, mainVersion) >= 0 &&
      _compareVersion(wirelessCurrent, wirelessVersion) >= 0;
}

class DownloadedFirmware {
  const DownloadedFirmware({required this.directory, this.main, this.wireless});

  final Directory directory;
  final File? main;
  final File? wireless;
}

class FirmwareUpdateService {
  const FirmwareUpdateService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static Uri manifestUriFor(String model, String modelVersion) {
    if (_chipRevision(_normalizeVersion(modelVersion)) == null) {
      throw const FormatException('Invalid device hardware version');
    }
    final device = switch (model) {
      'T-Display-P4-Air' => 't-display-p4-air',
      'T-Display-P4' => 't-display-p4',
      _ => throw const FormatException('Unsupported device model'),
    };
    final file = 'lilygobox_${device}_ota-manifest_stable_v2.json';
    return Uri.parse(
      'https://github.com/Xinyuan-LilyGO/lilygobox-espidf/releases/download/ota-stable/$file',
    );
  }

  Future<FirmwareRelease?> check({
    required String model,
    required String modelVersion,
    required String mainCurrent,
    required String wirelessCurrent,
    FirmwareHardware? hardware,
  }) async {
    final uri = manifestUriFor(model, modelVersion);
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Firmware manifest request failed', uri: uri);
      }
      final release = _parse(
        jsonDecode(response.body),
        model,
        modelVersion,
        hardware,
      );
      if (release == null) {
        throw const FormatException(
          'Firmware manifest is invalid or incompatible',
        );
      }
      return release.isNewerThan(mainCurrent, wirelessCurrent) ? release : null;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<DownloadedFirmware> download(
    FirmwareRelease release, {
    required bool downloadMain,
    required bool downloadWireless,
    http.Client? client,
    void Function(bool main, int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!downloadMain && !downloadWireless) {
      throw StateError('当前已是最新版本');
    }
    final downloadClient = client ?? _client ?? http.Client();
    final directory = await Directory.systemTemp.createTemp('lilygobox-ota-');
    try {
      final main = downloadMain
          ? File('${directory.path}${Platform.pathSeparator}main.bin')
          : null;
      final wireless = downloadWireless
          ? File('${directory.path}${Platform.pathSeparator}wireless.bin')
          : null;
      if (main != null) {
        await _downloadAndVerify(
          downloadClient,
          release.mainUrl,
          release.mainSize,
          release.mainSha256,
          main,
          (received, total) => onProgress?.call(true, received, total),
          isCancelled,
        );
      }
      if (wireless != null) {
        await _downloadAndVerify(
          downloadClient,
          release.wirelessUrl,
          release.wirelessSize,
          release.wirelessSha256,
          wireless,
          (received, total) => onProgress?.call(false, received, total),
          isCancelled,
        );
      }
      if (isCancelled?.call() ?? false) throw const HttpException('更新已取消');
      return DownloadedFirmware(
        directory: directory,
        main: main,
        wireless: wireless,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    } finally {
      if (client == null && _client == null) downloadClient.close();
    }
  }

  Future<void> _downloadAndVerify(
    http.Client client,
    Uri uri,
    int expectedSize,
    String expectedHash,
    File target,
    void Function(int, int) onProgress,
    bool Function()? isCancelled,
  ) async {
    if (isCancelled?.call() ?? false) throw const HttpException('更新已取消');
    onProgress(0, expectedSize);
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Firmware download failed', uri: uri);
    }
    final sink = target.openWrite();
    var size = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (isCancelled?.call() ?? false) throw const HttpException('更新已取消');
        size += chunk.length;
        if (size > expectedSize) {
          throw const FormatException('Firmware size mismatch');
        }
        sink.add(chunk);
        onProgress(size, expectedSize);
      }
    } finally {
      await sink.close();
    }
    final actual = await sha256.bind(target.openRead()).first;
    if (size != expectedSize ||
        actual.toString().toLowerCase() != expectedHash.toLowerCase()) {
      throw const FormatException('Firmware integrity check failed');
    }
  }

  FirmwareRelease? _parse(
    Object? value,
    String model,
    String modelVersion,
    FirmwareHardware? hardware,
  ) {
    if (value is! Map<String, dynamic> ||
        value['kind'] != 'lilygobox#otaManifest' ||
        !const ['1.0', '2.0'].contains(value['manifestVersion']) ||
        value['channel'] != 'stable') {
      return null;
    }
    final release = value['release'];
    final targets = value['targets'];
    final files = value['files'];
    if (release is! Map<String, dynamic> ||
        release['publisherId'] != 'lilygo' ||
        release['deviceId'] is! String ||
        targets is! List<Object?> ||
        files is! Map<String, dynamic>) {
      return null;
    }
    final deviceId = model == 'T-Display-P4-Air'
        ? 't-display-p4-air'
        : 't-display-p4';
    if (release['deviceId'] != deviceId) return null;
    Map<String, dynamic>? components;
    final wirelessChip =
        hardware?.wireless.model ??
        (model == 'T-Display-P4' && _normalizeVersion(modelVersion) == '1.0'
            ? 'esp32c6'
            : 'esp32c5');
    for (final target in targets) {
      if (target is! Map<String, dynamic>) return null;
      final compatibility = target['compatibility'];
      if (compatibility is! Map<String, dynamic>) return null;
      if (compatibility['deviceVersion'] != _normalizeVersion(modelVersion)) {
        continue;
      }
      final chips = compatibility['chips'];
      final candidate = target['components'];
      if (chips is! Map<String, dynamic> ||
          !_validChip(chips['main'], value['manifestVersion']) ||
          !_validChip(chips['wireless'], value['manifestVersion']) ||
          candidate is! Map<String, dynamic> ||
          candidate['main'] is! String ||
          candidate['wireless'] is! String) {
        return null;
      }
      if (!_matchesChip(
            chips['main'],
            hardware?.main,
            hardware?.main.model ?? 'esp32p4',
            value['manifestVersion'],
          ) ||
          !_matchesChip(
            chips['wireless'],
            hardware?.wireless,
            wirelessChip,
            value['manifestVersion'],
          )) {
        continue;
      }
      // 老设备未上报芯片信息时，只允许唯一固件组合；最终兼容性仍由设备复核。
      if (components != null &&
          (hardware != null ||
              components['main'] != candidate['main'] ||
              components['wireless'] != candidate['wireless'])) {
        return null;
      }
      components = candidate;
    }
    if (components == null) return null;
    final main = files[components['main']];
    final wireless = files[components['wireless']];
    final mainFile = _file(main);
    final wirelessFile = _file(wireless);
    if (mainFile == null ||
        wirelessFile == null ||
        main is! Map<String, dynamic> ||
        main['chip'] != (hardware?.main.model ?? 'esp32p4') ||
        main['projectName'] != 'lilygobox-espidf' ||
        wireless is! Map<String, dynamic> ||
        wireless['chip'] != wirelessChip ||
        wireless['projectName'] != 'network_adapter') {
      return null;
    }
    return FirmwareRelease(
      version: release['version'] as String? ?? mainFile.version,
      mainVersion: mainFile.version,
      mainUrl: mainFile.url,
      mainSize: mainFile.size,
      mainSha256: mainFile.sha256,
      wirelessVersion: wirelessFile.version,
      wirelessUrl: wirelessFile.url,
      wirelessSize: wirelessFile.size,
      wirelessSha256: wirelessFile.sha256,
      notes: (value['releaseNotes'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  bool _validChip(Object? source, Object? manifestVersion) {
    if (source is! Map<String, dynamic> ||
        !const ['esp32p4', 'esp32c5', 'esp32c6'].contains(source['model'])) {
      return false;
    }

    if (manifestVersion == '1.0') {
      return !source.containsKey('minRevision') &&
          !source.containsKey('maxRevision') &&
          _chipRevision(source['revision']) != null;
    }
    final minimum = _chipRevision(source['minRevision']);
    final maximum = _chipRevision(source['maxRevision']);
    return !source.containsKey('revision') &&
        minimum != null &&
        maximum != null &&
        minimum <= maximum;
  }

  bool _matchesChip(
    Map<String, dynamic> chip,
    FirmwareChip? actual,
    String model,
    Object? manifestVersion,
  ) {
    if (chip['model'] != model) return false;
    if (actual == null) return true;
    final current = _chipRevision(actual.revision);
    if (current == null) return false;
    if (manifestVersion == '1.0') {
      return current == _chipRevision(chip['revision']);
    }
    return current >= _chipRevision(chip['minRevision'])! &&
        current <= _chipRevision(chip['maxRevision'])!;
  }

  _FirmwareFile? _file(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] is! String ||
        value['sizeBytes'] is! int ||
        (value['sizeBytes'] as int) <= 0 ||
        (value['sizeBytes'] as int) > 64 * 1024 * 1024 ||
        value['hashes'] is! Map<String, dynamic>) {
      return null;
    }
    final urls = value['downloadUrls'];
    final hash = (value['hashes'] as Map<String, dynamic>)['sha256'];
    if (urls is! List<Object?> ||
        urls.isEmpty ||
        urls.first is! String ||
        hash is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
      return null;
    }
    final url = Uri.tryParse(urls.first as String);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      return null;
    }
    return _FirmwareFile(
      version: value['version'] as String,
      url: url,
      size: value['sizeBytes'] as int,
      sha256: hash,
    );
  }
}

class _FirmwareFile {
  const _FirmwareFile({
    required this.version,
    required this.url,
    required this.size,
    required this.sha256,
  });
  final String version;
  final Uri url;
  final int size;
  final String sha256;
}

final _versionPattern = RegExp(
  r'^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta)\.(\d+))?$',
);

int? _chipRevision(Object? value) {
  if (value is! String || !RegExp(r'^\d+\.\d+$').hasMatch(value)) return null;
  final parts = value.split('.').map(int.tryParse).toList();
  final major = parts[0];
  final minor = parts[1];
  return major != null && minor != null && major <= 255 && minor <= 99
      ? major * 100 + minor
      : null;
}

String _normalizeVersion(String value) =>
    value.replaceFirst(RegExp(r'^[vV]'), '');

int _compareVersion(String a, String b) {
  final am = _versionPattern.firstMatch(_normalizeVersion(a));
  final bm = _versionPattern.firstMatch(_normalizeVersion(b));
  if (am == null || bm == null) return a.compareTo(b);
  for (var i = 1; i <= 3; i++) {
    final compare = int.parse(am.group(i)!).compareTo(int.parse(bm.group(i)!));
    if (compare != 0) return compare;
  }
  final ar = am.group(4) == null
      ? 2
      : am.group(4) == 'beta'
      ? 1
      : 0;
  final br = bm.group(4) == null
      ? 2
      : bm.group(4) == 'beta'
      ? 1
      : 0;
  return ar != br
      ? ar.compareTo(br)
      : int.parse(am.group(5) ?? '0').compareTo(int.parse(bm.group(5) ?? '0'));
}
