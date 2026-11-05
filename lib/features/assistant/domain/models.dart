/*
 * @Description: 定义 AI 服务配置、会话消息与待确认的设置操作。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 14:52:13
 * @License: GPL 3.0
 */

enum AiApiProtocol { openAiChatCompletions, openAiResponses }

class AiServiceConfiguration {
  const AiServiceConfiguration({
    this.protocol = AiApiProtocol.openAiChatCompletions,
    this.baseUrl = '',
    this.model = '',
  });

  final AiApiProtocol protocol;
  final String baseUrl;
  final String model;

  AiServiceConfiguration copyWith({
    AiApiProtocol? protocol,
    String? baseUrl,
    String? model,
  }) => AiServiceConfiguration(
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
  );
}

/// 已确认保存的模型服务，模型标识由服务端发现或用户手动填写。
class AiModelService {
  AiModelService({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required List<String> models,
  }) : models = List.unmodifiable(models);

  final String id;
  final String name;
  final AiApiProtocol protocol;
  final String baseUrl;
  final List<String> models;

  String get host => Uri.parse(baseUrl).authority;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'models': models,
  };

  factory AiModelService.fromJson(Map<String, dynamic> json) {
    final protocolName = json['protocol'] as String?;
    final legacyProvider = json['provider'] as String?;
    final protocol = switch (protocolName ?? legacyProvider) {
      'openAiResponses' => AiApiProtocol.openAiResponses,
      'openAiChatCompletions' ||
      'deepSeek' ||
      'openAiCompatible' => AiApiProtocol.openAiChatCompletions,
      _ => throw const FormatException('Unknown AI API protocol.'),
    };
    return AiModelService(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: protocol,
      baseUrl: json['baseUrl'] as String,
      models: (json['models'] as List).cast<String>(),
    );
  }
}

enum AiProblem {
  invalidAddress,
  nameRequired,
  modelsRequired,
  keyRequired,
  storage,
  noService,
  busy,
  invalidResponse,
  request,
  timeout,
}

class AiConfigurationException implements Exception {
  const AiConfigurationException(this.problem);
  final AiProblem problem;
}

class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolName,
    this.toolArguments,
    this.toolDecision,
  });

  final String id;
  final String role;
  final String content;
  final String? toolName;
  final Map<String, Object?>? toolArguments;
  final bool? toolDecision;

  AiMessage copyWith({bool? toolDecision}) => AiMessage(
    id: id,
    role: role,
    content: content,
    toolName: toolName,
    toolArguments: toolArguments,
    toolDecision: toolDecision ?? this.toolDecision,
  );
}

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

class AiCompletion {
  const AiCompletion({
    required this.text,
    required this.toolCalls,
    this.responseItems = const [],
  });

  final String text;
  final List<AiToolCall> toolCalls;
  final List<Map<String, Object?>> responseItems;
}
