/*
 * @Description: 验证模型服务持久化、排序、迁移与写入失败回滚。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-09 09:45:46
 */

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/features/assistant/data/model_service_repository.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

import 'assistant_test_scope.dart';

void main() {
  late _Storage storage;
  late AppPreferences preferences;
  late MemoryAiCredentialStore keys;
  late ModelServiceRepository repository;
  setUp(() async {
    storage = _Storage();
    preferences = await AppPreferences.load(storage: storage);
    keys = MemoryAiCredentialStore();
    repository = ModelServiceRepository(preferences, keys);
    await repository.load();
  });
  tearDown(() => preferences.dispose());

  Future<String> add(String name, String key) => repository.save(
    name: name,
    protocol: AiApiProtocol.openAiChatCompletions,
    baseUrl: 'https://$name.test/v1',
    models: ['chat', 'reason'],
    apiKey: key,
  );

  test(
    'fresh install has no services or model, including after reload',
    () async {
      expect(repository.services, isEmpty);
      expect(repository.selectedService, isNull);
      expect(repository.selectedModel, isNull);
      expect(keys.values, isEmpty);
      await repository.load();
      expect(repository.services, isEmpty);
    },
  );

  test(
    'keys are isolated and never serialized; selected model survives reload',
    () async {
      final first = await add('first', 'secret-first');
      final second = await add('second', 'secret-second');
      await repository.select(second, 'reason');
      expect(repository.keyFor(first), 'secret-first');
      expect(repository.keyFor(second), 'secret-second');
      expect(storage.value, isNot(contains('secret-')));
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.selectedService?.id, second);
      expect(restored.selectedModel, 'reason');
      expect(restored.services, hasLength(2));
    },
  );

  test('legacy provider values restore as Chat Completions protocol', () {
    final legacy = AiModelService.fromJson({
      'id': 'legacy',
      'name': 'DeepSeek',
      'provider': 'deepSeek',
      'baseUrl': 'https://api.deepseek.com',
      'models': ['deepseek-chat'],
    });
    expect(legacy.protocol, AiApiProtocol.openAiChatCompletions);
    expect(legacy.preset, AiServicePreset.custom);
    expect(
      AiModelService.fromJson({...legacy.toJson()}).protocol,
      AiApiProtocol.openAiChatCompletions,
    );
  });

  test(
    'reordering persists without changing the selected model or keys',
    () async {
      final first = await add('first', 'secret-first');
      final second = await add('second', 'secret-second');
      final third = await add('third', 'secret-third');
      await repository.select(second, 'reason');
      await repository.reorder(2, 0);
      expect(repository.services.map((service) => service.id), [
        third,
        first,
        second,
      ]);
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.services.map((service) => service.id), [
        third,
        first,
        second,
      ]);
      expect(restored.selectedId, second);
      expect(restored.selectedModel, 'reason');
      expect(restored.keyFor(first), 'secret-first');
    },
  );

  test('failed reordering retains the previous order', () async {
    final first = await add('first', 'secret-first');
    final second = await add('second', 'secret-second');
    storage.fail = true;
    await expectLater(
      repository.reorder(1, 0),
      throwsA(isA<AiConfigurationException>()),
    );
    expect(repository.services.map((service) => service.id), [first, second]);
    storage.fail = false;
    await preferences.flush();
  });

  test('Responses protocol persists and restores with its service', () async {
    final id = await repository.save(
      name: 'OpenAI',
      protocol: AiApiProtocol.openAiResponses,
      baseUrl: 'https://api.openai.com/v1',
      models: ['gpt-4.1-mini'],
      apiKey: 'responses-key',
    );
    final restored = ModelServiceRepository(preferences, keys);
    await restored.load();
    expect(restored.find(id)?.protocol, AiApiProtocol.openAiResponses);
    expect(restored.selectedModel, 'gpt-4.1-mini');
  });

  test(
    'official presets persist their canonical endpoint and protocol',
    () async {
      final deepSeekId = await repository.save(
        name: 'DeepSeek official',
        preset: AiServicePreset.deepSeek,
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://ignored.example',
        models: ['deepseek-chat'],
        apiKey: 'deepseek-key',
      );
      final openAiId = await repository.save(
        name: 'OpenAI official',
        preset: AiServicePreset.openAi,
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://ignored.example',
        models: ['gpt-4.1-mini'],
        apiKey: 'openai-key',
      );

      final deepSeek = repository.find(deepSeekId)!;
      expect(deepSeek.baseUrl, 'https://api.deepseek.com');
      expect(deepSeek.protocol, AiApiProtocol.openAiChatCompletions);
      final openAi = repository.find(openAiId)!;
      expect(openAi.baseUrl, 'https://api.openai.com/v1');
      expect(openAi.protocol, AiApiProtocol.openAiResponses);
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.find(openAiId)?.preset, AiServicePreset.openAi);
      await expectLater(
        repository.save(
          id: deepSeekId,
          name: 'Custom DeepSeek',
          preset: AiServicePreset.custom,
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://api.deepseek.com',
          models: ['deepseek-chat'],
        ),
        throwsA(
          isA<AiConfigurationException>().having(
            (error) => error.problem,
            'problem',
            AiProblem.keyRequired,
          ),
        ),
      );
    },
  );

  test(
    'editing keeps key on same origin and rejects reusing it on another origin',
    () async {
      final id = await add('first', 'secret-first');
      await repository.save(
        id: id,
        name: 'renamed',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://first.test/v2',
        models: ['updated'],
      );
      expect(repository.selectedModel, 'updated');
      expect(repository.keyFor(id), 'secret-first');
      await expectLater(
        repository.save(
          id: id,
          name: 'renamed',
          preset: AiServicePreset.openAi,
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://another.test/v1',
          models: ['updated'],
        ),
        throwsA(
          isA<AiConfigurationException>().having(
            (e) => e.problem,
            'problem',
            AiProblem.keyRequired,
          ),
        ),
      );
      expect(repository.selectedService?.baseUrl, 'https://first.test/v2');
    },
  );

  test(
    'removing selected service switches safely and an empty catalog stays empty',
    () async {
      final first = await add('first', 'secret-first');
      final second = await add('second', 'secret-second');
      await repository.remove(first);
      expect(repository.selectedService?.id, second);
      expect(repository.keyFor(first), isNull);
      expect(keys.values.containsKey(first), isFalse);
      await repository.remove(second);
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.services, isEmpty);
      expect(restored.selectedModel, isNull);
    },
  );

  test(
    'failed catalog write does not add a service or retain its new key',
    () async {
      await add('first', 'secret-first');
      storage.fail = true;
      await expectLater(
        add('second', 'secret-second'),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(repository.services, hasLength(1));
      expect(keys.values.values, ['secret-first']);
      storage.fail = false;
      await preferences.flush();
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.services.single.name, 'first');
    },
  );

  test('failed removal restores key and retains selected service', () async {
    final id = await add('first', 'secret-first');
    storage.fail = true;
    await expectLater(
      repository.remove(id),
      throwsA(isA<AiConfigurationException>()),
    );
    expect(repository.selectedService?.id, id);
    expect(keys.values[id], 'secret-first');
    storage.fail = false;
    await preferences.flush();
  });

  test('only explicit legacy configuration with a key is migrated', () async {
    preferences.setValue('ai.baseUrl', 'https://api.deepseek.com');
    preferences.setValue('ai.model', 'deepseek-chat');
    await preferences.flush();
    final withoutKey = ModelServiceRepository(preferences, keys);
    await withoutKey.load();
    expect(withoutKey.services, isEmpty);
    await keys.write('legacy-secret');
    final migrated = ModelServiceRepository(preferences, keys);
    await migrated.load();
    expect(migrated.services.single.name, 'DeepSeek');
    expect(migrated.keyFor(migrated.selectedId), 'legacy-secret');
    await migrated.remove(migrated.selectedId!);
    final restored = ModelServiceRepository(preferences, keys);
    await restored.load();
    expect(restored.services, isEmpty);
  });

  test(
    'malformed saved catalog fails without replacing original data',
    () async {
      preferences.setValue(ModelServiceRepository.catalogKey, '{invalid');
      await preferences.flush();
      await expectLater(
        repository.load(),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(
        jsonDecode(storage.value!)[ModelServiceRepository.catalogKey],
        '{invalid',
      );
    },
  );
}

class _Storage implements PreferencesStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('write failed');
    this.value = value;
  }
}
