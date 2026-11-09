/*
 * @Description: 持久化已添加的模型服务、独立密钥与模型选择，并迁移已有的显式配置。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-09 09:45:46
 */

import 'dart:convert';

import '../../../core/storage/preferences.dart';
import '../domain/models.dart';
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
  int _sequence = 0;

  List<AiModelService> get services => List.unmodifiable(_services);
  String? get selectedId => _selectedId;
  String? get selectedModel => _model;
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
    String? model,
  ) async {
    final previous = _preferences.stringValue(catalogKey, '');
    _preferences.setValue(
      catalogKey,
      jsonEncode({
        'services': services.map((item) => item.toJson()).toList(),
        'selectedId': id,
        'model': model,
      }),
    );
    if (!await _preferences.flush()) {
      _preferences.setValue(catalogKey, previous);
      throw const AiConfigurationException(AiProblem.storage);
    }
    _services = services;
    _selectedId = id;
    _model = model;
  }
}
