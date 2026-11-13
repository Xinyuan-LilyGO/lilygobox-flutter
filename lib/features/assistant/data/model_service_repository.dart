/*
 * @Description: 持久化已添加的模型服务、独立密钥与模型选择，并迁移已有的显式配置。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-13 19:20:26
 */

import 'dart:convert';

import '../../../core/storage/preferences.dart';
import '../domain/model_service_configuration.dart';
import '../domain/models.dart';
import '../domain/reasoning.dart';
import 'credential_store.dart';

class ModelServiceRepository {
  ModelServiceRepository(this._preferences, this._credentials);
  static const catalogKey = 'ai.services.v2';
  final AppPreferences _preferences;
  final AiCredentialStore _credentials;
  List<AiModelService> _services = [];
  final Map<String, String> _keys = {};
  String? _selectedId;
  String? _model;
  Map<String, String> _reasoningEfforts = {};
  int _sequence = 0;

  List<AiModelService> get services => List.unmodifiable(_services);
  String? get selectedId => _selectedId;
  String? get selectedModel => _model;
  AiReasoningEffort? effortFor(String id, String model) {
    if (find(id)?.models.contains(model) != true) return null;
    final saved = _reasoningEfforts[jsonEncode([id, model])];
    final capabilities = AiReasoningCapabilities.forModel(model);
    return capabilities.levels
            .where((effort) => effort.name == saved)
            .firstOrNull ??
        capabilities.initialEffort;
  }

  Future<void> setReasoningEffort(
    String id,
    String model,
    AiReasoningEffort? effort,
  ) async {
    final service = find(id);
    if (service == null ||
        !service.models.contains(model) ||
        (effort != null &&
            !AiReasoningCapabilities.forModel(model).levels.contains(effort))) {
      throw const AiConfigurationException(AiProblem.noService);
    }
    final next = {..._reasoningEfforts};
    final key = jsonEncode([id, model]);
    if (effort == null) {
      next.remove(key);
    } else {
      next[key] = effort.name;
    }
    await _persist(_services, _selectedId, _model, reasoningEfforts: next);
  }

  AiModelService? get selectedService => find(_selectedId);
  String? keyFor(String? id) => _keys[id];
  AiModelService? find(String? id) {
    for (final service in _services) {
      if (service.id == id) return service;
    }
    return null;
  }

  static String validateAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AiConfigurationException(AiProblem.invalidAddress);
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> load() async {
    if (_preferences.error == PreferencesError.read) {
      throw const AiConfigurationException(AiProblem.storage);
    }
    final raw = _preferences.stringValue(catalogKey, '');
    if (raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _services = (json['services'] as List)
            .map(
              (value) => AiModelService.fromJson(value as Map<String, dynamic>),
            )
            .toList();
        for (final service in _services) {
          validateAddress(service.baseUrl);
          if (service.id.isEmpty || service.models.isEmpty) {
            throw const FormatException();
          }
          final key = await _credentials.read(serviceId: service.id);
          if (key != null) _keys[service.id] = key;
        }
        final selected = find(json['selectedId'] as String?);
        _selectedId =
            selected?.id ?? (_services.isEmpty ? null : _services.first.id);
        final models = selectedService?.models ?? const <String>[];
        _model = models.contains(json['model'])
            ? json['model'] as String
            : models.firstOrNull;
        final efforts = json['reasoningEfforts'];
        _reasoningEfforts = {
          if (efforts is Map)
            for (final entry in efforts.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
        };
        // 根据统一能力规则修复旧 ultra 档位，带前后缀的名称同样生效。
        var migratedEffort = false;
        for (final service in _services) {
          for (final model in service.models) {
            final key = jsonEncode([service.id, model]);
            final levels = AiReasoningCapabilities.forModel(model).levels;
            if (levels.contains(AiReasoningEffort.max) &&
                !levels.contains(AiReasoningEffort.ultra) &&
                _reasoningEfforts[key] == AiReasoningEffort.ultra.name) {
              _reasoningEfforts[key] = AiReasoningEffort.max.name;
              migratedEffort = true;
            }
          }
        }
        if (migratedEffort ||
            (_selectedId != null &&
                _model != null &&
                AiReasoningCapabilities.forModel(_model!).levels.isNotEmpty &&
                !_reasoningEfforts.containsKey(
                  jsonEncode([_selectedId, _model]),
                ))) {
          await _persist(_services, _selectedId, _model);
        }
      } catch (_) {
        _services = [];
        _keys.clear();
        throw const AiConfigurationException(AiProblem.storage);
      }
      return;
    }
    // 仅迁移确实保存过的地址、模型和密钥；默认值不创建服务。
    final address = _preferences.stringValue('ai.baseUrl', '');
    final model = _preferences.stringValue('ai.model', '');
    if (address.isEmpty || model.isEmpty) return;
    final key = await _credentials.read();
    if (key == null || key.isEmpty) return;
    final protocol = AiApiProtocol.openAiChatCompletions;
    await save(
      name: _preferences.stringValue('ai.provider', '') != 'openAiCompatible'
          ? 'DeepSeek'
          : Uri.parse(address).host,
      protocol: protocol,
      baseUrl: address,
      models: [model],
      apiKey: key,
    );
    await _credentials.clear();
  }

  Future<String> save({
    String? id,
    required String name,
    required AiApiProtocol protocol,
    required String baseUrl,
    required List<String> models,
    String? apiKey,
    AiServicePreset preset = AiServicePreset.custom,
    Map<String, AiImageInput>? imageInputs,
  }) async {
    final address = validateAddress(preset.baseUrl ?? baseUrl);
    final cleanModels = models
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList();
    if (name.trim().isEmpty) {
      throw const AiConfigurationException(AiProblem.nameRequired);
    }
    if (cleanModels.isEmpty) {
      throw const AiConfigurationException(AiProblem.modelsRequired);
    }
    final old = find(id);
    if (id != null && old == null) {
      throw const AiConfigurationException(AiProblem.noService);
    }
    final newKey = apiKey?.trim();
    final oldKey = _keys[id];
    if (newKey?.isNotEmpty != true &&
        (oldKey?.isNotEmpty != true ||
            old!.preset != preset ||
            Uri.parse(old.baseUrl).origin != Uri.parse(address).origin)) {
      throw const AiConfigurationException(AiProblem.keyRequired);
    }
    final serviceId =
        id ?? 'service-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final service = AiModelService(
      id: serviceId,
      name: name.trim(),
      protocol: preset.protocol ?? protocol,
      baseUrl: address,
      models: cleanModels,
      preset: preset,
      imageInputs:
          imageInputs ??
          (old != null &&
                  old.baseUrl == address &&
                  old.protocol == (preset.protocol ?? protocol)
              ? old.imageInputs
              : const {}),
    );
    final next = [
      for (final item in _services)
        if (item.id == serviceId) service else item,
      if (old == null) service,
    ];
    final nextId = _selectedId ?? serviceId;
    final nextModel = nextId == serviceId && !cleanModels.contains(_model)
        ? cleanModels.first
        : _model;
    try {
      if (newKey?.isNotEmpty == true) {
        await _credentials.write(newKey!, serviceId: serviceId);
      }
      await _persist(next, nextId, nextModel ?? cleanModels.first);
      _keys[serviceId] = newKey?.isNotEmpty == true ? newKey! : oldKey!;
      return serviceId;
    } catch (_) {
      if (oldKey != null) {
        await _credentials.write(oldKey, serviceId: serviceId);
      } else {
        await _credentials.clear(serviceId: serviceId);
      }
      throw const AiConfigurationException(AiProblem.storage);
    }
  }

  /// 导出内容包含明文密钥，仅供用户显式触发的配置迁移使用。
  String exportConfiguration() {
    for (final service in _services) {
      if (_keys[service.id]?.isNotEmpty != true) {
        throw const AiConfigurationException(AiProblem.keyRequired);
      }
    }
    final source = ModelServiceConfiguration(
      services: _services,
      apiKeys: _keys,
      selectedId: _selectedId,
      model: _model,
      reasoningEfforts: _reasoningEfforts,
    ).encode();
    // 确保每个导出文件都符合导入限制。
    ModelServiceConfiguration.decode(source);
    return source;
  }

  Future<void> importConfiguration(String source) async {
    final configuration = ModelServiceConfiguration.decode(source);
    if (configuration.services.isEmpty) return;
    final imported = {for (final item in configuration.services) item.id: item};
    final next = [
      for (final item in _services) imported[item.id] ?? item,
      for (final item in configuration.services)
        if (find(item.id) == null) item,
    ];
    final previousKeys = <String, String?>{};
    try {
      for (final service in configuration.services) {
        // 读取安全存储的实际值，确保回滚不仅依赖内存缓存。
        previousKeys[service.id] = await _credentials.read(
          serviceId: service.id,
        );
      }
      for (final service in configuration.services) {
        await _credentials.write(
          configuration.apiKeys[service.id]!,
          serviceId: service.id,
        );
      }
      await _persist(
        next,
        configuration.selectedId,
        configuration.model,
        reasoningEfforts: {
          ..._reasoningEfforts,
          ...configuration.reasoningEfforts,
        },
      );
      _keys.addAll(configuration.apiKeys);
    } catch (_) {
      // 尽量恢复全部密钥；单个恢复失败不应跳过其余服务。
      for (final entry in previousKeys.entries) {
        try {
          if (entry.value case final key?) {
            await _credentials.write(key, serviceId: entry.key);
          } else {
            await _credentials.clear(serviceId: entry.key);
          }
        } catch (_) {
          // 仍统一返回存储失败，不记录密钥或带来源内容的异常。
        }
      }
      throw const AiConfigurationException(AiProblem.storage);
    }
  }

  Future<void> select(String id, String model) async {
    final service = find(id);
    if (service == null || !service.models.contains(model)) {
      throw const AiConfigurationException(AiProblem.noService);
    }
    await _persist(_services, id, model);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _services.length ||
        newIndex < 0 ||
        newIndex >= _services.length ||
        oldIndex == newIndex) {
      return;
    }
    final next = [..._services];
    final service = next.removeAt(oldIndex);
    next.insert(newIndex, service);
    await _persist(next, _selectedId, _model);
  }

  Future<void> remove(String id) async {
    if (find(id) == null) return;
    final next = _services.where((item) => item.id != id).toList();
    final nextId = _selectedId == id ? next.firstOrNull?.id : _selectedId;
    final nextModel = _selectedId == id
        ? next.firstOrNull?.models.first
        : _model;
    final oldKey = _keys[id];
    try {
      await _credentials.clear(serviceId: id);
      await _persist(next, nextId, nextModel);
      _keys.remove(id);
    } catch (_) {
      if (oldKey != null) await _credentials.write(oldKey, serviceId: id);
      throw const AiConfigurationException(AiProblem.storage);
    }
  }

  Future<void> _persist(
    List<AiModelService> services,
    String? id,
    String? model, {
    Map<String, String>? reasoningEfforts,
  }) async {
    final sourceEfforts = reasoningEfforts ?? _reasoningEfforts;
    final nextEfforts = <String, String>{
      for (final service in services)
        for (final model in service.models)
          if (AiReasoningCapabilities.forModel(model).levels.isNotEmpty)
            jsonEncode([service.id, model]):
                AiReasoningCapabilities.forModel(model).levels
                    .where(
                      (effort) =>
                          effort.name ==
                          sourceEfforts[jsonEncode([service.id, model])],
                    )
                    .firstOrNull
                    ?.name ??
                AiReasoningCapabilities.forModel(model).initialEffort!.name,
    };
    final previous = _preferences.stringValue(catalogKey, '');
    _preferences.setValue(
      catalogKey,
      jsonEncode({
        'services': services.map((item) => item.toJson()).toList(),
        'selectedId': id,
        'model': model,
        'reasoningEfforts': nextEfforts,
      }),
    );
    if (!await _preferences.flush()) {
      _preferences.setValue(catalogKey, previous);
      throw const AiConfigurationException(AiProblem.storage);
    }
    _services = services;
    _selectedId = id;
    _model = model;
    _reasoningEfforts = nextEfforts;
  }
}
