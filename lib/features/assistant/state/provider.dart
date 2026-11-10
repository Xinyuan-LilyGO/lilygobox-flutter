/*
 * @Description: 管理 AI 服务配置、对话、请求状态和 AI 设置操作。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-10 17:19:17
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/storage/preferences.dart';
import '../data/chat_completion_client.dart';
import '../data/credential_store.dart';
import '../data/model_service_repository.dart';
import '../data/settings_tool_handler.dart';
import '../domain/models.dart';
import '../domain/reasoning.dart';

class AiAssistantProvider extends ChangeNotifier {
  AiAssistantProvider({
    required AppPreferences preferences,
    required AiCredentialStore credentialStore,
    required SettingsToolHandler settings,
    ChatCompletionClient? client,
  }) : _repository = ModelServiceRepository(preferences, credentialStore),
       _settings = settings,
       _client = client ?? ChatCompletionClient() {
    _initializing = _restoreServices();
  }

  final ModelServiceRepository _repository;
  final SettingsToolHandler _settings;
  final ChatCompletionClient _client;
  final List<AiMessage> _messages = [];
  final List<Map<String, Object?>> _history = [];
  final Set<String> _resolvingToolIds = {};
  late final Future<void> _initializing;
  bool _credentialLoaded = false;
  bool _loadFailed = false;
  bool _busy = false;
  bool _paused = false;
  bool _stopRequested = false;
  bool _saving = false;
  bool _disposed = false;
  Completer<void>? _abortRequest;
  _AssistantTextOutput? _activeOutput;
  AiServiceConfiguration? _activeConfiguration;
  String? _activeApiKey;
  final Stopwatch _turnStopwatch = Stopwatch();
  Timer? _elapsedTimer;
  String? _activeMessageId;
  DateTime? _activeMessageCreatedAt;
  final List<AiProcessingStep> _activeProcessingSteps = [];
  final List<AiRequestRetry> _activeRetries = [];
  AiResponseStatus _activeStatus = AiResponseStatus.connecting;
  final List<AiProcessEvent> _activeProcessEvents = [];
  Timer? _processNotifyTimer;
  int _activeRequestNumber = 0;
  Object? _error;
  Object? _configurationError;
  int _nextMessageId = 0;

  List<AiModelService> get services => _repository.services;
  AiModelService? get selectedService => _repository.selectedService;
  String? get selectedModel => _repository.selectedModel;
  AiReasoningEffort? get reasoningEffort =>
      selectedService == null || selectedModel == null
      ? null
      : _repository.effortFor(selectedService!.id, selectedModel!);
  AiServiceConfiguration get configuration => AiServiceConfiguration(
    protocol: selectedService?.protocol ?? AiApiProtocol.openAiChatCompletions,
    baseUrl: selectedService?.baseUrl ?? '',
    model: selectedModel ?? '',
    reasoningEffort: reasoningEffort,
  );
  List<AiMessage> get messages => List.unmodifiable(_messages);
  bool get credentialLoaded => _credentialLoaded;
  bool get hasApiKey => hasServiceKey(selectedService?.id);
  bool hasServiceKey(String? id) => _repository.keyFor(id)?.isNotEmpty == true;
  bool get busy => _busy;
  bool get paused => _paused;
  bool isThinking(String id) =>
      _busy &&
      id == _activeMessageId &&
      _activeStatus == AiResponseStatus.thinking;
  bool get saving => _saving;
  bool get canChangeService => _credentialLoaded && !_loadFailed && !_saving;
  bool get canSendMessage => canChangeService && !_busy;
  Object? get error => _error;
  Object? get configurationError => _configurationError;
  bool isResolvingTool(String id) => _resolvingToolIds.contains(id);
  Future<void> get initialized => _initializing;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _restoreServices() async {
    try {
      await _repository.load();
    } catch (_) {
      _loadFailed = true;
      _configurationError = const AiConfigurationException(AiProblem.storage);
    } finally {
      _credentialLoaded = true;
      _notify();
    }
  }

  Future<T> _change<T>(Future<T> Function() action) async {
    if (!_credentialLoaded) await initialized;
    if (!canChangeService) {
      throw AiConfigurationException(
        _loadFailed ? AiProblem.storage : AiProblem.busy,
      );
    }
    _saving = true;
    _error = null;
    _notify();
    try {
      return await action();
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<String> saveService({
    String? id,
    required String name,
    required AiApiProtocol protocol,
    required String baseUrl,
    required List<String> models,
    String? apiKey,
    AiServicePreset preset = AiServicePreset.custom,
    Map<String, AiImageInput>? imageInputs,
  }) => _change(
    () => _repository.save(
      id: id,
      name: name,
      protocol: protocol,
      baseUrl: baseUrl,
      models: models,
      apiKey: apiKey,
      preset: preset,
      imageInputs: imageInputs,
    ),
  );

  Future<void> selectModel(String serviceId, String model) =>
      _change(() => _repository.select(serviceId, model));

  Future<void> setReasoningEffort(AiReasoningEffort? effort) =>
      _change(() async {
        final service = selectedService;
        final model = selectedModel;
        if (service == null || model == null) {
          throw const AiConfigurationException(AiProblem.noService);
        }
        await _repository.setReasoningEffort(service.id, model, effort);
      });

  Future<void> reorderServices(int oldIndex, int newIndex) =>
      _change(() => _repository.reorder(oldIndex, newIndex));

  Future<void> removeService(String serviceId) =>
      _change(() => _repository.remove(serviceId));

  Future<List<String>> discoverModels({
    required String baseUrl,
    required String apiKey,
    String? serviceId,
  }) async => (await discoverModelCatalog(
    baseUrl: baseUrl,
    apiKey: apiKey,
    serviceId: serviceId,
  )).models;

  Future<AiModelCatalog> discoverModelCatalog({
    required String baseUrl,
    required String apiKey,
    String? serviceId,
  }) async {
    final address = ModelServiceRepository.validateAddress(baseUrl);
    final service = _repository.find(serviceId);
    final key = apiKey.trim().isNotEmpty
        ? apiKey.trim()
        : service != null &&
              Uri.parse(service.baseUrl).origin == Uri.parse(address).origin
        ? _repository.keyFor(serviceId)
        : null;
    if (key == null || key.isEmpty) {
      throw const AiConfigurationException(AiProblem.keyRequired);
    }
    return _client.discoverModelCatalog(baseUrl: address, apiKey: key);
  }

  bool get hasImageHistory => _history.any(
    (message) =>
        message['content'] is List &&
        (message['content'] as List).any(
          (part) => part is Map && part['type'] == 'image_url',
        ),
  );

  bool canAcceptImages() =>
      selectedService?.imageInputFor(selectedModel ?? '') !=
      AiImageInput.unsupported;

  bool get canSendImageHistory => !hasImageHistory || canAcceptImages();

  Future<void> sendMessage(
    String content, {
    List<AiImageAttachment> attachments = const [],
  }) async {
    final text = content.trim();
    if ((text.isEmpty && attachments.isEmpty) || !canSendMessage) return;
    if (!hasApiKey) {
      _error = const AiConfigurationException(AiProblem.noService);
      _notify();
      return;
    }
    if ((!canAcceptImages() && attachments.isNotEmpty) ||
        !canSendImageHistory) {
      _error = const AiConfigurationException(AiProblem.imageUnsupported);
      _notify();
      return;
    }
    _error = null;
    _messages.add(
      _message(role: 'user', content: text, attachments: attachments),
    );
    _history.add({
      'role': 'user',
      'content': _messageContent(text, attachments),
    });
    _stopRequested = false;
    _paused = false;
    _activeConfiguration = configuration;
    _activeApiKey = _repository.keyFor(selectedService!.id)!;
    _activeProcessingSteps.clear();
    _activeRetries.clear();
    _activeProcessEvents.clear();
    _activeRequestNumber = 0;
    _activeStatus = AiResponseStatus.connecting;
    _turnStopwatch
      ..reset()
      ..start();
    _appendStatusEvent(AiResponseStatus.connecting);
    _activeMessageId = _newId();
    _activeMessageCreatedAt = DateTime.now();
    _messages.add(
      _withTurnDetails(
        AiMessage(id: _activeMessageId!, role: 'assistant', content: ''),
      ),
    );
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshElapsed();
    });
    _abortRequest = Completer<void>();
    _busy = true;
    _notify();
    await _requestAssistant();
  }

  void stopGeneration() {
    if (!_busy || _stopRequested) return;
    _stopRequested = true;
    _activeOutput?.stop();
    _client.resumeResponse();
    _paused = false;
    final abortRequest = _abortRequest;
    if (abortRequest != null && !abortRequest.isCompleted) {
      abortRequest.complete();
    }
  }

  void pauseGeneration() {
    if (!_busy || _paused) return;
    _paused = true;
    _turnStopwatch.stop();
    _appendStatusEvent(AiResponseStatus.paused);
    _refreshElapsed();
    _activeOutput?.pause();
    _client.pauseResponse();
    _notify();
  }

  void resumeGeneration() {
    if (!_busy || !_paused) return;
    _paused = false;
    _turnStopwatch.start();
    _appendStatusEvent(_activeStatus);
    _activeOutput?.resume();
    _client.resumeResponse();
    _refreshElapsed();
    _notify();
  }

  Future<void> resolveTool(String messageId, {required bool approve}) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0 ||
        _messages[index].toolDecision != null ||
        !_resolvingToolIds.add(messageId)) {
      return;
    }
    final message = _messages[index];
    final toolName = message.toolName!;
    final arguments = message.toolArguments!;
    var result = 'The user declined this setting change.';
    _notify();
    try {
      if (approve) {
        try {
          result = await _settings.execute(toolName, arguments);
        } catch (error) {
          result = 'The setting change failed: $error';
        }
      }
      _messages[index] = message.copyWith(toolDecision: approve);
      _history.add({
        'role': 'tool',
        'tool_call_id': message.id,
        'content': result,
      });
    } finally {
      _resolvingToolIds.remove(messageId);
    }
    if (_messages.any(
      (item) => item.toolName != null && item.toolDecision == null,
    )) {
      _notify();
      return;
    }
    _stopRequested = false;
    _paused = false;
    _abortRequest = Completer<void>();
    _activeConfiguration ??= configuration;
    _activeApiKey ??= _repository.keyFor(selectedService!.id)!;
    _busy = true;
    _notify();
    await _requestAssistant();
  }

  void clearConversation() {
    if (_busy) return;
    _messages.clear();
    _history.clear();
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    stopGeneration();
    _processNotifyTimer?.cancel();
    _elapsedTimer?.cancel();
    _activeOutput?.stop();
    _turnStopwatch.stop();
    _disposed = true;
    unawaited(_client.close());
    super.dispose();
  }

  Future<void> _requestAssistant() async {
    final requestNumber = ++_activeRequestNumber;
    String? streamingMessageId = _activeMessageId;
    var streamedContent = '';
    late final _AssistantTextOutput output;

    void showNextDelta(String delta) {
      streamedContent += delta;
      streamingMessageId ??= _newId();
      final index = _messages.indexWhere(
        (message) => message.id == streamingMessageId,
      );
      final updated = _withTurnDetails(
        AiMessage(
          id: streamingMessageId!,
          role: 'assistant',
          content: streamedContent,
        ),
      );
      if (index < 0) {
        _messages.add(updated);
      } else {
        _messages[index] = updated;
      }
      _notify();
    }

    output = _AssistantTextOutput(showNextDelta, initiallyPaused: _paused);
    _activeOutput = output;

    try {
      final completion = await _client.complete(
        configuration: _activeConfiguration!,
        apiKey: _activeApiKey!,
        messages: [
          {
            'role': 'system',
            'content':
                'You are the LilygoBox assistant. Help with the app and its settings. '
                'Use setting tools when the user asks to change a supported setting. '
                'Apply supported, reversible app setting changes immediately. '
                'Only report success after the setting tool returns successfully. '
                'Reply in the language used by the user.',
          },
          ..._history,
        ],
        tools: _settingTools,
        abortTrigger: _abortRequest?.future,
        onTextDelta: output.add,
        onReasoningDelta: _recordReasoning,
        onStatus: (status) {
          if (_disposed || _stopRequested || _activeStatus == status) return;
          _recordStatus(
            status == AiResponseStatus.connecting && requestNumber > 1
                ? AiResponseStatus.awaitingReply
                : status,
          );
        },
        onRetry: (attempt, error) {
          if (_disposed || _stopRequested) return;
          final retry = AiRequestRetry(attempt, error);
          _activeRetries.add(retry);
          _activeProcessEvents.add(
            AiProcessEvent(
              type: AiProcessEventType.retry,
              elapsed: _turnStopwatch.elapsed,
              retry: retry,
            ),
          );
          _activeStatus = AiResponseStatus.retrying;
          _refreshElapsed();
        },
      );
      await output.finish();
      if (completion.toolCalls.isEmpty) {
        if (completion.text.isNotEmpty) {
          if (streamingMessageId case final id?) {
            final index = _messages.indexWhere((message) => message.id == id);
            if (index >= 0) {
              _messages[index] = _withTurnDetails(
                _messages[index].copyWith(content: completion.text),
              );
            }
          } else {
            _messages.add(
              _withTurnDetails(
                _message(role: 'assistant', content: completion.text),
              ),
            );
          }
          _history.add({
            'role': 'assistant',
            'content': completion.text,
            if (completion.reasoning.isNotEmpty)
              'reasoning_content': completion.reasoning,
            if (completion.responseItems.isNotEmpty)
              'response_items': completion.responseItems,
          });
        }
        _error = null;
        return;
      }
      final calls = [
        for (final call in completion.toolCalls)
          AiToolCall(
            id: call.id.isEmpty ? _newId() : call.id,
            name: call.name,
            arguments: call.arguments,
          ),
      ];
      if (completion.text.isNotEmpty) {
        _activeProcessEvents.add(
          AiProcessEvent(
            type: AiProcessEventType.assistant,
            elapsed: _turnStopwatch.elapsed,
            text: completion.text,
          ),
        );
        final index = _messages.indexWhere(
          (message) => message.id == _activeMessageId,
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(content: '');
        }
      }
      _history.add({
        'role': 'assistant',
        'content': completion.text.isEmpty ? null : completion.text,
        if (completion.reasoning.isNotEmpty)
          'reasoning_content': completion.reasoning,
        if (completion.responseItems.isNotEmpty)
          'response_items': completion.responseItems,
        'tool_calls': [
          for (final call in calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
      });
      for (final call in calls) {
        if (_stopRequested) break;
        _recordStatus(AiResponseStatus.executingTools);
        String result;
        var succeeded = true;
        try {
          result = await _settings.execute(call.name, call.arguments);
        } catch (error) {
          succeeded = false;
          result = 'The setting change failed: $error';
        }
        final step = AiProcessingStep(
          name: call.name,
          arguments: call.arguments,
          succeeded: succeeded,
        );
        _activeProcessingSteps.add(step);
        _activeProcessEvents.add(
          AiProcessEvent(
            type: AiProcessEventType.action,
            elapsed: _turnStopwatch.elapsed,
            action: step,
          ),
        );
        _refreshElapsed();
        _history.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result,
        });
      }
      if (!_stopRequested) await _requestAssistant();
    } catch (error) {
      output.stop();
      await output.finish();
      if (_stopRequested) {
        if (streamedContent.isNotEmpty) {
          _history.add({'role': 'assistant', 'content': streamedContent});
        }
      }
      if (streamingMessageId case final id?) {
        final index = _messages.indexWhere((message) => message.id == id);
        if (index >= 0) {
          _messages[index] = _withTurnDetails(_messages[index]);
        }
      }
      if (!_stopRequested) {
        _error = error;
        final index = _messages.indexWhere(
          (message) => message.id == _activeMessageId,
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(requestError: error);
        }
      }
    } finally {
      output.stop();
      await output.finish();
      if (identical(_activeOutput, output)) _activeOutput = null;
      _busy = false;
      _paused = false;
      _abortRequest = null;
      _turnStopwatch.stop();
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _processNotifyTimer?.cancel();
      _processNotifyTimer = null;
      _activeStatus = _stopRequested
          ? AiResponseStatus.stopped
          : _error != null
          ? AiResponseStatus.failed
          : AiResponseStatus.completed;
      if (_activeMessageId != null) _appendStatusEvent(_activeStatus);
      _refreshElapsed();
      if (_stopRequested) {
        _messages.removeWhere(
          (message) =>
              message.id == _activeMessageId &&
              message.content.isEmpty &&
              !message.processEvents.any(
                (event) => event.type != AiProcessEventType.status,
              ),
        );
      }
      _activeMessageId = null;
      _activeConfiguration = null;
      _activeApiKey = null;
      _notify();
    }
  }

  void _appendStatusEvent(AiResponseStatus status) {
    _activeProcessEvents.add(
      AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: _turnStopwatch.elapsed,
        status: status,
      ),
    );
  }

  void _recordStatus(AiResponseStatus status) {
    if (_activeStatus == status) return;
    _activeStatus = status;
    _appendStatusEvent(status);
    _refreshElapsed();
  }

  void _recordReasoning(String text) {
    if (_disposed || _stopRequested || text.isEmpty) return;
    if (_activeProcessEvents.isNotEmpty &&
        _activeProcessEvents.last.type == AiProcessEventType.status &&
        _activeProcessEvents.last.status == AiResponseStatus.thinking) {
      final previous = _activeProcessEvents.removeLast();
      _activeProcessEvents.add(
        AiProcessEvent(
          type: AiProcessEventType.reasoning,
          elapsed: previous.elapsed,
          text: text,
        ),
      );
    } else if (_activeProcessEvents.isNotEmpty &&
        _activeProcessEvents.last.type == AiProcessEventType.reasoning) {
      final previous = _activeProcessEvents.last;
      _activeProcessEvents[_activeProcessEvents.length - 1] = AiProcessEvent(
        type: AiProcessEventType.reasoning,
        elapsed: previous.elapsed,
        text: previous.text + text,
      );
    } else {
      _activeProcessEvents.add(
        AiProcessEvent(
          type: AiProcessEventType.reasoning,
          elapsed: _turnStopwatch.elapsed,
          text: text,
        ),
      );
    }
    // 合并同一帧内的思考增量，避免每个 token 都重建整个聊天页。
    _processNotifyTimer ??= Timer(const Duration(milliseconds: 16), () {
      _processNotifyTimer = null;
      _refreshElapsed();
    });
  }

  void _refreshElapsed() {
    final index = _messages.indexWhere(
      (message) => message.id == _activeMessageId,
    );
    if (index < 0) return;
    _messages[index] = _withTurnDetails(_messages[index]);
    _notify();
  }

  AiMessage _message({
    required String role,
    required String content,
    List<AiImageAttachment> attachments = const [],
  }) => AiMessage(
    id: _newId(),
    role: role,
    content: content,
    createdAt: DateTime.now(),
    attachments: attachments,
  );

  Object _messageContent(String text, List<AiImageAttachment> attachments) {
    if (attachments.isEmpty) return text;
    return [
      if (text.isNotEmpty) {'type': 'text', 'text': text},
      for (final attachment in attachments)
        {
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${attachment.mimeType};base64,${base64Encode(attachment.bytes)}',
          },
        },
    ];
  }

  AiMessage _withTurnDetails(AiMessage message) => message.copyWith(
    createdAt: message.createdAt ?? _activeMessageCreatedAt,
    elapsed: _turnStopwatch.elapsed,
    model: _activeConfiguration?.model,
    reasoningEffort: _activeConfiguration?.reasoningEffort,
    protocol: _activeConfiguration?.protocol,
    processingSteps: List.unmodifiable(_activeProcessingSteps),
    status: _paused ? AiResponseStatus.paused : _activeStatus,
    retries: List.unmodifiable(_activeRetries),
    processEvents: List.unmodifiable(_activeProcessEvents),
  );

  String _newId() => 'assistant-${_nextMessageId++}';
}

class _AssistantTextOutput {
  _AssistantTextOutput(this._onChunk, {required bool initiallyPaused})
    : _paused = initiallyPaused;

  final void Function(String) _onChunk;
  final List<String> _pending = [];
  bool _paused;
  bool _stopped = false;
  Future<void>? _drain;
  Completer<void>? _resumeSignal;

  void add(String text) {
    if (_stopped || text.isEmpty) return;
    _pending.add(text);
    // 先登记任务再运行。单字增量可同步排空，直接调用会把已清空的
    // _drain 覆盖回已完成的 Future，导致 finish 不断等待同一个任务。
    _drain ??= Future<void>.microtask(_run);
  }

  Future<void> finish() async {
    while (_drain != null) {
      await _drain;
    }
  }

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    final signal = _resumeSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _resumeSignal = null;
  }

  void stop() {
    _stopped = true;
    _pending.clear();
    resume();
  }

  Future<void> _run() async {
    try {
      while (_pending.isNotEmpty && !_stopped) {
        if (_paused) {
          _resumeSignal ??= Completer<void>();
          await _resumeSignal!.future;
          continue;
        }
        final text = _pending.join();
        _pending.clear();
        _onChunk(text);
      }
    } finally {
      _drain = null;
    }
  }
}

final _settingTools = <Map<String, Object?>>[
  _tool(
    'set_theme',
    'Change the application color theme.',
    {
      'theme': _string(['dark', 'light']),
    },
    ['theme'],
  ),
  _tool(
    'set_language',
    'Change the application interface language.',
    {
      'language': _string(['auto', 'en', 'zh']),
    },
    ['language'],
  ),
  _tool(
    'set_font',
    'Change the application font.',
    {
      'font': _string(['system', 'inter', 'googleSansFlex', 'roboto']),
    },
    ['font'],
  ),
  _tool(
    'set_sidebar_visibility',
    'Show or hide the main sidebar.',
    {
      'visible': {'type': 'boolean'},
    },
    ['visible'],
  ),
  _tool(
    'set_sidebar_width',
    'Set the main sidebar width from 180 to 360.',
    {'width': _number(180, 360)},
    ['width'],
  ),
  _tool(
    'set_content_split_width',
    'Set the device split view width from 100 to 1200.',
    {'width': _number(100, 1200)},
    ['width'],
  ),
  _tool(
    'set_settings_sidebar_width',
    'Set the settings sidebar width from 176 to 300.',
    {'width': _number(176, 300)},
    ['width'],
  ),
];

Map<String, Object?> _tool(
  String name,
  String description,
  Map<String, Object?> properties,
  List<String> required,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    },
  },
};

Map<String, Object?> _string(List<String> values) => {
  'type': 'string',
  'enum': values,
};

Map<String, Object?> _number(double min, double max) => {
  'type': 'number',
  'minimum': min,
  'maximum': max,
};
