import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/features/devices/data/firmware_update_service.dart';

Map<String, dynamic> manifest({String version = '2.0'}) =>
    jsonDecode(
          jsonEncode({
            'kind': 'lilygobox#otaManifest',
            'manifestVersion': version,
            'channel': 'stable',
            'release': {
              'publisherId': 'lilygo',
              'deviceId': 't-display-p4',
              'version': '1.1.3',
            },
            'targets': [
              {
                'compatibility': {
                  'deviceVersion': '1.0',
                  'chips': {
                    'main': {
                      'model': 'esp32p4',
                      if (version == '1.0')
                        'revision': '1.0'
                      else ...{
                        'minRevision': '0.0',
                        'maxRevision': '1.99',
                      },
                    },
                    'wireless': {
                      'model': 'esp32c6',
                      if (version == '1.0')
                        'revision': '0.0'
                      else ...{
                        'minRevision': '0.0',
                        'maxRevision': '0.0',
                      },
                    },
                  },
                },
                'components': {'main': 'main', 'wireless': 'wireless'},
              },
            ],
            'files': {
              for (final role in ['main', 'wireless'])
                role: {
                  'chip': role == 'main' ? 'esp32p4' : 'esp32c6',
                  'projectName': role == 'main'
                      ? 'lilygobox-espidf'
                      : 'network_adapter',
                  'version': role == 'main' ? '1.1.3' : '2.12.3',
                  'sizeBytes': 123,
                  'hashes': {'sha256': List.filled(64, 'a').join()},
                  if (version == '1.0')
                    'downloadUrls': ['https://example.com/$role.bin']
                  else
                    'downloadUrl': 'https://example.com/$role.bin',
                },
            },
            'releaseNotes': ['Update'],
          }),
        )
        as Map<String, dynamic>;

Future<FirmwareRelease?> check(
  Map<String, dynamic> data, {
  String model = 'T-Display-P4',
  String modelVersion = '1.0',
  FirmwareHardware? hardware,
}) async {
  final client = MockClient(
    (request) async => http.Response(jsonEncode(data), 200),
  );
  addTearDown(client.close);
  return FirmwareUpdateService(client: client).check(
    model: model,
    modelVersion: modelVersion,
    hardware: hardware,
    mainCurrent: '1.1.2',
    wirelessCurrent: '2.12.3',
  );
}

void main() {
  test('network failure retries the same manifest through the proxy', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (requests.length == 1) {
        throw http.ClientException('connection reset', request.url);
      }
      return http.Response(jsonEncode(manifest()), 200);
    });
    addTearDown(client.close);
    final release = await FirmwareUpdateService(client: client).check(
      model: 'T-Display-P4',
      modelVersion: '1.0',
      mainCurrent: '1.1.2',
      wirelessCurrent: '2.12.3',
    );
    expect(release?.mainVersion, '1.1.3');
    expect(requests, hasLength(2));
    expect(requests.first.host, 'github.com');
    expect(requests.last.toString(), 'https://gh-proxy.com/${requests.first}');
  });

  test('HTTP 404 retries the manifest through the proxy', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (requests.length == 1) {
        return http.Response('Not found', 404);
      }
      return http.Response(jsonEncode(manifest()), 200);
    });
    addTearDown(client.close);
    final release = await FirmwareUpdateService(client: client).check(
      model: 'T-Display-P4',
      modelVersion: '1.0',
      mainCurrent: '1.1.2',
      wirelessCurrent: '2.12.3',
    );
    expect(release?.mainVersion, '1.1.3');
    expect(requests, hasLength(2));
    expect(requests.first.host, 'github.com');
    expect(requests.last.toString(), 'https://gh-proxy.com/${requests.first}');
  });

  test('HTTP failures retain status instead of reporting up to date', () async {
    final client = MockClient((_) async => http.Response('Unavailable', 503));
    addTearDown(client.close);
    await expectLater(
      FirmwareUpdateService(client: client).check(
        model: 'T-Display-P4',
        modelVersion: '2.0',
        mainCurrent: '1.1.2',
        wirelessCurrent: '2.12.3',
      ),
      throwsA(
        isA<FirmwareManifestException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('hardware versions select the matching product manifest', () {
    for (final (model, version, product) in [
      ('T-Display-P4', '1.0', 't-display-p4'),
      ('T-Display-P4', 'v2.0', 't-display-p4'),
      ('T-Display-P4-Air', '1.0', 't-display-p4-air'),
      ('T-Display-P4-Air', 'v2.0', 't-display-p4-air'),
    ]) {
      expect(
        FirmwareUpdateService.manifestUriFor(model, version).path,
        endsWith('lilygobox-$product-ota-manifest-stable-v2.json'),
      );
    }
    expect(
      () => FirmwareUpdateService.manifestUriFor('Other', '1.0'),
      throwsFormatException,
    );
  });

  test('v2 ranges and legacy exact manifest select the release', () async {
    for (final version in ['1.0', '2.0']) {
      final release = await check(manifest(version: version));
      expect(release?.mainVersion, '1.1.3');
      expect(release?.needsWirelessUpdate('2.12.3'), isFalse);
    }
  });

  test('v2 requires one canonical GitHub download URL per component', () async {
    final data = manifest();
    data['files']['main']['version'] = '1.1.4';
    data['files']['main']['downloadUrl'] =
        'https://github.com/owner/repo/releases/download/v1.1.3/main.bin';
    final release = await check(data);
    expect(release, isNotNull);

    data['files']['main'].remove('downloadUrl');
    data['files']['main']['downloadUrls'] = [
      'https://github.com/owner/repo/releases/download/v1.1.3/main.bin',
    ];
    await expectLater(check(data), throwsFormatException);

    final v1 = manifest(version: '1.0');
    v1['files']['main']['downloadUrls'] = [
      'https://github.com/owner/repo/releases/download/v1.1.3/main.bin',
      'https://gh-proxy.com/https://github.com/owner/repo/releases/download/v1.1.3/main.bin',
    ];
    expect((await check(v1))?.mainUrl.host, 'github.com');
  });

  test('unchanged component versions hide update entry', () async {
    final data = manifest();
    data['files']['main']['version'] = '1.1.2';
    expect(await check(data), isNull);
  });

  test(
    'reject unsupported protocol and wrong board, product, chip or project',
    () async {
      final mutations = <void Function(Map<String, dynamic>)>[
        (data) => data['manifestVersion'] = '3.0',
        (data) => data['channel'] = 'beta',
        (data) => data['release']['deviceId'] = 't-display-p4-air',
        (data) => data['targets'][0]['compatibility']['deviceVersion'] = '2.0',
        (data) =>
            data['targets'][0]['compatibility']['chips']['wireless']['model'] =
                'esp32c5',
        (data) => data['files']['main']['projectName'] = 'other',
      ];
      for (final mutate in mutations) {
        final data = manifest();
        mutate(data);
        await expectLater(check(data), throwsFormatException);
      }
    },
  );

  test(
    'reject incomplete reversed or invalid ranges and malformed targets',
    () async {
      for (final maximum in ['0.0', '1.100', 'v1.99', null]) {
        final data = manifest();
        data['targets'][0]['compatibility']['chips']['main']
          ..['minRevision'] = '1.0'
          ..['maxRevision'] = maximum;
        await expectLater(check(data), throwsFormatException);
      }
      final data = manifest();
      data['targets'] = ['invalid'];
      await expectLater(check(data), throwsFormatException);
    },
  );

  test(
    'ambiguous component mappings are rejected before firmware download',
    () async {
      final data = manifest();
      final target = jsonDecode(jsonEncode(data['targets'][0]));
      target['components']['main'] = 'another-main';
      data['targets'].add(target);
      await expectLater(check(data), throwsFormatException);
    },
  );

  Map<String, dynamic> airManifest() {
    final data = manifest();
    data['release']['deviceId'] = 't-display-p4-air';
    data['targets'] = [
      for (final board in ['1.0', '2.0'])
        for (final series in [1, 2])
          {
            'compatibility': {
              'deviceVersion': board,
              'chips': {
                'main': {
                  'model': 'esp32p4',
                  'minRevision': '$series.0',
                  'maxRevision': '$series.99',
                },
                'wireless': {
                  'model': 'esp32c5',
                  'minRevision': '1.0',
                  'maxRevision': '1.0',
                },
              },
            },
            'components': {
              'main': 'board-$board-chip-$series',
              'wireless': 'wireless',
            },
          },
    ];
    data['files']['wireless']['chip'] = 'esp32c5';
    for (final board in ['1.0', '2.0']) {
      for (final series in [1, 2]) {
        data['files']['board-$board-chip-$series'] = {
          ...data['files']['main'] as Map<String, dynamic>,
          'downloadUrl': 'https://example.com/board-$board-chip-$series.bin',
        };
      }
    }
    return data;
  }

  FirmwareHardware hardware(String revision) => FirmwareHardware(
    main: FirmwareChip(model: 'esp32p4', revision: revision),
    wireless: const FirmwareChip(model: 'esp32c5', revision: '1.0'),
  );

  test(
    'one Air manifest selects board and actual chip revision together',
    () async {
      for (final board in ['1.0', '2.0']) {
        for (final revision in ['1.0', '1.3', '1.99', '2.0', '2.99']) {
          final release = await check(
            airManifest(),
            model: 'T-Display-P4-Air',
            modelVersion: board,
            hardware: hardware(revision),
          );
          expect(
            release?.mainUrl.path,
            '/board-$board-chip-${revision.split('.').first}.bin',
          );
          expect(release?.wirelessUrl.path, '/wireless.bin');
        }
      }
    },
  );

  test('unknown chip or board never selects an incompatible variant', () async {
    for (final revision in ['0.99', '3.0', '1.100']) {
      await expectLater(
        check(
          airManifest(),
          model: 'T-Display-P4-Air',
          hardware: hardware(revision),
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      check(
        airManifest(),
        model: 'T-Display-P4-Air',
        modelVersion: '3.0',
        hardware: hardware('1.3'),
      ),
      throwsFormatException,
    );
    await expectLater(
      check(airManifest(), model: 'T-Display-P4-Air'),
      throwsFormatException,
    );
  });

  test(
    'overlapping matching chip targets are rejected even with shared files',
    () async {
      final data = airManifest();
      data['targets'].add(data['targets'][0]);
      await expectLater(
        check(data, model: 'T-Display-P4-Air', hardware: hardware('1.3')),
        throwsFormatException,
      );
    },
  );

  test(
    'device chip metadata accepts full revisions and rejects malformed values',
    () {
      expect(FirmwareHardware.fromJson(null), isNull);
      final chips = {
        'main': {
          'model': 'esp32p4',
          'revision': '1.3',
          'revisionSource': 'runtime',
        },
        'wireless': {
          'model': 'esp32c5',
          'revision': '1.0',
          'revisionSource': 'boardConfig',
        },
      };
      expect(FirmwareHardware.fromJson(chips)?.main.revision, '1.3');
      chips['main']!['revision'] = '1.100';
      expect(() => FirmwareHardware.fromJson(chips), throwsFormatException);
      expect(
        () => FirmwareHardware.fromJson({'main': chips['main']}),
        throwsFormatException,
      );
    },
  );
}
