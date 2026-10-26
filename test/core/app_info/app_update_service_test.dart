import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/core/app_info/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    test(
      'startup removes installed, stale and partial packages, keeping latest per channel',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'update-cleanup-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final now = DateTime(2026, 10, 22);
        Future<File> seed(
          String version, {
          bool partial = false,
          bool old = false,
        }) async {
          final file = File(
            '${directory.path}/LilygoBox-$version-windows-x64-setup.exe${partial ? '.part' : ''}',
          );
          await file.writeAsString('test');
          await file.setLastModified(
            now.subtract(Duration(days: old ? 31 : 1)),
          );
          return file;
        }

        final installed = await seed('1.0.0-beta.1');
        final previous = await seed('1.0.0-alpha.9');
        final olderBeta = await seed('1.0.0-beta.2');
        final latestBeta = await seed('1.0.0-beta.10');
        final stable = await seed('1.0.0');
        final expired = await seed('2.0.0-beta.1', old: true);
        final partial = await seed('3.0.0', partial: true);
        final unrelated = await File(
          '${directory.path}/other-installer.exe',
        ).writeAsString('keep');
        final unknown = await File(
          '${directory.path}/LilygoBox-bad-windows-x64-setup.exe',
        ).writeAsString('keep');

        await AppUpdateService(
          updateDirectory: directory,
        ).cleanInstallerCache(currentVersion: '1.0.0-beta.1', now: now);

        for (final file in [installed, previous, olderBeta, expired, partial]) {
          expect(await file.exists(), isFalse, reason: file.path);
        }
        for (final file in [latestBeta, stable, unrelated, unknown]) {
          expect(await file.exists(), isTrue, reason: file.path);
        }
      },
    );

    test(
      'a cancelled future installer is retained until that version runs',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'update-install-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = await File(
          '${directory.path}/LilygoBox-1.0.0-beta.1-windows-x64-setup.exe',
        ).writeAsString('test');
        final service = AppUpdateService(updateDirectory: directory);
        await service.cleanInstallerCache(currentVersion: '1.0.0-beta.0');
        expect(await file.exists(), isTrue);
        await service.cleanInstallerCache(currentVersion: '1.0.0-beta.1');
        expect(await file.exists(), isFalse);
      },
    );

    test('a failed download removes its partial file and can retry', () async {
      final directory = await Directory.systemTemp.createTemp('update-retry-');
      addTearDown(() => directory.delete(recursive: true));
      final good = [1, 2, 3];
      var requests = 0;
      final client = MockClient(
        (_) async =>
            http.Response.bytes(++requests == 1 ? [9, 9, 9] : good, 200),
      );
      addTearDown(client.close);
      final service = AppUpdateService(
        client: client,
        updateDirectory: directory,
      );
      final update = AppUpdate(
        version: '1.0.0-beta.1',
        fileName: 'LilygoBox-1.0.0-beta.1-windows-x64-setup.exe',
        downloadUrl: Uri.https('github.com', '/test.exe'),
        sizeBytes: good.length,
        sha256: sha256.convert(good).toString(),
        releaseNotes: const [],
      );
      await expectLater(
        service.downloadInstaller(update),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.kind,
            'kind',
            AppUpdateFailureKind.integrity,
          ),
        ),
      );
      expect(
        await directory
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
      final installer = await service.downloadInstaller(update);
      expect(await installer.readAsBytes(), good);
      await service.downloadInstaller(update);
      expect(requests, 2);
    });

    test('uses the explicitly selected Beta channel', () {
      expect(
        AppUpdateService.manifestUri(AppReleaseChannel.beta).path,
        endsWith(
          '/app-update-beta/lilygobox-app-update-manifest-beta-v1.json',
        ),
      );
    });

    http.Response response({
      String channel = 'stable',
      String version = '1.2.0',
    }) => http.Response(
      jsonEncode({
        'kind': 'lilygobox#appUpdateManifest',
        'channel': channel,
        'release': {'version': version},
        'windows': {
          'x64': {
            'fileName': 'LilygoBox-$version-windows-x64-setup.exe',
            'downloadUrl': 'https://github.com/example/LilygoBox-setup.exe',
            'sizeBytes': 1234,
            'sha256': 'a' * 64,
          },
        },
        'releaseNotes': ['A release note'],
      }),
      200,
    );

    test('should return a newer stable release', () async {
      final service = AppUpdateService(
        client: MockClient((_) async => response()),
      );

      final update = await service.check(
        currentVersion: '1.1.9',
        channel: AppReleaseChannel.stable,
      );

      expect(update?.version, '1.2.0');
      expect(update?.releaseNotes, ['A release note']);
      expect(update?.fileName, 'LilygoBox-1.2.0-windows-x64-setup.exe');
      expect(update?.sizeBytes, 1234);
      expect(update?.sha256, 'a' * 64);
    });

    test('should accept a newer beta release from the beta manifest', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/app-update-beta/'));
        return response(channel: 'beta', version: '1.2.0-beta.1');
      });
      final service = AppUpdateService(client: client);

      final update = await service.check(
        currentVersion: '1.1.9',
        channel: AppReleaseChannel.beta,
      );

      expect(update?.version, '1.2.0-beta.1');
    });

    test(
      'retries app update manifest through proxy after GitHub failure',
      () async {
        final requests = <Uri>[];
        final client = MockClient((request) async {
          requests.add(request.url);
          if (requests.length == 1) {
            throw http.ClientException('connection reset', request.url);
          }
          return response(channel: 'beta', version: '1.2.0-beta.1');
        });
        final service = AppUpdateService(client: client);

        final update = await service.check(
          currentVersion: '1.1.9',
          channel: AppReleaseChannel.beta,
        );

        expect(update?.version, '1.2.0-beta.1');
        expect(requests, hasLength(2));
        expect(requests.first.host, 'github.com');
        expect(
          requests.last.toString(),
          'https://gh-proxy.com/${requests.first}',
        );
      },
    );

    test('does not retry an unpublished manifest after a 404', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('not found', 404);
      });
      addTearDown(client.close);

      await expectLater(
        AppUpdateService(
          client: client,
        ).check(currentVersion: '1.1.9', channel: AppReleaseChannel.beta),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.kind,
            'kind',
            AppUpdateFailureKind.manifestNotFound,
          ),
        ),
      );
      expect(requests, 1);
    });

    test('retries app update manifest after a GitHub server error', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return requests.length == 1
            ? http.Response('unavailable', 503)
            : response(channel: 'beta', version: '1.2.0-beta.1');
      });
      addTearDown(client.close);

      final update = await AppUpdateService(
        client: client,
      ).check(currentVersion: '1.1.9', channel: AppReleaseChannel.beta);

      expect(update?.version, '1.2.0-beta.1');
      expect(requests, hasLength(2));
      expect(
        requests.last.toString(),
        'https://gh-proxy.com/${requests.first}',
      );
    });

    test('should return null when the installed version is current', () async {
      final service = AppUpdateService(
        client: MockClient((_) async => response(version: '1.2.0')),
      );

      final update = await service.check(
        currentVersion: 'v1.2.0',
        channel: AppReleaseChannel.stable,
      );

      expect(update, isNull);
    });

    test(
      'should reuse a cached installer only when its hash matches',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lilygobox-update-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final bytes = [1, 2, 3, 4];
        const fileName = 'LilygoBox-windows-x64-setup.exe';
        final installer = File('${directory.path}/1.2.0/$fileName');
        await installer.parent.create(recursive: true);
        await installer.writeAsBytes(bytes);
        final update = AppUpdate(
          version: '1.2.0',
          fileName: fileName,
          downloadUrl: Uri.https('github.com', '/example/installer.exe'),
          sizeBytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          releaseNotes: const [],
        );
        final service = AppUpdateService(updateDirectory: directory);

        expect(
          (await service.findCachedInstaller(update))?.path,
          installer.path,
        );

        await installer.writeAsBytes([9, 9, 9]);
        expect(await service.findCachedInstaller(update), isNull);
        expect(await installer.exists(), isFalse);
      },
    );

    test(
      'should reject a manifest whose version does not match its channel',
      () async {
        final service = AppUpdateService(
          client: MockClient(
            (_) async => response(channel: 'beta', version: '1.2.0'),
          ),
        );

        await expectLater(
          service.check(
            currentVersion: '1.1.9',
            channel: AppReleaseChannel.beta,
          ),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.kind,
              'kind',
              AppUpdateFailureKind.invalidManifest,
            ),
          ),
        );
      },
    );

    test('should reject malformed current versions', () async {
      final service = AppUpdateService(
        client: MockClient((_) async => response()),
      );

      await expectLater(
        service.check(
          currentVersion: 'unknown',
          channel: AppReleaseChannel.stable,
        ),
        throwsFormatException,
      );
    });

    test('should derive a prerelease version for a channel build', () {
      expect(
        appReleaseVersion('1.0.0', channel: AppReleaseChannel.beta),
        '1.0.0-beta.1',
      );
      expect(
        appReleaseVersion(
          '1.0.0',
          versionOverride: '1.0.0-beta.4',
          channel: AppReleaseChannel.beta,
        ),
        '1.0.0-beta.4',
      );
    });
  });
}
