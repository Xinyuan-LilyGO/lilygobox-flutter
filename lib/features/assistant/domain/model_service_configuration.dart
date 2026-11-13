/*
 * @Description: 校验独立模型服务备份格式，包含密钥、模型能力及选择配置。
 * @Author: Codex
 * @Date: 2026-11-13 19:20:26
 * @LastEditTime: 2026-11-13 19:20:26
 */
import 'dart:convert';

import 'models.dart';
import 'reasoning.dart';

class ModelServiceConfiguration {
  const ModelServiceConfiguration({
    required this.services,
    required this.apiKeys,
    required this.selectedId,
    required this.model,
    required this.reasoningEfforts,
  });

  static const formatName = 'lilygobox-model-services';
  static const schemaVersion = 1;
  static const maximumFileBytes = 2 * 1024 * 1024;
  final List<AiModelService> services;
  final Map<String, String> apiKeys;
  final String? selectedId;
  final String? model;
  final Map<String, String> reasoningEfforts;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': formatName,
    'schemaVersion': schemaVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'services': [
      for (final service in services)
        {...service.toJson(), 'apiKey': apiKeys[service.id]},
    ],
    'selectedId': selectedId,
    'model': model,
    'reasoningEfforts': reasoningEfforts,
  });

  static ModelServiceConfiguration decode(String source) {
    // 不在异常中附带来源内容，避免把密钥带入日志或错误界面。
    try {
      if (utf8.encode(source).length > maximumFileBytes) {
        throw const FormatException();
      }
      return _decode(jsonDecode(source));
    } catch (_) {
      throw const FormatException('Invalid model service configuration.');
    }
  }

  static ModelServiceConfiguration _decode(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['format'] != formatName ||
        json['schemaVersion'] != schemaVersion ||
        json['schemaVersion'] is! int ||
        json['services'] is! List ||
        (json['services'] as List).length > 500) {
      throw const FormatException();
    }
    final services = <AiModelService>[];
    final keys = <String, String>{};
    for (final entry in json['services'] as List) {
      if (entry is! Map<String, dynamic>) throw const FormatException();
      final id = _text(entry['id']);
      final name = _text(entry['name']);
      final address = _text(entry['baseUrl']);
      final uri = Uri.tryParse(address);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          keys.containsKey(id) ||
          !AiApiProtocol.values.any((v) => v.name == entry['protocol']) ||
          !AiServicePreset.values.any((v) => v.name == entry['preset'])) {
        throw const FormatException();
      }
      final rawModels = entry['models'];
      if (rawModels is! List || rawModels.isEmpty || rawModels.length > 10000) {
        throw const FormatException();
      }
      final models = rawModels.map(_text).toList();
      if (models.toSet().length != models.length) throw const FormatException();
      final images = entry['discoveredImageInputs'];
      if (images is! Map<String, dynamic>) throw const FormatException();
      for (final item in images.entries) {
        if (!models.contains(item.key) ||
            !AiImageInput.values.any((v) => v.name == item.value)) {
          throw const FormatException();
        }
      }
      keys[id] = _text(entry['apiKey']);
      services.add(
        AiModelService.fromJson({
          ...entry,
          'id': id,
          'name': name,
          'baseUrl': address.replaceFirst(RegExp(r'/+$'), ''),
          'models': models,
        }),
      );
    }
    final selectedId = json['selectedId'];
    final model = json['model'];
    if (services.isEmpty) {
      if (selectedId != null || model != null) throw const FormatException();
    } else {
      final selected = services.where((v) => v.id == selectedId).firstOrNull;
      if (selected == null || !selected.models.contains(model)) {
        throw const FormatException();
      }
    }
    final efforts = json['reasoningEfforts'];
    if (efforts is! Map<String, dynamic>) throw const FormatException();
    for (final entry in efforts.entries) {
      final pair = jsonDecode(entry.key);
      if (pair is! List || pair.length != 2) throw const FormatException();
      final service = services.where((v) => v.id == pair[0]).firstOrNull;
      if (service == null ||
          !service.models.contains(pair[1]) ||
          !AiReasoningEffort.values.any((v) => v.name == entry.value) ||
          AiReasoningCapabilities.forModel(pair[1] as String).levels.isEmpty) {
        throw const FormatException();
      }
    }
    return ModelServiceConfiguration(
      services: List.unmodifiable(services),
      apiKeys: Map.unmodifiable(keys),
      selectedId: selectedId as String?,
      model: model as String?,
      reasoningEfforts: Map.unmodifiable(efforts.cast<String, String>()),
    );
  }

  static String _text(dynamic value) {
    if (value is! String ||
        value.isEmpty ||
        value.trim() != value ||
        value.length > 65536) {
      throw const FormatException();
    }
    return value;
  }
}
