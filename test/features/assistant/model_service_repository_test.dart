/*
 * @Description: 验证模型服务持久化、排序、迁移与写入失败回滚。
 */

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/features/assistant/data/model_service_repository.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';

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

  test('legacy manual declarations are ignored', () {
    final service = AiModelService.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'protocol': 'openAiChatCompletions',
      'baseUrl': 'https://example.test/v1',
      'models': ['chat'],
      'imageInputs': {'chat': 'unsupported'},
    });
    expect(service.imageInputFor('chat'), AiImageInput.unknown);
  });

  test(
    'image declarations persist per service and expire on endpoint change',
    () async {
      final first = await repository.save(
        name: 'First',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['chat', 'vision'],
        apiKey: 'key',
        imageInputs: {
          'chat': AiImageInput.unsupported,
          'vision': AiImageInput.supported,
        },
      );
      final second = await add('Second', 'key');
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(
        restored.find(first)!.imageInputFor('chat'),
        AiImageInput.unsupported,
      );
      expect(
        restored.find(second)!.imageInputFor('chat'),
        AiImageInput.unknown,
      );
      await restored.save(
        id: first,
        name: 'First',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['chat'],
      );
      expect(restored.find(first)!.imageInputs.keys, ['chat']);
      await restored.save(
        id: first,
        name: 'First',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v2',
        models: ['chat'],
      );
      expect(restored.find(first)!.imageInputFor('chat'), AiImageInput.unknown);
    },
  );
  test(
    'reasoning is isolated by service and model and persists concrete levels',
    () async {
      Future<String> addReasoning(String name) => repository.save(
        name: name,
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['o3', 'deepseek-flash', 'plain'],
        apiKey: 'key',
      );
      final first = await addReasoning('First');
      final second = await addReasoning('Second');
      await repository.setReasoningEffort(first, 'o3', AiReasoningEffort.high);
      await repository.setReasoningEffort(
        first,
        'deepseek-flash',
        AiReasoningEffort.max,
      );
      expect(repository.effortFor(second, 'o3'), AiReasoningEffort.medium);
      await repository.select(first, 'deepseek-flash');
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.effortFor(first, 'o3'), AiReasoningEffort.high);
      expect(
        restored.effortFor(first, 'deepseek-flash'),
        AiReasoningEffort.max,
      );
      expect(restored.selectedModel, 'deepseek-flash');
      await restored.setReasoningEffort(first, 'o3', null);
      await restored.load();
      expect(restored.effortFor(first, 'o3'), AiReasoningEffort.medium);
      await expectLater(
        restored.setReasoningEffort(first, 'plain', AiReasoningEffort.high),
        throwsA(isA<AiConfigurationException>()),
      );
      await restored.remove(first);
      expect(restored.effortFor(first, 'deepseek-flash'), isNull);
    },
  );

  test(
    'old selected reasoning model receives a persisted concrete level',
    () async {
      final id = await repository.save(
        name: 'Existing',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['o3', 'deepseek-flash', 'plain'],
        apiKey: 'key',
      );
      final catalog =
          jsonDecode(
                preferences.stringValue(ModelServiceRepository.catalogKey, ''),
              )
              as Map<String, dynamic>;
      catalog.remove('reasoningEfforts');
      preferences.setValue(
        ModelServiceRepository.catalogKey,
        jsonEncode(catalog),
      );
      await preferences.flush();
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.selectedModel, 'o3');
      expect(restored.effortFor(id, 'o3'), AiReasoningEffort.medium);
      expect(restored.effortFor(id, 'deepseek-flash'), AiReasoningEffort.high);
      expect(restored.effortFor(id, 'plain'), isNull);
      final saved =
          jsonDecode(
                preferences.stringValue(ModelServiceRepository.catalogKey, ''),
              )
              as Map;
      expect(
        (saved['reasoningEfforts'] as Map)[jsonEncode([id, 'o3'])],
        'medium',
      );
    },
  );

  test('Astra rejects ultra and migrates saved ultra to max', () async {
    final capabilities = AiReasoningCapabilities.forModel('gpt-6-astra');
    expect(capabilities.levels, isNot(contains(AiReasoningEffort.ultra)));
    expect(capabilities.levels.last, AiReasoningEffort.max);
    for (final responses in [false, true]) {
      expect(
        capabilities.requestParameters(
          AiReasoningEffort.max,
          responses: responses,
        ),
        responses
            ? {
                'reasoning': {'effort': 'max'},
              }
            : {'reasoning_effort': 'max'},
      );
    }
    // 其他模型原有的 ultra 档位不受本次修复影响。
    expect(
      AiReasoningCapabilities.forModel('gpt-6-sol').levels,
      contains(AiReasoningEffort.ultra),
    );
    final id = await repository.save(
      name: 'Astra',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['gpt-6-astra'],
      apiKey: 'key',
    );
    final catalog =
        jsonDecode(
              preferences.stringValue(ModelServiceRepository.catalogKey, ''),
            )
            as Map<String, dynamic>;
    final effortKey = jsonEncode([id, 'gpt-6-astra']);
    (catalog['reasoningEfforts'] as Map)[effortKey] = 'ultra';
    preferences.setValue(
      ModelServiceRepository.catalogKey,
      jsonEncode(catalog),
    );
    await preferences.flush();
    final restored = ModelServiceRepository(preferences, keys);
    await restored.load();
    expect(restored.effortFor(id, 'gpt-6-astra'), AiReasoningEffort.max);
    final saved =
        jsonDecode(
              preferences.stringValue(ModelServiceRepository.catalogKey, ''),
            )
            as Map;
    expect((saved['reasoningEfforts'] as Map)[effortKey], 'max');
    await expectLater(
      restored.setReasoningEffort(id, 'gpt-6-astra', AiReasoningEffort.ultra),
      throwsA(isA<AiConfigurationException>()),
    );
  });

  test(
    'decorated model ids retain separate efforts and migrate unsupported ultra',
    () async {
      const sol = 'custom-gpt-6.1-sol-test';
      const astra = 'ai-apizn/gpt-6-astra';
      final id = await repository.save(
        name: 'Gateway',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://example.test/v1',
        models: [sol, astra],
        apiKey: 'key',
      );
      expect(repository.effortFor(id, sol), AiReasoningEffort.medium);
      await repository.setReasoningEffort(id, sol, AiReasoningEffort.ultra);
      final catalog =
          jsonDecode(
                preferences.stringValue(ModelServiceRepository.catalogKey, ''),
              )
              as Map;
      final astraKey = jsonEncode([id, astra]);
      (catalog['reasoningEfforts'] as Map)[astraKey] = 'ultra';
      preferences.setValue(
        ModelServiceRepository.catalogKey,
        jsonEncode(catalog),
      );
      await preferences.flush();
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.services.single.models, [sol, astra]);
      expect(restored.effortFor(id, sol), AiReasoningEffort.ultra);
      expect(restored.effortFor(id, astra), AiReasoningEffort.max);
      final saved =
          jsonDecode(
                preferences.stringValue(ModelServiceRepository.catalogKey, ''),
              )
              as Map;
      expect((saved['reasoningEfforts'] as Map)[astraKey], 'max');
    },
  );

  test('failed reasoning save preserves the previous selection', () async {
    final id = await repository.save(
      name: 'Test',
      protocol: AiApiProtocol.openAiResponses,
      baseUrl: 'https://example.test/v1',
      models: ['o3'],
      apiKey: 'key',
    );
    await repository.setReasoningEffort(id, 'o3', AiReasoningEffort.low);
    storage.fail = true;
    await expectLater(
      repository.setReasoningEffort(id, 'o3', AiReasoningEffort.high),
      throwsA(isA<AiConfigurationException>()),
    );
    expect(repository.effortFor(id, 'o3'), AiReasoningEffort.low);
    storage.fail = false;
    await repository.load();
    expect(repository.effortFor(id, 'o3'), AiReasoningEffort.low);
  });

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
  test(
    'service backup restores secrets, capabilities, selection and effort on another installation',
    () async {
      final first = await repository.save(
        name: 'Backup',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://backup.test/v1',
        models: ['gpt-6.1-sol', 'vision'],
        apiKey: 'backup-secret',
        imageInputs: {'vision': AiImageInput.supported},
      );
      await repository.setReasoningEffort(
        first,
        'gpt-6.1-sol',
        AiReasoningEffort.high,
      );
      await repository.select(first, 'vision');
      final source = repository.exportConfiguration();
      final targetPreferences = await AppPreferences.load(storage: _Storage());
      addTearDown(targetPreferences.dispose);
      final targetKeys = MemoryAiCredentialStore();
      final target = ModelServiceRepository(targetPreferences, targetKeys);
      await target.load();
      await target.importConfiguration(source);
      final restored = ModelServiceRepository(targetPreferences, targetKeys);
      await restored.load();
      expect(restored.selectedId, first);
      expect(restored.selectedModel, 'vision');
      expect(restored.selectedService!.protocol, AiApiProtocol.openAiResponses);
      expect(
        restored.selectedService!.imageInputFor('vision'),
        AiImageInput.supported,
      );
      expect(restored.effortFor(first, 'gpt-6.1-sol'), AiReasoningEffort.high);
      expect(restored.keyFor(first), 'backup-secret');
      expect(targetKeys.values[first], 'backup-secret');
      expect(
        targetPreferences.stringValue(ModelServiceRepository.catalogKey, ''),
        isNot(contains('backup-secret')),
      );
    },
  );

  test(
    'backup merges unrelated services and replaces a matching id without duplicates',
    () async {
      final first = await add('first', 'old-secret');
      final source = repository.exportConfiguration();
      final second = await add('second', 'second-secret');
      final json = jsonDecode(source) as Map<String, dynamic>;
      final entry = (json['services'] as List).single as Map<String, dynamic>;
      entry['name'] = 'Renamed';
      entry['apiKey'] = 'new-secret';
      await repository.importConfiguration(jsonEncode(json));
      expect(repository.services.map((v) => v.id), [first, second]);
      expect(repository.find(first)!.name, 'Renamed');
      expect(repository.keyFor(first), 'new-secret');
      expect(repository.keyFor(second), 'second-secret');
      await repository.importConfiguration(jsonEncode(json));
      expect(repository.services, hasLength(2));
    },
  );

  test(
    'invalid backup is fully validated before touching any stored service or key',
    () async {
      final first = await add('first', 'old-secret');
      final json =
          jsonDecode(repository.exportConfiguration()) as Map<String, dynamic>;
      final entries = json['services'] as List;
      final valid = Map<String, dynamic>.from(entries.single as Map);
      valid['apiKey'] = 'new-secret';
      entries[0] = valid;
      entries.add({...valid, 'id': 'broken', 'protocol': 'unknown'});
      await expectLater(
        repository.importConfiguration(jsonEncode(json)),
        throwsFormatException,
      );
      expect(repository.keyFor(first), 'old-secret');
      expect(keys.values[first], 'old-secret');
      expect(repository.services, hasLength(1));
    },
  );

  test(
    'wrong format, duplicate ids, invalid selection and image metadata are rejected without leaking source',
    () async {
      await add('first', 'do-not-include-in-errors');
      final original = repository.exportConfiguration();
      final invalidSources = <String>[
        '{invalid',
        jsonEncode({'format': 'lilygobox-config', 'schemaVersion': 1}),
      ];
      for (final change in <void Function(Map<String, dynamic>)>[
        (json) => json['schemaVersion'] = 2,
        (json) =>
            (json['services'] as List).add((json['services'] as List).first),
        (json) => json['selectedId'] = 'missing',
        (json) =>
            ((json['services'] as List).first as Map)['discoveredImageInputs'] =
                {'chat': 'bad'},
        (json) => ((json['services'] as List).first as Map)['apiKey'] = '',
      ]) {
        final json = jsonDecode(original) as Map<String, dynamic>;
        change(json);
        invalidSources.add(jsonEncode(json));
      }
      for (final source in invalidSources) {
        await expectLater(
          repository.importConfiguration(source),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'sanitized error',
              isNot(contains('do-not-include-in-errors')),
            ),
          ),
        );
      }
      expect(repository.services, hasLength(1));
    },
  );

  test(
    'failed backup persistence restores all previous keys and repository state',
    () async {
      final first = await add('first', 'old-secret');
      final json =
          jsonDecode(repository.exportConfiguration()) as Map<String, dynamic>;
      final entries = json['services'] as List;
      final firstEntry = entries.single as Map<String, dynamic>;
      firstEntry['apiKey'] = 'new-secret';
      entries.add({
        ...firstEntry,
        'id': 'new-service',
        'apiKey': 'another-secret',
      });
      storage.fail = true;
      await expectLater(
        repository.importConfiguration(jsonEncode(json)),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(repository.keyFor(first), 'old-secret');
      expect(keys.values[first], 'old-secret');
      expect(keys.values.containsKey('new-service'), isFalse);
      expect(repository.services, hasLength(1));
      storage.fail = false;
      await preferences.flush();
      final restored = ModelServiceRepository(preferences, keys);
      await restored.load();
      expect(restored.services, hasLength(1));
      expect(restored.keyFor(first), 'old-secret');
    },
  );

  test(
    'a credential failure rolls back earlier imported keys before catalog mutation',
    () async {
      final failingKeys = _FailingKeys();
      final target = ModelServiceRepository(preferences, failingKeys);
      await target.load();
      final id = await target.save(
        name: 'first',
        protocol: AiApiProtocol.openAiResponses,
        baseUrl: 'https://first.test',
        models: ['chat'],
        apiKey: 'old-secret',
      );
      final json =
          jsonDecode(target.exportConfiguration()) as Map<String, dynamic>;
      final entries = json['services'] as List;
      final first = entries.single as Map<String, dynamic>;
      first['apiKey'] = 'updated-secret';
      entries.add({
        ...first,
        'id': 'new-service',
        'apiKey': 'fail-on-this-secret',
      });
      failingKeys.fail = true;
      await expectLater(
        target.importConfiguration(jsonEncode(json)),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(failingKeys.values[id], 'old-secret');
      expect(failingKeys.values.containsKey('new-service'), isFalse);
      expect(target.services, hasLength(1));
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

class _FailingKeys extends MemoryAiCredentialStore {
  bool fail = false;
  @override
  Future<void> write(String value, {String? serviceId}) async {
    if (fail && value == 'fail-on-this-secret') {
      throw StateError('storage failed');
    }
    await super.write(value, serviceId: serviceId);
  }
}
