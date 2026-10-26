import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/features/devices/data/firmware_cache.dart';
import 'package:lilygobox/features/devices/data/firmware_update_service.dart';

void main() {
  late Directory directory;
  late FirmwareCache cache;
  final bytes = [1, 2, 3, 4];
  final hash = sha256.convert(bytes).toString();
  late FirmwareRelease release;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('firmware-cache-test-');
    cache = FirmwareCache(directory: Directory('${directory.path}/cache'));
    release = FirmwareRelease(
      version: '1.1.3',
      mainVersion: '1.1.3',
      mainUrl: Uri.https('example.com', '/main'),
      mainSize: bytes.length,
      mainSha256: hash,
      wirelessVersion: '2.12.4',
      wirelessUrl: Uri.https('example.com', '/wireless'),
      wirelessSize: bytes.length,
      wirelessSha256: hash,
      notes: const [],
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> seed() async {
    final source = await File(
      '${directory.path}/source.bin',
    ).writeAsBytes(bytes);
    await cache.store(
      'P4-V2-chip1.3',
      'main',
      release.mainVersion,
      bytes.length,
      hash,
      source,
    );
  }

  test(
    'verified cached firmware is copied to disposable transfer files',
    () async {
      await seed();
      final client = MockClient(
        (_) async => throw StateError('network must not be used'),
      );
      addTearDown(client.close);
      final files = await FirmwareUpdateService(client: client).download(
        release,
        downloadMain: true,
        downloadWireless: false,
        cache: cache,
        cacheScope: 'P4-V2-chip1.3',
      );
      expect(await files.main!.readAsBytes(), bytes);
      await files.directory.delete(recursive: true);
      expect(
        await cache.contains(
          'P4-V2-chip1.3',
          'main',
          release.mainVersion,
          bytes.length,
          hash,
        ),
        isTrue,
      );
    },
  );

  test(
    'corrupt cache is rejected and replaced with a verified download',
    () async {
      await seed();
      final entry = await cache.directory
          .list()
          .where((entry) => entry is File)
          .first;
      await File(entry.path).writeAsBytes([9, 9, 9, 9]);
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      });
      addTearDown(client.close);
      final files = await FirmwareUpdateService(client: client).download(
        release,
        downloadMain: true,
        downloadWireless: false,
        cache: cache,
        cacheScope: 'P4-V2-chip1.3',
      );
      expect(requests, 1);
      expect(await files.main!.readAsBytes(), bytes);
      await files.directory.delete(recursive: true);
    },
  );

  test(
    'board scope and forced redownload prevent unintended cache reuse',
    () async {
      await seed();
      expect(
        await cache.contains(
          'Air-chip2.0',
          'main',
          release.mainVersion,
          bytes.length,
          hash,
        ),
        isFalse,
      );
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      });
      addTearDown(client.close);
      final files = await FirmwareUpdateService(client: client).download(
        release,
        downloadMain: true,
        downloadWireless: false,
        cache: cache,
        cacheScope: 'P4-V2-chip1.3',
        reuseCache: false,
      );
      expect(requests, 1);
      await files.directory.delete(recursive: true);
    },
  );

  test('failure of another component preserves completed cache', () async {
    final client = MockClient(
      (request) async => request.url.path == '/main'
          ? http.Response.bytes(bytes, 200)
          : http.Response('failed', 503),
    );
    addTearDown(client.close);
    await expectLater(
      FirmwareUpdateService(client: client).download(
        release,
        downloadMain: true,
        downloadWireless: true,
        cache: cache,
        cacheScope: 'P4-V2-chip1.3',
      ),
      throwsA(isA<HttpException>()),
    );
    expect(
      await cache.contains(
        'P4-V2-chip1.3',
        'main',
        release.mainVersion,
        bytes.length,
        hash,
      ),
      isTrue,
    );
    expect(
      await cache.contains(
        'P4-V2-chip1.3',
        'wireless',
        release.wirelessVersion,
        bytes.length,
        hash,
      ),
      isFalse,
    );
  });

  test(
    'integrity retry downloads only the broken component and clears transfer copies',
    () async {
      var corrupt = true;
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        return http.Response.bytes(
          corrupt && request.url.path == '/wireless' ? [9, 9, 9, 9] : bytes,
          200,
        );
      });
      addTearDown(client.close);
      Future<DownloadedFirmware> download() =>
          FirmwareUpdateService(client: client).download(
            release,
            downloadMain: true,
            downloadWireless: true,
            cache: cache,
            cacheScope: 'P4-V2-chip1.3',
          );
      await expectLater(
        download(),
        throwsA(
          isA<FirmwareIntegrityException>().having(
            (error) => error.main,
            'main',
            isFalse,
          ),
        ),
      );
      expect(
        await Directory('${cache.directory.path}/transfers').list().toList(),
        isEmpty,
      );
      corrupt = false;
      final files = await download();
      expect(requests, ['/main', '/wireless', '/wireless']);
      expect(await files.main!.readAsBytes(), bytes);
      expect(await files.wireless!.readAsBytes(), bytes);
      await files.directory.delete(recursive: true);
    },
  );

  test(
    'maintenance expires old firmware while keeping current cache and unknown files',
    () async {
      await seed();
      final old = await File(
        '${cache.directory.path}/${'a' * 64}.bin',
      ).writeAsString('old');
      await old.setLastModified(
        DateTime.now().subtract(const Duration(days: 31)),
      );
      final other = await File(
        '${cache.directory.path}/unrelated.bin',
      ).writeAsString('keep');
      final active = await cache.createTransferDirectory();
      await cache.clean();
      expect(await old.exists(), isFalse);
      expect(await other.exists(), isTrue);
      expect(await active.exists(), isTrue);
      expect(
        await cache.contains(
          'P4-V2-chip1.3',
          'main',
          release.mainVersion,
          bytes.length,
          hash,
        ),
        isTrue,
      );
    },
  );
}
