import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/files/package_transfer.dart';
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

  test(
    'cancels model extraction without installing or leaving files',
    () async {
      final source = await fixture('recognition', .bilingualZipformer);
      await modelRoot.create();
      final initial = await store.read();
      late final PackageTransfer transfer;
      transfer = PackageTransfer(
        onProgress: (progress) {
          if (progress.stage == .decompressing) transfer.cancel();
        },
      );

      await expectLater(
        store.import(initial, source, check: check, transfer: transfer),
        throwsA(isA<PackageCancelled>()),
      );
      expect((await store.read()).models, isEmpty);
      expect(await modelRoot.list().isEmpty, isTrue);
    },
  );

  test(
    'counts stored model files without counting temporary imports',
    () async {
      expect(await store.readStorageBytes(), 0);
      const format = SpeechModelFormat.chineseVits;
      final source = await fixture('synthesis', format);
      final library = await store.import(SpeechLibrary(), source, check: check);
      final scratch = await modelRoot.createTemp('import-');
      await File(path.join(scratch.path, 'source.tar'))
          .writeAsString('temporary');
      final bytes = format.files.fold(0, (total, file) => total + file.length);
      expect(await store.readStorageBytes(), bytes);
      await store.delete(library, library.models.single);
      expect(await store.readStorageBytes(), 0);
    },
  );

  test('persists upstream files and models without global defaults', () async {
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
    final voiceModel = synthesized.models.singleWhere(
      (model) => model.kind == .synthesis,
    );
    final installed = await store.directoryFor(voiceModel);
    expect(File(path.join(installed.path, 'README.md')).existsSync(), isFalse);
    expect(
      File(path.join(installed.path, 'dict', 'jieba.dict.utf8')).existsSync(),
      isTrue,
    );
    await File(tts).delete();

    final reopened = await SpeechModelStore(directory: modelRoot).read();
    expect(
      reopened.models.map((model) => model.id),
      synthesized.models.map((model) => model.id),
    );
    expect(reopened.models.last.name, '中文语音');
    expect(reopened.synthesisModel(null), isNull);
    expect(reopened.recognitionModel(null), isNull);
    final index = jsonDecode(
      await File(path.join(modelRoot.path, 'library.json')).readAsString(),
    ) as Map<String, Object?>;
    expect(index.keys, ['models']);
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
      expect(broken.models.single.id, model.id);
      expect(broken.models.single.available, isFalse);
      expect(broken.recognitionModel(model.id), isNull);
      await expectLater(
        store.directoryFor(model),
        throwsA(failure(.missingFiles)),
      );
      final repaired = await store.import(broken, asr, check: check);
      expect(repaired.recognitionModel(model.id)?.id, model.id);
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

  test('deleting one synthesis model never falls back to another', () async {
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
    final model = withSecond.models.last;
    final installed = await store.directoryFor(model);
    await store.delete(withSecond, model);
    final reopened = await store.read();
    expect(reopened.recognitionModel(withAsr.models.single.id), isNotNull);
    expect(reopened.synthesisModel((modelId: model.id, voice: 0)), isNull);
    expect(reopened.models, hasLength(2));
    expect(installed.existsSync(), isFalse);
  });

  test(
    'batch deletion restores model files when the index write fails',
    () async {
      final asr = await fixture('recognition', .bilingualZipformer);
      final tts = await fixture('synthesis', .chineseVits);
      final withAsr = await store.import(SpeechLibrary(), asr, check: check);
      final library = await store.import(withAsr, tts, check: check);
      final index = File(path.join(modelRoot.path, 'library.json'));
      final original = await index.rename('${index.path}.backup');
      final obstruction = await Directory(index.path).create();
      final ids = {for (final model in library.models) model.id};

      await expectLater(
        store.deleteModels(library, ids),
        throwsA(failure(.storage)),
      );

      await obstruction.delete();
      await original.rename(index.path);
      expect(
        (await store.read()).models.map((model) => model.id),
        unorderedEquals(ids),
      );
      for (final model in library.models) {
        expect(await (await store.directoryFor(model)).exists(), isTrue);
      }
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
      await store.export([model], destination);

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
        unorderedEquals([
          'voice-models.json',
          for (final relative in format.files) 'models/0/$relative',
        ]),
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
      expect(imported.models.single.name, model.name);
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
    'round trips mixed models with identical names and skips installed copies',
    () async {
      final tts = await fixture('shared', .chineseVits);
      final first = await store.import(SpeechLibrary(), tts, check: check);
      final asr = await fixture('shared', .bilingualZipformer);
      final library = await store.import(first, asr, check: check);
      final destination = path.join(workspace.path, 'mixed.tar.zst');
      await store.export(library.models, destination);

      final receiver = SpeechModelStore(
        directory: Directory(path.join(workspace.path, 'receiver')),
      );
      final existing = await receiver.import(
        SpeechLibrary(),
        asr,
        check: check,
      );
      final checkedFormats = <SpeechModelFormat>[];
      final restored = await receiver.import(
        existing,
        destination,
        check: (format, directory) {
          checkedFormats.add(format);
          return check(format, directory);
        },
      );
      expect(checkedFormats, [SpeechModelFormat.chineseVits]);
      expect(
        restored.models.map((model) => model.id),
        unorderedEquals(library.models.map((model) => model.id)),
      );
      expect(restored.models.map((model) => model.name), ['shared', 'shared']);
      expect((await receiver.read()).models, hasLength(2));
    },
  );

  test('preserves and hashes the Kokoro phonemizer resources', () async {
    const format = SpeechModelFormat.kokoroMultiLanguage;
    const resource = 'espeak-ng-data/voices/!v/example';
    final source = await speechArchiveFixture(
      workspace,
      'upstream',
      format,
      modelFolder: 'kokoro-multi-lang-v1_0',
      extra: {resource: 'voice configuration', 'README.md': 'documentation'},
    );
    final original = await store.import(SpeechLibrary(), source, check: check);
    final model = original.models.single;
    expect(model.format, format);
    expect(model.name, 'kokoro-multi-lang-v1_0');

    final destination = path.join(workspace.path, 'kokoro.tar.zst');
    await store.export(original.models, destination);
    final receiver = SpeechModelStore(
      directory: Directory(path.join(workspace.path, 'receiver')),
    );
    final restored = await receiver.import(
      SpeechLibrary(),
      destination,
      check: check,
    );
    expect(restored.models.single.id, model.id);
    final directory = await receiver.directoryFor(restored.models.single);
    final voice = File(path.joinAll([directory.path, ...resource.split('/')]));
    expect(await voice.readAsString(), 'voice configuration');
    expect(
      await File(path.join(directory.path, 'README.md')).exists(),
      isFalse,
    );

    await File(path.join(directory.path, 'espeak-ng-data', 'phondata'))
        .delete();
    expect((await receiver.read()).models.single.available, isFalse);
  });

  test('rejects colliding paths in Kokoro phonemizer resources', () async {
    final source = await speechArchiveFixture(
      workspace,
      'colliding',
      .kokoroMultiLanguage,
      extra: {'espeak-ng-data/Lang/other': 'another file'},
    );
    await expectLater(
      store.import(SpeechLibrary(), source, check: check),
      throwsA(failure(.invalidPackage)),
    );
  });

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
