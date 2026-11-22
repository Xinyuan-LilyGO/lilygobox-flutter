/*
 * @Description: 调用 OpenAI 兼容 Chat Completions 并解析设置工具调用。
 */

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/reasoning.dart';
import 'reasoning_text_filter.dart';

class AiRequestException implements Exception {
  const AiRequestException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.code,
  });
  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  final String? code;

  @override
  String toString() => message;
}

class AiIncompleteResponseException extends AiRequestException {
  const AiIncompleteResponseException({this.finishReason, this.usage})
    : super(finishReason ?? 'Incomplete response', code: finishReason);

  final String? finishReason;
  final AiTokenUsage? usage;
}

class ChatCompletionClient {
  ChatCompletionClient({
    http.Client? client,
    this.retryDelay = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _withoutStreamUsage = {},
       _ownsTransport = true;

  ChatCompletionClient._fork(ChatCompletionClient parent)
    : _client = parent._client,
      _withoutStreamUsage = parent._withoutStreamUsage,
      retryDelay = parent.retryDelay,
      _ownsTransport = false;

  /// 每个对话拥有独立的流和取消状态，仅复用 HTTP 传输连接池。
  ChatCompletionClient fork() => ChatCompletionClient._fork(this);

  final bool _ownsTransport;
  final http.Client _client;
  final Set<({String baseUrl, String model})> _withoutStreamUsage;
  final Duration retryDelay;
  static const maxRetries = 2;
  StreamSubscription<String>? _responseSubscription;
  Timer? _responseTimeout;
  void Function(Object, StackTrace)? _failResponse;

  void _armResponseTimeout() {
    _responseTimeout?.cancel();
    if (_failResponse == null) return;
    _responseTimeout = Timer(const Duration(seconds: 90), () {
      _failResponse?.call(
        TimeoutException('No response received for 90 seconds.'),
        StackTrace.current,
      );
    });
  }

  Future<AiCompletion> complete({
    required AiServiceConfiguration configuration,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    Future<void>? abortTrigger,
    void Function(String)? onTextDelta,
    void Function(String)? onReasoningDelta,
    void Function(AiResponseStatus)? onStatus,
    void Function(int, Object)? onRetry,
    int? maxTokens,
  }) async {
    var cancelled = false;
    var finished = false;
    unawaited(
      abortTrigger?.then<void>(
        (_) {
          if (!finished) cancelled = true;
        },
        onError: (Object _, StackTrace _) {
          if (!finished) cancelled = true;
        },
      ),
    );
    final uri = Uri.parse(configuration.baseUrl);
    try {
      for (var attempt = 0; ; attempt++) {
        if (cancelled) throw http.RequestAbortedException(uri);
        var outputStarted = false;
        onStatus?.call(
          attempt == 0
              ? AiResponseStatus.connecting
              : AiResponseStatus.retrying,
        );
        void emitReasoning(String text) {
          if (text.isEmpty) return;
          onStatus?.call(AiResponseStatus.thinking);
          onReasoningDelta?.call(text);
        }

        final filter = ReasoningTextFilter(
          onText: (text) {
            if (text.isEmpty) return;
            onStatus?.call(AiResponseStatus.streaming);
            onTextDelta?.call(text);
          },
          onReasoning: emitReasoning,
        );
        try {
          final completion = await _completeOnce(
            configuration: configuration,
            apiKey: apiKey,
            messages: messages,
            tools: tools,
            abortTrigger: abortTrigger,
            maxTokens: maxTokens,
            onReasoningDelta: emitReasoning,
            onStatus: (status) {
              if (status == AiResponseStatus.preparingTools) {
                outputStarted = true;
              }
              onStatus?.call(status);
            },
            onTextDelta: (text) {
              if (text.isNotEmpty) outputStarted = true;
              filter.add(text);
            },
          );
          filter.finish();
          // Normalize the final value too: the provider replaces streamed UI
          // content with this completion and uses it for subsequent history.
          final text = StringBuffer();
          final inlineReasoning = StringBuffer();
          ReasoningTextFilter(
              onText: text.write,
              onReasoning: inlineReasoning.write,
            )
            ..add(completion.text)
            ..finish();
          return AiCompletion(
            text: text.toString(),
            reasoning: completion.reasoning + inlineReasoning.toString(),
            toolCalls: completion.toolCalls,
            // Keep original protocol items, including encrypted reasoning, for
            // Responses API continuation; they are never displayed as text.
            responseItems: completion.responseItems,
            usage: completion.usage,
            streamedOutputDuration: completion.streamedOutputDuration,
            streamedOutputChunks: completion.streamedOutputChunks,
            finishReason: completion.finishReason,
          );
        } on _StreamUsageUnsupported catch (error) {
          _withoutStreamUsage.add(error.endpoint);
        } catch (error) {
          // 已输出正文或工具调用后不重发，避免重复回复或重复执行设置。
          final retryable = switch (error) {
            http.RequestAbortedException() => false,
            TimeoutException() || http.ClientException() => true,
            AiRequestException(:final statusCode) =>
              statusCode == 408 ||
                  statusCode == 429 ||
                  (statusCode != null &&
                      statusCode >= 500 &&
                      statusCode <= 599),
            _ => false,
          };
          if (cancelled ||
              outputStarted ||
              !retryable ||
              attempt >= maxRetries) {
            rethrow;
          }
          onRetry?.call(attempt + 1, error);
          onStatus?.call(AiResponseStatus.retrying);
          final delay = error is AiRequestException && error.retryAfter != null
              ? error.retryAfter!
              : retryDelay * (1 << attempt);
          final waiting = Completer<void>();
          final timer = Timer(delay, () => waiting.complete());
          try {
            await Future.any<void>([waiting.future, ?abortTrigger]);
          } finally {
            timer.cancel();
          }
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<AiCompletion> _completeOnce({
    required AiServiceConfiguration configuration,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    Future<void>? abortTrigger,
    void Function(String)? onTextDelta,
    void Function(String)? onReasoningDelta,
    void Function(AiResponseStatus)? onStatus,
    int? maxTokens,
  }) async {
    final base = configuration.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final responses = configuration.protocol == AiApiProtocol.openAiResponses;
    final endpoint = (baseUrl: base, model: configuration.model);
    final includeUsage = !responses && !_withoutStreamUsage.contains(endpoint);
    final uri = Uri.parse(
      '$base/${responses ? 'responses' : 'chat/completions'}',
    );
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'text/event-stream, application/json',
          })
          ..body = jsonEncode({
            'model': configuration.model,
            'stream': true,
            ...processingSpeedParameters(
              configuration.model,
              configuration.processingSpeed,
              responses: responses,
              serviceTiers: configuration.serviceTiers,
            ),
            ...AiReasoningCapabilities.forModel(configuration.model)
                .requestParameters(
                  configuration.reasoningEffort,
                  responses: responses,
                ),
            if (responses)
              ..._responsesRequest(messages, tools, maxTokens)
            else ...{
              'messages': messages,
              if (includeUsage) 'stream_options': {'include_usage': true},
              if (tools.isNotEmpty) 'tools': tools,
              if (tools.isNotEmpty) 'tool_choice': 'auto',
              'max_tokens': ?maxTokens,
            },
          });
    final response = await _sendCancellable(request, abortTrigger);
    final successful = response.statusCode >= 200 && response.statusCode < 300;
    if (successful) onStatus?.call(AiResponseStatus.thinking);
    final raw = StringBuffer();
    final dataLines = <String>[];
    final toolDeltas = <int, Map<String, Object?>>{};
    var eventName = '';
    final streamedText = StringBuffer();
    final streamedReasoning = StringBuffer();
    AiCompletion? responseCompletion;
    AiTokenUsage? streamedUsage;
    String? finishReason;
    final streamClock = Stopwatch()..start();
    var receivedAt = Duration.zero;
    Duration? firstOutputAt;
    Duration? lastOutputAt;
    var outputChunks = 0;
    var outputDuration = Duration.zero;
    void markOutput() {
      if (receivedAt == lastOutputAt) return;
      lastOutputAt = receivedAt;
      outputChunks++;
      firstOutputAt ??= receivedAt;
      outputDuration = receivedAt - firstOutputAt!;
    }

    void emitReasoning(String text) {
      if (text.isEmpty) return;
      streamedReasoning.write(text);
      onReasoningDelta?.call(text);
    }

    void completeReasoning(String text) {
      // Responses 的完成事件可能再次包含已推送的摘要，只补充未收到的尾部。
      final received = streamedReasoning.toString();
      if (text.startsWith(received)) {
        emitReasoning(text.substring(received.length));
      }
    }

    void processEvent() {
      if (!successful) return;
      if (dataLines.isEmpty) {
        eventName = '';
        return;
      }
      final data = dataLines.join('\n');
      dataLines.clear();
      final currentEvent = eventName;
      eventName = '';
      if (data == '[DONE]') return;
      final decoded = _decode(data);
      final error = decoded['error'];
      if (error != null || decoded['type'] == 'error') {
        throw AiRequestException(
          error is Map
              ? error['message']?.toString() ?? 'Invalid stream response'
              : decoded['message']?.toString() ?? 'Invalid stream response',
          code: error is Map
              ? error['code']?.toString()
              : decoded['code']?.toString(),
        );
      }
      if (responses) {
        final type = decoded['type'] ?? currentEvent;
        if ((type == 'response.reasoning_summary_text.delta' ||
                type == 'response.reasoning_text.delta') &&
            decoded['delta'] is String) {
          final delta = decoded['delta'] as String;
          if (delta.isNotEmpty) markOutput();
          emitReasoning(delta);
        } else if (type == 'response.output_text.delta' &&
            decoded['delta'] is String) {
          final delta = decoded['delta'] as String;
          if (delta.isNotEmpty) markOutput();
          streamedText.write(delta);
          onTextDelta?.call(delta);
        } else if (type == 'response.function_call_arguments.delta') {
          if (decoded['delta'] case final String delta when delta.isNotEmpty) {
            markOutput();
          }
        } else if (type == 'response.completed' &&
            decoded['response'] is Map<String, dynamic>) {
          responseCompletion = _parseResponses(
            decoded['response'] as Map<String, dynamic>,
          );
          completeReasoning(responseCompletion!.reasoning);
        } else if (type == 'response.output_item.added' &&
            decoded['item'] is Map &&
            (decoded['item'] as Map)['type'] == 'function_call') {
          markOutput();
          onStatus?.call(AiResponseStatus.preparingTools);
        } else if (type == 'response.failed' || type == 'response.incomplete') {
          final response = decoded['response'];
          if (response is Map) {
            _checkResponsesFailure(response);
            if (type == 'response.incomplete') {
              throw AiIncompleteResponseException(
                finishReason: _responseIncompleteReason(response),
                usage: _parseUsage(response['usage'], responses: true),
              );
            }
          }
          if (type == 'response.incomplete') {
            throw const AiIncompleteResponseException();
          }
          throw const AiConfigurationException(AiProblem.invalidResponse);
        }
        return;
      }
      streamedUsage = _parseUsage(decoded['usage']) ?? streamedUsage;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) return;
      final choice = choices.first as Map;
      if (choice['finish_reason'] case final String reason) {
        finishReason = reason;
      }
      final delta = choice['delta'];
      if (delta is! Map) return;
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        markOutput();
        emitReasoning(reasoning);
      }
      final text = delta['content'];
      if (text is String && text.isNotEmpty) {
        markOutput();
        streamedText.write(text);
        onTextDelta?.call(text);
      }
      final calls = delta['tool_calls'];
      if (calls is! List) return;
      if (calls.isNotEmpty) onStatus?.call(AiResponseStatus.preparingTools);
      for (final call in calls.whereType<Map>()) {
        final index = call['index'];
        if (index is! int) continue;
        final collected = toolDeltas.putIfAbsent(index, () => {});
        if (call['id'] is String) collected['id'] = call['id'];
        final function = call['function'];
        if (function is Map) {
          if (function['name'] is String) {
            if ((function['name'] as String).isNotEmpty) markOutput();
            collected['name'] = function['name'];
          }
          if (function['arguments'] is String) {
            if ((function['arguments'] as String).isNotEmpty) markOutput();
            collected['arguments'] =
                '${collected['arguments'] ?? ''}${function['arguments']}';
          }
        }
      }
    }

    final completion = Completer<void>();
    void fail(Object error, StackTrace stackTrace) {
      if (!completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
    }

    _failResponse = fail;
    var reading = true;
    unawaited(
      abortTrigger?.then<void>(
        (_) {
          if (reading) {
            fail(http.RequestAbortedException(uri), StackTrace.current);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (reading) fail(error, stack);
        },
      ),
    );
    var lineTail = '';
    _responseSubscription = response.stream
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            try {
              receivedAt = streamClock.elapsed;
              _armResponseTimeout();
              raw.write(chunk);
              lineTail += chunk;
              final lines = lineTail.split('\n');
              lineTail = lines.removeLast();
              for (final rawLine in lines) {
                final line = rawLine.endsWith('\r')
                    ? rawLine.substring(0, rawLine.length - 1)
                    : rawLine;
                if (line.isEmpty) {
                  processEvent();
                } else if (line.startsWith('data:')) {
                  dataLines.add(line.substring(5).trimLeft());
                } else if (line.startsWith('event:')) {
                  eventName = line.substring(6).trim();
                }
              }
            } catch (error, stackTrace) {
              fail(error, stackTrace);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completion.isCompleted) {
              completion.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!completion.isCompleted) completion.complete();
          },
          cancelOnError: true,
        );
    _armResponseTimeout();
    try {
      await completion.future;
    } finally {
      reading = false;
      _failResponse = null;
      _responseTimeout?.cancel();
      await _responseSubscription?.cancel();
      _responseSubscription = null;
    }
    if (lineTail.isNotEmpty) {
      final lastLine = lineTail.endsWith('\r')
          ? lineTail.substring(0, lineTail.length - 1)
          : lineTail;
      if (lastLine.startsWith('data:')) {
        dataLines.add(lastLine.substring(5).trimLeft());
      } else if (lastLine.startsWith('event:')) {
        eventName = lastLine.substring(6).trim();
      }
    }
    processEvent();

    final body = raw.toString().trim();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (includeUsage &&
          (response.statusCode == 400 || response.statusCode == 422) &&
          const ['stream_options', 'include_usage'].any(body.contains)) {
        throw _StreamUsageUnsupported(endpoint);
      }
      String? detail;
      String? code;
      try {
        final error = _decode(body)['error'];
        detail = error is Map ? error['message']?.toString() : null;
        code = error is Map ? error['code']?.toString() : null;
        if (code != null && code.isNotEmpty) {
          detail = detail == null ? code : '$code: $detail';
        }
      } catch (_) {
        // 非 JSON 网关错误也保留 HTTP 状态，供重试策略判断。
      }
      final retrySeconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw AiRequestException(
        detail?.isNotEmpty == true ? detail! : 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        retryAfter: retrySeconds == null
            ? null
            : Duration(seconds: retrySeconds.clamp(0, 30)),
        code: code,
      );
    }

    if (responseCompletion case final completion?) {
      final received = streamedText.toString();
      if (completion.text.startsWith(received) &&
          completion.text.length > received.length) {
        onTextDelta?.call(completion.text.substring(received.length));
      }
      return AiCompletion(
        text: completion.text,
        toolCalls: completion.toolCalls,
        responseItems: completion.responseItems,
        reasoning: streamedReasoning.toString(),
        usage: completion.usage,
        streamedOutputDuration: outputDuration,
        streamedOutputChunks: outputChunks,
        finishReason: completion.finishReason,
      );
    }
    if (!body.startsWith('data:') && !body.contains('\ndata:')) {
      final decoded = _decode(body);
      final parsed = responses
          ? _parseResponses(decoded)
          : _parseChatCompletion(decoded);
      if (parsed.reasoning.isNotEmpty) onReasoningDelta?.call(parsed.reasoning);
      if (parsed.text.isNotEmpty) onTextDelta?.call(parsed.text);
      return parsed;
    }
    if (responses) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    final calls = <AiToolCall>[];
    for (final entry
        in toolDeltas.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final name = entry.value['name'];
      if (name is! String) continue;
      try {
        final arguments = jsonDecode(
          entry.value['arguments'] as String? ?? '{}',
        );
        if (arguments is Map<String, dynamic>) {
          calls.add(
            AiToolCall(
              id: entry.value['id']?.toString() ?? '',
              name: name,
              arguments: Map<String, Object?>.from(arguments),
            ),
          );
        }
      } on FormatException {
        continue;
      }
    }
    return AiCompletion(
      text: streamedText.toString(),
      toolCalls: calls,
      reasoning: streamedReasoning.toString(),
      usage: streamedUsage,
      streamedOutputDuration: outputDuration,
      streamedOutputChunks: outputChunks,
      finishReason: finishReason,
    );
  }

  AiCompletion _parseChatCompletion(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    final choice = choices.first as Map;
    final message = choice['message'];
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
      reasoning: message['reasoning_content'] is String
          ? message['reasoning_content'] as String
          : message['reasoning'] is String
          ? message['reasoning'] as String
          : '',
      usage: _parseUsage(decoded['usage']),
      finishReason: switch (choice['finish_reason']) {
        final String reason => reason,
        _ => null,
      },
    );
  }

  /// 只读取显式配置的服务地址，不根据模型列表猜测协议。
  Future<List<String>> listModels({
    required String baseUrl,
    required String apiKey,
  }) async =>
      (await discoverModelCatalog(baseUrl: baseUrl, apiKey: apiKey)).models;

  Future<AiModelCatalog> discoverModelCatalog({
    required String baseUrl,
    required String apiKey,
    Future<void>? abortTrigger,
  }) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final finished = Completer<void>();
    final abort = Future.any<void>([finished.future, ?abortTrigger]);
    final request =
        http.AbortableRequest(
            'GET',
            Uri.parse('$base/models'),
            abortTrigger: abort,
          )
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          });
    late http.Response response;
    try {
      response = await Future.any<http.Response>([
        _sendCancellable(request, abort).then(http.Response.fromStream),
        abort.then<http.Response>(
          (_) => throw http.RequestAbortedException(request.url),
        ),
      ]).timeout(const Duration(seconds: 30));
    } finally {
      finished.complete();
    }
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
    final models =
        data
            .whereType<Map>()
            .map((item) => item['id'])
            .whereType<String>()
            .map((model) => model.trim())
            .where((model) => model.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return AiModelCatalog(
      models: models,
      serviceTiers: {
        for (final item in data.whereType<Map>())
          if (item['id'] case final String id)
            if (id.trim().isNotEmpty && item['service_tiers'] is List)
              id.trim(): [
                for (final tier in item['service_tiers'] as List)
                  if (tier is Map && tier['id'] is String) tier['id'] as String,
              ],
      },
      imageInputs: {
        for (final item in data.whereType<Map>())
          if (item['id'] case final String id)
            if (id.trim().isNotEmpty) id.trim(): ?_imageInputDeclaration(item),
      },
    );
  }

  Future<http.StreamedResponse> _sendCancellable(
    http.BaseRequest request,
    Future<void>? abort,
  ) async {
    var abandoned = false;
    final sending = _client.send(request).then((response) {
      if (abandoned) {
        unawaited(
          response.stream
              .listen(null)
              .cancel()
              .catchError((Object _, StackTrace _) {}),
        );
        throw http.RequestAbortedException(request.url);
      }
      return response;
    });
    try {
      return await Future.any<http.StreamedResponse>([
        sending,
        if (abort != null)
          abort.then<http.StreamedResponse>(
            (_) => throw http.RequestAbortedException(request.url),
          ),
      ]).timeout(const Duration(seconds: 90));
    } finally {
      abandoned = true;
    }
  }

  AiImageInput? _imageInputDeclaration(Map model) {
    final architecture = model['architecture'];
    final input =
        model['input_modalities'] ??
        model['inputModalities'] ??
        model['input'] ??
        (architecture is Map ? architecture['input_modalities'] : null);
    if (input is! List ||
        input.isEmpty ||
        input.any((value) => value is! String)) {
      return null;
    }
    if (input.contains('image')) return AiImageInput.supported;
    if (input.contains('text')) return AiImageInput.unsupported;
    return null;
  }

  Future<void> close() async {
    _responseTimeout?.cancel();
    _responseTimeout = null;
    final failResponse = _failResponse;
    _failResponse = null;
    failResponse?.call(http.RequestAbortedException(), StackTrace.current);
    if (_ownsTransport) _client.close();
    final subscription = _responseSubscription;
    _responseSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // Closing a response stream is best-effort during provider disposal.
    }
  }

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
    int? maxTokens,
  ) {
    final instructions = <String>[];
    final input = <Map<String, Object?>>[];
    for (final message in messages) {
      final role = message['role'];
      final content = message['content'];
      if (role == 'system' && instructions.isEmpty && input.isEmpty) {
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
        final responseContent = content is List
            ? [
                for (final part in content.whereType<Map>())
                  if (part['type'] == 'text')
                    {'type': 'input_text', 'text': part['text']}
                  else if (part['type'] == 'image_url' &&
                      part['image_url'] is Map)
                    {
                      'type': 'input_image',
                      'image_url': (part['image_url'] as Map)['url'],
                    },
              ]
            : content;
        input.add({'role': role, 'content': responseContent});
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
      'max_output_tokens': ?maxTokens,
      'store': false,
      'include': ['reasoning.encrypted_content'],
    };
  }

  void _checkResponsesFailure(Map response) {
    if (response['error'] case final Map error) {
      final code = error['code']?.toString();
      final message = error['message']?.toString() ?? code;
      if (message != null) throw AiRequestException(message, code: code);
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
  }

  String? _responseIncompleteReason(Map response) =>
      switch (response['incomplete_details']) {
        {'reason': final String reason} => reason,
        _ => null,
      };

  AiCompletion _parseResponses(Map<String, dynamic> decoded) {
    _checkResponsesFailure(decoded);
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final calls = <AiToolCall>[];
    final output = decoded['output'];
    if (output is! List) {
      throw const AiConfigurationException(AiProblem.invalidResponse);
    }
    for (final item in output.whereType<Map>()) {
      if (item['type'] == 'reasoning') {
        final summary = item['summary'];
        if (summary is List) {
          for (final part in summary.whereType<Map>()) {
            if (part['text'] is String) reasoning.write(part['text']);
          }
        }
        // 仅展示接口公开返回的文本；encrypted_content 仍仅用于协议回放。
        continue;
      }
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
      reasoning: reasoning.toString(),
      toolCalls: calls,
      usage: _parseUsage(decoded['usage'], responses: true),
      finishReason:
          _responseIncompleteReason(decoded) ??
          (decoded['status'] == 'incomplete' ? 'incomplete' : null),
      responseItems: [
        for (final item in output.whereType<Map>())
          Map<String, Object?>.from(item),
      ],
    );
  }

  AiTokenUsage? _parseUsage(Object? raw, {bool responses = false}) {
    if (raw is! Map) return null;
    int? tokens(Object? value) => value is int && value >= 0 ? value : null;

    final hit = tokens(raw['prompt_cache_hit_tokens']);
    final miss = tokens(raw['prompt_cache_miss_tokens']);
    final input =
        tokens(raw[responses ? 'input_tokens' : 'prompt_tokens']) ??
        tokens(raw[responses ? 'prompt_tokens' : 'input_tokens']) ??
        (hit != null && miss != null ? hit + miss : null);
    int? cachedIn(Object? details) =>
        details is Map ? tokens(details['cached_tokens']) : null;
    final cached = responses
        ? cachedIn(raw['input_tokens_details']) ??
              hit ??
              cachedIn(raw['prompt_tokens_details'])
        : hit ??
              cachedIn(raw['prompt_tokens_details']) ??
              cachedIn(raw['input_tokens_details']);
    final output = tokens(raw['output_tokens'] ?? raw['completion_tokens']);
    if (input == null && cached == null && output == null) return null;
    return AiTokenUsage(
      inputTokens: input,
      outputTokens: output,
      cachedTokens: cached,
    );
  }
}

class _StreamUsageUnsupported implements Exception {
  const _StreamUsageUnsupported(this.endpoint);

  final ({String baseUrl, String model}) endpoint;
}
