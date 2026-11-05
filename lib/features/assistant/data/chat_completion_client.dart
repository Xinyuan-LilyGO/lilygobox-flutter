/*
 * @Description: 调用 OpenAI 兼容 Chat Completions 并解析设置工具调用。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 14:52:13
 * @License: GPL 3.0
 */

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class AiRequestException implements Exception {
  const AiRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ChatCompletionClient {
  ChatCompletionClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<AiCompletion> complete({
    required AiServiceConfiguration configuration,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    int maxTokens = 2048,
  }) async {
    final base = configuration.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final responses = configuration.protocol == AiApiProtocol.openAiResponses;
    final uri = Uri.parse(
      '$base/${responses ? 'responses' : 'chat/completions'}',
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': configuration.model,
            if (responses)
              ..._responsesRequest(messages, tools, maxTokens)
            else ...{
              'messages': messages,
              if (tools.isNotEmpty) 'tools': tools,
              if (tools.isNotEmpty) 'tool_choice': 'auto',
              'max_tokens': maxTokens,
            },
          }),
        )
        .timeout(const Duration(seconds: 90));

    final decoded = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final detail = error is Map ? error['message']?.toString() : null;
      throw AiRequestException(
        detail?.isNotEmpty == true ? detail! : 'HTTP ${response.statusCode}',
      );
    }

    if (responses) return _parseResponses(decoded);

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    final content = message['content'];
    final calls = <AiToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls.whereType<Map>()) {
        final function = raw['function'];
        if (function is! Map) continue;
        final name = function['name'];
        final rawArguments = function['arguments'];
        if (name is! String || rawArguments is! String) continue;
        try {
          final arguments = jsonDecode(rawArguments);
          if (arguments is Map<String, dynamic>) {
            calls.add(
              AiToolCall(
                id: raw['id']?.toString() ?? '',
                name: name,
                arguments: Map<String, Object?>.from(arguments),
              ),
            );
          }
        } on FormatException {
          continue;
        }
      }
    }
    return AiCompletion(
      text: content is String ? content.trim() : '',
      toolCalls: calls,
    );
  }

  /// 只读取显式配置的服务地址，不根据模型列表猜测协议。
  Future<List<String>> listModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .get(
          Uri.parse('$base/models'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      throw AiRequestException(
        error is Map && error['message'] is String
            ? error['message'] as String
            : 'HTTP ${response.statusCode}',
      );
    }
    final data = decoded['data'];
    if (data is! List) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    return data
        .whereType<Map>()
        .map((item) => item['id'])
        .whereType<String>()
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> close() async => _client.close();

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Replaced with a localized UI error by the caller.
    }
    throw const AiConfigurationException(AiProblem.invalidResponse);
  }

  Map<String, Object?> _responsesRequest(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
    int maxTokens,
  ) {
    final instructions = <String>[];
    final input = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = message['role'];
      final content = message['content'];
      if (role == 'system') {
        if (content is String && content.isNotEmpty) instructions.add(content);
        continue;
      }
      final responseItems = message['response_items'];
      if (role == 'assistant' &&
          responseItems is List &&
          responseItems.isNotEmpty) {
        input.addAll(responseItems.cast<Map<String, Object?>>());
        continue;
      }
      if (role == 'tool') {
        input.add({
          'type': 'function_call_output',
          'call_id': message['tool_call_id'],
          'output': content?.toString() ?? '',
        });
        continue;
      }
      final rawCalls = message['tool_calls'];
      if (role == 'assistant' && rawCalls is List) {
        if (content is String && content.isNotEmpty) {
          input.add({'role': 'assistant', 'content': content});
        }
        for (final call in rawCalls.whereType<Map>()) {
          final function = call['function'];
          if (function is! Map) continue;
          input.add({
            'type': 'function_call',
            'call_id': call['id'],
            'name': function['name'],
            'arguments': function['arguments']?.toString() ?? '{}',
          });
        }
        continue;
      }
      if (role is String && content != null) {
        input.add({'role': role, 'content': content});
      }
    }
    return {
      if (instructions.isNotEmpty) 'instructions': instructions.join('\n\n'),
      'input': input,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            if (tool['function'] case final function? when function is Map)
              {
                'type': 'function',
                'name': function['name'],
                'description': function['description'],
                'parameters': function['parameters'],
                'strict': false,
              },
        ],
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      'max_output_tokens': maxTokens,
      'store': false,
      'include': ['reasoning.encrypted_content'],
    };
  }

  AiCompletion _parseResponses(Map<String, dynamic> decoded) {
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    final output = decoded['output'];
    if (output is! List) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    for (final item in output.whereType<Map>()) {
      if (item['type'] == 'function_call') {
        final name = item['name'];
        final rawArguments = item['arguments'];
        if (name is! String || rawArguments == null) continue;
        try {
          final arguments = rawArguments is String
              ? jsonDecode(rawArguments)
              : rawArguments;
          if (arguments is Map<String, dynamic>) {
            calls.add(
              AiToolCall(
                id: item['call_id']?.toString() ?? item['id']?.toString() ?? '',
                name: name,
                arguments: Map<String, Object?>.from(arguments),
              ),
            );
          }
        } on FormatException {
          continue;
        }
        continue;
      }
      if (item['type'] != 'message' || item['content'] is! List) continue;
      for (final content in (item['content'] as List).whereType<Map>()) {
        if (content['type'] == 'output_text' && content['text'] is String) {
          text.write(content['text']);
        }
      }
    }
    return AiCompletion(
      text: text.toString().trim(),
      toolCalls: calls,
      responseItems: [
        for (final item in output.whereType<Map>())
          Map<String, Object?>.from(item),
      ],
    );
  }
}
