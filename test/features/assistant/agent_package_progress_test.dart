import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/files/zstd_tar.dart';
import 'package:lilygobox/features/assistant/data/agent_compression.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'agent-package-progress-',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Map<String, Object?> payload() => {
    'type': 'chat',
    'text': List.generate(
      80000,
      (index) => 'Message $index: 聊天记录与附件。',
    ).join('\n'),
    'memories': <Object?>[],
  };

  test('exports JSON entries in a standard Zstd-compressed TAR', () async {
    final path = '${directory.path}/chat.tar.zst';
    final data = payload();
    await AgentPackage.write(path, data);
    final archive = TarDecoder().decodeBytes(
      ZstdDecoder().decodeBytes(await File(path).readAsBytes(), verify: true),
      verify: true,
    );
    expect(archive.files.map((entry) => entry.name), [
      'manifest.json',
      'data.json',
    ]);
    final [manifest, body] = archive.files;
    final decoded = utf8.decode(body.content);
    final metadata = jsonDecode(utf8.decode(manifest.content));
    expect(jsonDecode(decoded), data);
    expect(metadata, {
      'format': 'LilygoBox.agent-data',
      'version': 1,
      'type': 'chat',
      'sha256': sha256.convert(utf8.encode(decoded)).toString(),
      'size': body.size,
    });
  });

  test(
    'packages report measured checksum and IO with indeterminate codec stages',
    () async {
      final path = '${directory.path}/chat.tar.zst';
      final written = <AgentPackageProgress>[];
      final read = <AgentPackageProgress>[];
      final data = payload();
      await AgentPackage.write(path, data, onProgress: written.add);
      expect(await AgentPackage.read(path, onProgress: read.add), data);
      final compression = written
          .where((e) => e.stage == AgentPackageStage.compressing)
          .toList();
      expect(compression.single.fraction, isNull);
      final decompression = read
          .where((e) => e.stage == AgentPackageStage.decompressing)
          .toList();
      expect(decompression.single.fraction, isNull);
      expect(
        written.where((event) => event.stage == .writing).last.fraction,
        1,
      );
      expect(read.where((event) => event.stage == .reading).last.fraction, 1);
      expect(written.last.stage, AgentPackageStage.committing);
      expect(written.last.canCancel, isFalse);
      for (final events in [written, read]) {
        final checksums = events
            .where((event) => event.stage == AgentPackageStage.checksumming)
            .toList();
        expect(checksums, isNotEmpty);
        expect(checksums.first.fraction, 0);
        expect(checksums.last.fraction, 1);
        expect(
          checksums.any((event) => event.fraction! > 0 && event.fraction! < 1),
          isTrue,
        );
        var previous = 0;
        for (final event in checksums) {
          if (event.completed == 0) previous = 0;
          expect(event.completed, greaterThanOrEqualTo(previous));
          expect(event.completed, lessThanOrEqualTo(event.total!));
          previous = event.completed!;
        }
      }
      expect(directory.listSync().whereType<File>().length, 1);
    },
  );

  for (final exporting in [true, false]) {
    test(
      'cancelled ${exporting ? 'export' : 'import'} checksum preserves the original file',
      () async {
        final path = '${directory.path}/checksum.tar.zst';
        if (exporting) {
          await File(path).writeAsString('Existing destination');
        } else {
          await AgentPackage.write(path, payload());
        }
        final before = await File(path).readAsBytes();
        final cancellation = AgentPackageCancellation();
        void onProgress(AgentPackageProgress progress) {
          if (progress.stage == AgentPackageStage.checksumming &&
              progress.fraction != null &&
              progress.fraction! > 0 &&
              progress.fraction! < 1) {
            cancellation.cancel();
          }
        }

        await expectLater(
          exporting
              ? AgentPackage.write(
                  path,
                  payload(),
                  cancellation: cancellation,
                  onProgress: onProgress,
                )
              : AgentPackage.read(
                  path,
                  cancellation: cancellation,
                  onProgress: onProgress,
                ),
          throwsA(isA<AgentPackageCancelled>()),
        );
        expect(await File(path).readAsBytes(), before);
        expect(directory.listSync().whereType<File>(), hasLength(1));
      },
    );
  }

  test('cancelled compression keeps existing destination and removes temporary output', () async {
    final path = '${directory.path}/existing.tar.zst';
    await File(path).writeAsString('keep this existing file');
    final cancellation = AgentPackageCancellation();
    await expectLater(
      AgentPackage.write(
        path,
        payload(),
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.stage == AgentPackageStage.compressing) {
            cancellation.cancel();
          }
        },
      ),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(await File(path).readAsString(), 'keep this existing file');
    expect(directory.listSync().whereType<File>().map((f) => f.absolute.uri), [
      File(path).absolute.uri,
    ]);
  });

  test('cancelled decompression leaves source package unchanged', () async {
    final path = '${directory.path}/source.tar.zst';
    await AgentPackage.write(path, payload());
    final before = await File(path).readAsBytes();
    final cancellation = AgentPackageCancellation();
    await expectLater(
      AgentPackage.read(
        path,
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.stage == AgentPackageStage.decompressing) {
            cancellation.cancel();
          }
        },
      ),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(await File(path).readAsBytes(), before);
  });

  test('only a completed write replaces an existing package', () async {
    final path = '${directory.path}/existing.tar.zst';
    final original = {'type': 'memory', 'memories': <Object?>[]};
    await AgentPackage.write(path, original);
    final cancellation = AgentPackageCancellation();
    final data = payload();
    await expectLater(
      AgentPackage.write(
        path,
        data,
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.stage == .writing && progress.completed! > 0) {
            cancellation.cancel();
          }
        },
      ),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(directory.listSync().whereType<File>(), hasLength(1));
    expect(await AgentPackage.read(path), original);
    await AgentPackage.write(path, data);
    expect(await AgentPackage.read(path), data);
  });

  test(
    'adds the compound suffix without replacing an unselected file',
    () async {
      final requested = '${directory.path}/memory.zst';
      final destination = '${directory.path}/memory.tar.zst';
      final original = {'type': 'memory', 'memories': <Object?>[]};
      await AgentPackage.write(requested, original);
      expect(await AgentPackage.read(destination), original);
      await expectLater(
        AgentPackage.write(requested, payload()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await AgentPackage.read(destination), original);
    },
  );

  for (final (entryName, expectedError) in [
    ('unexpected.json', 'Invalid package structure'),
    ('data.json', 'Package checksum mismatch'),
  ]) {
    test('rejects $entryName with $expectedError', () async {
      final path = '${directory.path}/invalid.tar.zst';
      final bytes = utf8.encode('{"type":"chat"}');
      final output = OutputMemoryStream();
      ZstdTar.writer(output)
        ..add(
          ArchiveFile.bytes(
            'manifest.json',
            utf8.encode(
              jsonEncode({
                'format': 'LilygoBox.agent-data',
                'version': 1,
                'type': 'chat',
                'sha256': 'wrong checksum',
                'size': bytes.length,
              }),
            ),
          ),
        )
        ..add(ArchiveFile.bytes(entryName, bytes))
        ..close();
      await File(path).writeAsBytes(output.getBytes());
      await expectLater(
        AgentPackage.read(path),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            expectedError,
          ),
        ),
      );
    });
  }

  test('reads the long-chat fixture', () async {
    final archive = await AgentPackage.read(
      'artifacts/lilygobox-long-chat-10000.tar.zst',
    );
    expect(archive['type'], 'agent');
  });

  test(
    'reads a database object compressed with the previous Zstd implementation',
    () {
      final compressed = base64Decode(
        'sAkAAAAAAAAotS/9YLAIPQEA+ExlZ2FjeSBTUUxpdGUgb2JqZWN0IOaXp+aVsOaNrgoBADtG+MoJ',
      );
      final expected = List.filled(80, 'Legacy SQLite object 旧数据\n').join();
      expect(
        utf8.decode(AgentCompression.decompressObject(compressed)),
        expected,
      );
      final rewritten = AgentCompression.compressObject(utf8.encode(expected));
      expect(
        utf8.decode(AgentCompression.decompressObject(rewritten)),
        expected,
      );
    },
  );

  test('pre-cancelled package operation does not touch destination', () async {
    final path = '${directory.path}/data.tar.zst';
    final cancellation = AgentPackageCancellation()..cancel();
    await expectLater(
      AgentPackage.write(path, payload(), cancellation: cancellation),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(directory.listSync(), isEmpty);
  });
}
