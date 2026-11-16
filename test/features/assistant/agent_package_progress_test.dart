import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox_codecs/lilygobox_codecs.dart';

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
      (i) => 'Message $i: context and attachments.',
    ).join('\n'),
    'memories': <Object?>[],
  };

  test('codec progress streams preserve empty and multi-chunk data', () {
    for (final input in [
      Uint8List(0),
      Uint8List.fromList(List.generate(2500000, (i) => i % 251)),
    ]) {
      final encodeProgress = <int>[];
      final decodeProgress = <int>[];
      final packed = LilygoBoxCodecs.lzma2(
        input,
        onProgress: (a, b) => encodeProgress.add(a),
      );
      final output = LilygoBoxCodecs.unlzma2(
        packed,
        onProgress: (a, b) => decodeProgress.add(b),
      );
      expect(output, input);
      expect(decodeProgress.last, input.length);
      if (input.isNotEmpty) {
        expect(decodeProgress.length, greaterThan(1));
        expect(encodeProgress, isNotEmpty);
      }
    }
  });

  test(
    'packages report measured compression, decompression and writes',
    () async {
      final path = '${directory.path}/chat.7z';
      final written = <AgentPackageProgress>[];
      final read = <AgentPackageProgress>[];
      final data = payload();
      await AgentPackage.write(path, data, onProgress: written.add);
      expect(await AgentPackage.read(path, onProgress: read.add), data);
      final compression = written
          .where((e) => e.stage == AgentPackageStage.compressing)
          .toList();
      expect(compression.first.fraction, 0);
      expect(compression.last.fraction, 1);
      expect(
        compression.any((e) => e.fraction! > 0 && e.fraction! < 1),
        isTrue,
      );
      final decompression = read
          .where((e) => e.stage == AgentPackageStage.decompressing)
          .toList();
      expect(
        decompression.any((e) => e.fraction! > 0 && e.fraction! < 1),
        isTrue,
      );
      expect(written.last.stage, AgentPackageStage.committing);
      expect(written.last.canCancel, isFalse);
      expect(directory.listSync().whereType<File>().length, 1);
    },
  );

  test('cancelled compression keeps existing destination and removes temporary output', () async {
    final path = '${directory.path}/existing.7z';
    await File(path).writeAsString('keep this existing file');
    final cancellation = AgentPackageCancellation();
    await expectLater(
      AgentPackage.write(
        path,
        payload(),
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.stage == AgentPackageStage.compressing &&
              progress.fraction != null &&
              progress.fraction! > 0 &&
              progress.fraction! < 1) {
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
    final path = '${directory.path}/source.7z';
    await AgentPackage.write(path, payload());
    final before = await File(path).readAsBytes();
    final cancellation = AgentPackageCancellation();
    await expectLater(
      AgentPackage.read(
        path,
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.stage == AgentPackageStage.decompressing &&
              progress.fraction != null &&
              progress.fraction! > 0 &&
              progress.fraction! < 1) {
            cancellation.cancel();
          }
        },
      ),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(await File(path).readAsBytes(), before);
  });

  test(
    'native codecs stop inside measurable compression and decompression',
    () {
      final input = Uint8List.fromList(
        List.generate(4 * 1024 * 1024, (i) => i % 251),
      );
      final encodeCancel = CodecCancellation();
      final decodeCancel = CodecCancellation();
      try {
        var lastEncoded = 0;
        expect(
          () => LilygoBoxCodecs.lzma2(
            input,
            cancellation: encodeCancel,
            onProgress: (consumed, output) {
              lastEncoded = consumed;
              if (consumed > 0 && consumed < input.length) {
                encodeCancel.cancel();
              }
            },
          ),
          throwsA(isA<CodecCancelled>()),
        );
        expect(lastEncoded, greaterThan(0));
        expect(lastEncoded, lessThan(input.length));
        final compressed = LilygoBoxCodecs.lzma2(input);
        var lastDecoded = 0;
        expect(
          () => LilygoBoxCodecs.unlzma2(
            compressed,
            cancellation: decodeCancel,
            onProgress: (consumed, output) {
              lastDecoded = output;
              if (output > 0 && output < input.length) decodeCancel.cancel();
            },
          ),
          throwsA(isA<CodecCancelled>()),
        );
        expect(lastDecoded, greaterThan(0));
        expect(lastDecoded, lessThan(input.length));
        // A subsequent operation succeeds after cancelled operations freed their buffers.
        expect(LilygoBoxCodecs.unlzma2(compressed), input);
      } finally {
        encodeCancel.dispose();
        decodeCancel.dispose();
      }
    },
  );

  test('pre-cancelled package operation does not touch destination', () async {
    final path = '${directory.path}/data.7z';
    final cancellation = AgentPackageCancellation()..cancel();
    await expectLater(
      AgentPackage.write(path, payload(), cancellation: cancellation),
      throwsA(isA<AgentPackageCancelled>()),
    );
    expect(directory.listSync(), isEmpty);
  });
}
