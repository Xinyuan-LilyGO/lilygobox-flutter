import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/speech/data/speech_model_store.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:path/path.dart' as path;

import 'speech_package_fixture.dart';

void main() {
  late Directory workspace;
  late Directory modelRoot;
  late SpeechModelStore store;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('lilygobox-voice-test-');
    modelRoot = Directory(path.join(workspace.path, 'store'));
    store = SpeechModelStore(directory: modelRoot);
  });

  tearDown(() => workspace.delete(recursive: true));

  Future<String> fixture(String name, SpeechModelFormat format) =>
      speechArchiveFixture(workspace, name, format);

  Future<int> check(SpeechModelFormat format, Directory directory) async =>
      format.kind == .synthesis ? 5 : 0;

  Matcher failure(SpeechFailureReason reason) =>
      isA<SpeechFailure>().having((error) => error.reason, 'reason', reason);

  test('copies upstream files and restores both defaults and voice', () async {
    final asr = await fixture('recognition', .bilingualZipformer);
    final tts = await speechArchiveFixture(
      workspace,
      'upstream',
      .chineseVits,
      modelFolder: '中文语音',
      extra: {'README.md': 'upstream docs'},
    );
    final initial = await store.read();
    final recognized = await store.import(initial, asr, check: check);
    final synthesized = await store.import(recognized, tts, check: check);
    final selected = await store.selectVoice(synthesized, 3);
    final voiceModel = selected.selectedModel(.synthesis)!;
    final installed = await store.directoryFor(voiceModel);
    expect(File(path.join(installed.path, 'README.md')).existsSync(), isFalse);
    expect(
      File(path.join(installed.path, 'dict', 'jieba.dict.utf8')).existsSync(),
      isTrue,
    );
    await File(tts).delete();

    final reopened = await SpeechModelStore(directory: modelRoot).read();
    expect(reopened.recognitionId, selected.recognitionId);
    expect(reopened.selectedModel(.synthesis)?.name, '中文语音');
    expect(reopened.voice, 3);
  });

  test('detects a copied model regardless of its folder name', () async {
    final first = await fixture('original', .bilingualZipformer);
    final duplicate = await fixture('renamed', .bilingualZipformer);
    final library = await store.import(await store.read(), first, check: check);

    await expectLater(
      store.import(
        library,
        duplicate,
        check: (_, _) async {
          fail('A duplicate should not be sent to the inference engine');
        },
      ),
      throwsA(failure(.duplicateModel)),
    );
    expect(await modelRoot.list().length, 2);
    expect((await store.read()).models, hasLength(1));
  });

  test(
    'refuses incomplete input and restores a missing installed file',
    () async {
      final asr = await fixture('recognition', .bilingualZipformer);
      final incomplete = await speechArchiveFixture(
        workspace,
        'incomplete',
        .bilingualZipformer,
        missing: 'tokens.txt',
      );
      final empty = await store.read();
      await expectLater(
        store.import(empty, incomplete, check: check),
        throwsA(failure(.missingFiles)),
      );
      final library = await store.import(empty, asr, check: check);
      final model = library.models.single;
      final installed = await store.directoryFor(model);
      await File(path.join(installed.path, 'tokens.txt')).delete();

      final broken = await store.read();
      expect(broken.recognitionId, model.id);
      expect(broken.models.single.available, isFalse);
      expect(broken.selectedModel(.recognition), isNull);
      await expectLater(
        store.directoryFor(model),
        throwsA(failure(.missingFiles)),
      );
      final repaired = await store.import(broken, asr, check: check);
      expect(repaired.selectedModel(.recognition)?.id, model.id);
      expect((await store.read()).models.single.available, isTrue);
    },
  );

  test(
    'invalid native model does not add a library entry or retain files',
    () async {
      final tts = await fixture('synthesis', .chineseVits);
      final initial = await store.read();
      await expectLater(
        store.import(initial, tts, check: (_, _) async => 0),
        throwsA(failure(.invalidModel)),
      );
      expect((await store.read()).models, isEmpty);
      expect(await modelRoot.list().isEmpty, isTrue);
    },
  );

  test(
    'switching synthesis resets voice and deletion clears only its default',
    () async {
      final asr = await fixture('recognition', .bilingualZipformer);
      final tts = await fixture('synthesis', .chineseVits);
      final second = await speechArchiveFixture(
        workspace,
        'second',
        .chineseVits,
        extra: {'model.onnx': 'changed'},
      );
      final withAsr = await store.import(await store.read(), asr, check: check);
      final withTts = await store.import(withAsr, tts, check: check);
      final withSecond = await store.import(withTts, second, check: check);
      final choice = await store.selectVoice(withSecond, 4);
      final model = choice.models.last;
      final switched = await store.select(choice, model);
      expect(switched.voice, 0);
      expect(switched.synthesisId, model.id);

      final installed = await store.directoryFor(model);
      await store.delete(switched, model);
      final reopened = await store.read();
      expect(reopened.recognitionId, withAsr.recognitionId);
      expect(reopened.synthesisId, isNull);
      expect(reopened.models, hasLength(2));
      expect(installed.existsSync(), isFalse);
    },
  );

  test(
    'exports standard Zstd TAR, reimports byte for byte, and deduplicates',
    () async {
      const format = SpeechModelFormat.chineseVits;
      final upstream = await fixture('upstream', format);
      final library = await store.import(
        await store.read(),
        upstream,
        check: check,
      );
      final model = library.models.single;
      final destination = path.join(workspace.path, 'exported');
      await store.export(model, destination);

      final archivePath = '$destination.tar.zst';
      final archive = TarDecoder().decodeBytes(
        ZstdDecoder().decodeBytes(
          await File(archivePath).readAsBytes(),
          verify: true,
        ),
        verify: true,
      );
      expect(
        archive.files.map((entry) => entry.name),
        unorderedEquals(format.files),
      );

      final receivingStore = SpeechModelStore(
        directory: Directory(path.join(workspace.path, 'receiving')),
      );
      final imported = await receivingStore.import(
        await receivingStore.read(),
        archivePath,
        check: check,
      );
      expect(imported.models.single.id, model.id);
      expect(imported.models.single.name, 'exported');
      final installed = await receivingStore.directoryFor(
        imported.models.single,
      );
      for (final relative in format.files) {
        expect(
          await File(path.join(installed.path, relative)).readAsString(),
          relative,
        );
      }
      await expectLater(
        store.import(library, archivePath, check: check),
        throwsA(failure(.duplicateModel)),
      );
    },
  );

  test(
    'rejects a damaged package and rejects traversal before installing',
    () async {
      final unrelated = await File(
        path.join(workspace.path, 'not-a-model.tar.zst'),
      ).writeAsString('Not an archive');
      final unsafe = await speechArchiveFixture(
        workspace,
        'unsafe',
        .bilingualZipformer,
        extra: {'../../outside': 'not a model file'},
      );
      final library = await store.read();
      for (final package in [unrelated.path, unsafe]) {
        await expectLater(
          store.import(library, package, check: check),
          throwsA(failure(.invalidPackage)),
        );
      }
      expect(await modelRoot.list().isEmpty, isTrue);
      expect(File(path.join(workspace.path, 'outside')).existsSync(), isFalse);
    },
  );
}
