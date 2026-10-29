import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/core/app_info/app_update_service.dart';
import 'package:lilygobox/core/network/download_sources.dart';
import 'package:lilygobox/features/devices/data/firmware_update_service.dart';

void main() {
  final original = Uri.parse(
    'https://github.com/owner/repo/releases/download/v1.2.0/main.bin',
  );
  final proxy = Uri.parse('https://gh-proxy.com/$original');
  final bytes = [1, 2, 3, 4];
  final hash = sha256.convert(bytes).toString();

  FirmwareRelease firmware() => FirmwareRelease(
    version: '1.2.0',
    mainVersion: '1.2.0',
    mainUrl: original,
    mainSize: bytes.length,
    mainSha256: hash,
    wirelessVersion: '2.12.3',
    wirelessUrl: original,
    wirelessSize: bytes.length,
    wirelessSha256: hash,
    notes: const [],
  );

  AppUpdate application(String version) => AppUpdate(
    version: version,
    fileName: 'LilygoBox-windows-x64-setup-$version.exe',
    downloadUrl: original,
    sizeBytes: bytes.length,
    sha256: hash,
    releaseNotes: const [],
  );

  test('only original GitHub HTTPS URLs receive a proxy fallback', () {
    expect(githubDownloadSources(original), [original, proxy]);
    for (final address in [
      'http://github.com/file.bin',
      'http://192.168.1.1/file.bin',
      'https://example.com/file.bin',
      'https://github.com.evil/file.bin',
      'https://user@github.com/file.bin',
      'https://github.com:8443/file.bin',
      proxy.toString(),
    ]) {
      final uri = Uri.parse(address);
      expect(githubDownloadSources(uri), [uri]);
    }
  });

  for (final failure in ['network', 'http', 'stream']) {
    test(
      'firmware retries $failure through proxy and writes a complete file',
      () async {
        final requested = <Uri>[];
        final client = MockClient.streaming((request, _) async {
          requested.add(request.url);
          if (request.url == original) {
            if (failure == 'network') throw const SocketException('offline');
            if (failure == 'http')
              return http.StreamedResponse(Stream.value([0]), 503);
            return http.StreamedResponse(
              Stream<List<int>>.multi((controller) {
                controller.add([9, 9]);
                controller.addError(const SocketException('disconnected'));
                controller.close();
              }),
              200,
            );
          }
          return http.StreamedResponse(Stream.value(bytes), 200);
        });
        addTearDown(client.close);
        final files = await FirmwareUpdateService(
          client: client,
        ).download(firmware(), downloadMain: true, downloadWireless: false);
        addTearDown(() => files.directory.delete(recursive: true));
        expect(requested, [original, proxy]);
        expect(await files.main!.readAsBytes(), bytes);
      },
    );
  }

  test('a successful direct download does not use proxy', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      return http.Response.bytes(bytes, 200);
    });
    addTearDown(client.close);
    final files = await FirmwareUpdateService(
      client: client,
    ).download(firmware(), downloadMain: true, downloadWireless: false);
    addTearDown(() => files.directory.delete(recursive: true));
    expect(requested, [original]);
  });

  test(
    'an unavailable direct GitHub asset does not retry through the proxy',
    () async {
      var requests = 0;
      final client = MockClient.streaming((_, _) async {
        requests++;
        return http.StreamedResponse(Stream.value([0]), 404);
      });
      addTearDown(client.close);
      await expectLater(
        FirmwareUpdateService(
          client: client,
        ).download(firmware(), downloadMain: true, downloadWireless: false),
        throwsA(isA<HttpException>()),
      );
      expect(requests, 1);
    },
  );

  test(
    'firmware integrity failures require explicit retry without switching source',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes([9, 9, 9, 9], 200);
      });
      addTearDown(client.close);
      await expectLater(
        FirmwareUpdateService(
          client: client,
        ).download(firmware(), downloadMain: true, downloadWireless: false),
        throwsA(isA<FirmwareIntegrityException>()),
      );
      expect(requests, 1);
    },
  );

  test('cancelling firmware download prevents fallback', () async {
    var requests = 0;
    var cancelled = false;
    final client = MockClient((_) async {
      requests++;
      cancelled = true;
      throw const SocketException('closed');
    });
    addTearDown(client.close);
    await expectLater(
      FirmwareUpdateService(client: client).download(
        firmware(),
        downloadMain: true,
        downloadWireless: false,
        isCancelled: () => cancelled,
      ),
      throwsA(isA<HttpException>()),
    );
    expect(requests, 1);
  });

  test(
    'installer fallback preserves version-specific caches with the same filename',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'update-source-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        if (request.url == original) return http.Response('unavailable', 503);
        return http.Response.bytes(bytes, 200);
      });
      addTearDown(client.close);
      final service = AppUpdateService(
        client: client,
        updateDirectory: directory,
      );
      final previous = await service.downloadInstaller(application('1.2.0'));
      final next = await service.downloadInstaller(application('1.3.0'));
      expect(previous.path, isNot(next.path));
      expect(await previous.readAsBytes(), bytes);
      expect(await next.readAsBytes(), bytes);
      expect(requested, [original, proxy, original, proxy]);
      await service.downloadInstaller(application('1.3.0'));
      expect(requested.length, 4);
      await service.cleanInstallerCache(currentVersion: '1.2.0');
      expect(await previous.parent.exists(), isFalse);
      expect(await next.exists(), isTrue);
    },
  );

  test('cancelling installer download prevents fallback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'update-cancel-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    var cancelled = false;
    final client = MockClient((_) async {
      requests++;
      cancelled = true;
      throw const SocketException('closed');
    });
    addTearDown(client.close);
    await expectLater(
      AppUpdateService(
        client: client,
        updateDirectory: directory,
      ).downloadInstaller(application('1.2.0'), isCancelled: () => cancelled),
      throwsA(isA<AppUpdateException>()),
    );
    expect(requests, 1);
    expect(
      await directory
          .list(recursive: true)
          .where((entry) => entry is File)
          .toList(),
      isEmpty,
    );
  });

  test(
    'version cache cleanup keeps the latest installer and unrelated files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'update-cleanup-version-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<File> seed(String version) async {
        final target = File(
          '${directory.path}/$version/LilygoBox-windows-x64-setup-$version.exe',
        );
        await target.parent.create(recursive: true);
        return target.writeAsBytes(bytes);
      }

      final older = await seed('1.2.0-beta.1');
      final latest = await seed('1.2.0-beta.2');
      final stable = await seed('1.2.0');
      final unknown = await File(
        '${older.parent.path}/user.txt',
      ).writeAsString('keep');
      final partial = await File(
        '${latest.path}.part',
      ).writeAsString('partial');
      final service = AppUpdateService(updateDirectory: directory);
      await service.cleanInstallerCache(currentVersion: '1.1.0');
      expect(await older.exists(), isFalse);
      expect(await unknown.exists(), isTrue);
      expect(await latest.exists(), isTrue);
      expect(await stable.exists(), isTrue);
      expect(await partial.exists(), isFalse);

      await service.cleanInstallerCache(currentVersion: '1.2.0');
      expect(await latest.parent.exists(), isFalse);
      expect(await stable.parent.exists(), isFalse);
      expect(await unknown.exists(), isTrue);
    },
  );
}
