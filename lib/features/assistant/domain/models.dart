/*
 * @Description: 定义 AI 服务配置、会话消息与待确认的设置操作。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 11:35:10
 */

enum AiApiProtocol { openAiChatCompletions, openAiResponses }

/// 显式选择官方预设；已有服务不会因域名相同而自动切换类型。
enum AiServicePreset {
  custom,
  deepSeek,
  openAi;

  String? get baseUrl => switch (this) {
    custom => null,
    deepSeek => 'https://api.deepseek.com',
    openAi => 'https://api.openai.com/v1',
  };

  AiApiProtocol? get protocol => switch (this) {
    custom => null,
    deepSeek => AiApiProtocol.openAiChatCompletions,
    openAi => AiApiProtocol.openAiResponses,
  };
}

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
    this.preset = AiServicePreset.custom,
  }) : models = List.unmodifiable(models);

  final String id;
  final String name;
  final AiApiProtocol protocol;
  final String baseUrl;
  final List<String> models;
  final AiServicePreset preset;

  String get host => Uri.parse(baseUrl).authority;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'models': models,
    'preset': preset.name,
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
      preset: AiServicePreset.values.firstWhere(
        (preset) => preset.name == json['preset'],
        orElse: () => AiServicePreset.custom,
      ),
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

enum AiResponseStatus {
  connecting,
  awaitingReply,
  thinking,
  streaming,
  preparingTools,
  executingTools,
  retrying,
  paused,
  completed,
  failed,
  stopped,
}

class AiRequestRetry {
  const AiRequestRetry(this.attempt, this.error);
  final int attempt;
  final Object error;
}

enum AiProcessEventType { status, reasoning, assistant, action, retry }

class AiProcessEvent {
  const AiProcessEvent({
    required this.type,
    required this.elapsed,
    this.status,
    this.text = '',
    this.action,
    this.retry,
  });

  final AiProcessEventType type;
  final Duration elapsed;
  final AiResponseStatus? status;
  final String text;
  final AiProcessingStep? action;
  final AiRequestRetry? retry;
}

class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolName,
    this.toolArguments,
    this.toolDecision,
    this.elapsed,
    this.model,
    this.protocol,
    this.processingSteps = const [],
    this.status,
    this.requestError,
    this.retries = const [],
    this.processEvents = const [],
  });

  final String id;
  final String role;
  final String content;
  final String? toolName;
  final Map<String, Object?>? toolArguments;
  final bool? toolDecision;
  final Duration? elapsed;
  final String? model;
  final AiApiProtocol? protocol;
  final List<AiProcessingStep> processingSteps;
  final AiResponseStatus? status;
  final Object? requestError;
  final List<AiRequestRetry> retries;
  final List<AiProcessEvent> processEvents;

  AiMessage copyWith({
    String? content,
    bool? toolDecision,
    Duration? elapsed,
    String? model,
    AiApiProtocol? protocol,
    List<AiProcessingStep>? processingSteps,
    AiResponseStatus? status,
    Object? requestError,
    List<AiRequestRetry>? retries,
    List<AiProcessEvent>? processEvents,
  }) => AiMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    toolName: toolName,
    toolArguments: toolArguments,
    toolDecision: toolDecision ?? this.toolDecision,
    elapsed: elapsed ?? this.elapsed,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
    processingSteps: processingSteps ?? this.processingSteps,
    status: status ?? this.status,
    requestError: requestError ?? this.requestError,
    retries: retries ?? this.retries,
    processEvents: processEvents ?? this.processEvents,
  );
}

class AiProcessingStep {
  AiProcessingStep({
    required this.name,
    required Map<String, Object?> arguments,
    required this.succeeded,
  }) : arguments = Map.unmodifiable(arguments);

  final String name;
  final Map<String, Object?> arguments;
  final bool succeeded;
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
    this.reasoning = '',
  });

  final String text;
  final List<AiToolCall> toolCalls;
  final List<Map<String, Object?>> responseItems;
  final String reasoning;
}
