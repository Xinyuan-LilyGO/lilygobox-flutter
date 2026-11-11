/*
 * @Description: 定义 AI 服务配置、会话消息与待确认的设置操作。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-11 16:26:54
 */

import 'dart:typed_data';

import 'reasoning.dart';

class AiImageAttachment {
  const AiImageAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

enum AiApiProtocol { openAiChatCompletions, openAiResponses }

/// 未声明不等于不支持；第三方模型不根据名称猜测图片能力。
enum AiImageInput { unknown, supported, unsupported }

class AiModelCatalog {
  AiModelCatalog({
    required List<String> models,
    required Map<String, AiImageInput> imageInputs,
  }) : models = List.unmodifiable(models),
       imageInputs = Map.unmodifiable(imageInputs);
  final List<String> models;
  final Map<String, AiImageInput> imageInputs;
}

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
    this.reasoningEffort,
  });

  final AiApiProtocol protocol;
  final String baseUrl;
  final String model;
  final AiReasoningEffort? reasoningEffort;

  AiServiceConfiguration copyWith({
    AiApiProtocol? protocol,
    String? baseUrl,
    String? model,
    AiReasoningEffort? reasoningEffort,
  }) => AiServiceConfiguration(
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
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
    Map<String, AiImageInput> imageInputs = const {},
  }) : models = List.unmodifiable(models),
       imageInputs = Map.unmodifiable({
         for (final model in models)
           if (imageInputs.containsKey(model)) model: imageInputs[model]!,
       });

  final String id;
  final String name;
  final AiApiProtocol protocol;
  final String baseUrl;
  final List<String> models;
  final AiServicePreset preset;
  final Map<String, AiImageInput> imageInputs;
  AiImageInput imageInputFor(String model) =>
      imageInputs[model] ?? AiImageInput.unknown;

  String get host => Uri.parse(baseUrl).authority;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'models': models,
    'preset': preset.name,
    'discoveredImageInputs': {
      for (final entry in imageInputs.entries) entry.key: entry.value.name,
    },
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
      imageInputs: {
        // 旧 imageInputs 可能来自手动设置，不用作自动能力判断。
        if (json['discoveredImageInputs'] case final Map entries)
          for (final entry in entries.entries)
            if (entry.key is String)
              entry.key as String: AiImageInput.values.firstWhere(
                (value) => value.name == entry.value,
                orElse: () => AiImageInput.unknown,
              ),
      },
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
  imageUnsupported,
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
  awaitingApproval,
  retrying,
  completed,
  failed,
  stopped,
}

class AiRequestRetry {
  const AiRequestRetry(this.attempt, this.error);
  final int attempt;
  final Object error;
}

enum AiProcessEventType {
  status,
  reasoning,
  assistant,
  action,
  retry,
  guidance,
}

class AiProcessEvent {
  const AiProcessEvent({
    required this.type,
    required this.elapsed,
    this.status,
    this.text = '',
    this.action,
    this.retry,
    this.guidance,
  });

  final AiProcessEventType type;
  final Duration elapsed;
  final AiResponseStatus? status;
  final String text;
  final AiProcessingStep? action;
  final AiRequestRetry? retry;
  final AiMessage? guidance;
}

class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.toolName,
    this.toolArguments,
    this.toolDecision,
    this.elapsed,
    this.model,
    this.reasoningEffort,
    this.protocol,
    this.processingSteps = const [],
    this.status,
    this.requestError,
    this.retries = const [],
    this.processEvents = const [],
    this.attachments = const [],
  });

  final String id;
  final String role;
  final String content;
  final DateTime? createdAt;
  final String? toolName;
  final Map<String, Object?>? toolArguments;
  final bool? toolDecision;
  final Duration? elapsed;
  final String? model;
  final AiReasoningEffort? reasoningEffort;
  final AiApiProtocol? protocol;
  final List<AiProcessingStep> processingSteps;
  final AiResponseStatus? status;
  final Object? requestError;
  final List<AiRequestRetry> retries;
  final List<AiProcessEvent> processEvents;
  final List<AiImageAttachment> attachments;

  AiMessage copyWith({
    DateTime? createdAt,
    String? content,
    bool? toolDecision,
    Duration? elapsed,
    String? model,
    AiReasoningEffort? reasoningEffort,
    AiApiProtocol? protocol,
    List<AiProcessingStep>? processingSteps,
    AiResponseStatus? status,
    Object? requestError,
    List<AiRequestRetry>? retries,
    List<AiProcessEvent>? processEvents,
    List<AiImageAttachment>? attachments,
  }) => AiMessage(
    id: id,
    role: role,
    createdAt: createdAt ?? this.createdAt,
    content: content ?? this.content,
    toolName: toolName,
    toolArguments: toolArguments,
    toolDecision: toolDecision ?? this.toolDecision,
    elapsed: elapsed ?? this.elapsed,
    model: model ?? this.model,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    protocol: protocol ?? this.protocol,
    processingSteps: processingSteps ?? this.processingSteps,
    status: status ?? this.status,
    requestError: requestError ?? this.requestError,
    retries: retries ?? this.retries,
    processEvents: processEvents ?? this.processEvents,
    attachments: attachments ?? this.attachments,
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
