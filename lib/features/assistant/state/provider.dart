/*
 * @Description: 管理 AI 服务配置、对话、请求状态和待用户确认的设置变更。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 15:56:05
 * @License: GPL 3.0
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
  bool _testing = false;
  bool _saving = false;
  bool _disposed = false;
  Object? _error;
  int _nextMessageId = 0;

  List<AiModelService> get services => _repository.services;
  AiModelService? get selectedService => _repository.selectedService;
  String? get selectedModel => _repository.selectedModel;
  AiServiceConfiguration get configuration => AiServiceConfiguration(
    protocol: selectedService?.protocol ?? AiApiProtocol.openAiChatCompletions,
    baseUrl: selectedService?.baseUrl ?? '',
    model: selectedModel ?? '',
  );
  List<AiMessage> get messages => List.unmodifiable(_messages);
  bool get credentialLoaded => _credentialLoaded;
  bool get hasApiKey => hasServiceKey(selectedService?.id);
  bool hasServiceKey(String? id) => _repository.keyFor(id)?.isNotEmpty == true;
  bool get busy => _busy;
  bool get testing => _testing;
  bool get saving => _saving;
  bool get canChangeService =>
      _credentialLoaded &&
      !_loadFailed &&
      !_busy &&
      !_testing &&
      !_saving &&
      !_messages.any(
        (message) => message.toolName != null && message.toolDecision == null,
      );
  Object? get error => _error;
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
      _error = const AiConfigurationException(AiProblem.storage);
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
  }) => _change(
    () => _repository.save(
      id: id,
      name: name,
      protocol: protocol,
      baseUrl: baseUrl,
      models: models,
      apiKey: apiKey,
    ),
  );

  Future<void> selectModel(String serviceId, String model) =>
      _change(() => _repository.select(serviceId, model));

  Future<void> reorderServices(int oldIndex, int newIndex) =>
      _change(() => _repository.reorder(oldIndex, newIndex));

  Future<void> removeService(String serviceId) =>
      _change(() => _repository.remove(serviceId));

  Future<List<String>> discoverModels({
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
    return _client.listModels(baseUrl: address, apiKey: key);
  }

  Future<bool> testConnection({String? serviceId}) async {
    if (!_credentialLoaded) await initialized;
    if (!canChangeService) return false;
    final service = _repository.find(serviceId ?? selectedService?.id);
    if (service == null) {
      _error = const AiConfigurationException(AiProblem.noService);
      _notify();
      return false;
    }
    final key = _repository.keyFor(service.id);
    if (key == null || key.isEmpty) {
      _error = const AiConfigurationException(AiProblem.keyRequired);
      _notify();
      return false;
    }
    _testing = true;
    _error = null;
    _notify();
    try {
      await _client.complete(
        configuration: AiServiceConfiguration(
          protocol: service.protocol,
          baseUrl: service.baseUrl,
          model: service.id == selectedService?.id
              ? selectedModel!
              : service.models.first,
        ),
        apiKey: key,
        messages: const [
          {'role': 'user', 'content': 'Reply with OK.'},
        ],
        tools: const [],
        maxTokens: 8,
      );
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _testing = false;
      _notify();
    }
  }

  Future<void> sendMessage(String content) async {
    final text = content.trim();
    if (text.isEmpty || !canChangeService) return;
    if (!hasApiKey) {
      _error = const AiConfigurationException(AiProblem.noService);
      _notify();
      return;
    }
    _error = null;
    _messages.add(_message(role: 'user', content: text));
    _history.add({'role': 'user', 'content': text});
    _busy = true;
    _notify();
    await _requestAssistant();
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
    _disposed = true;
    unawaited(_client.close());
    super.dispose();
  }

  Future<void> _requestAssistant() async {
    try {
      final completion = await _client.complete(
        configuration: configuration,
        apiKey: _repository.keyFor(selectedService!.id)!,
        messages: [
          {
            'role': 'system',
            'content':
                'You are the LilygoBox assistant. Help with the app and its settings. '
                'Use setting tools when the user asks to change a supported setting. '
                'Never claim an action succeeded before the user approves it. '
                'Reply in the language used by the user.',
          },
          ..._history,
        ],
        tools: _settingTools,
      );
      if (completion.toolCalls.isEmpty) {
        if (completion.text.isNotEmpty) {
          _messages.add(_message(role: 'assistant', content: completion.text));
          _history.add({
            'role': 'assistant',
            'content': completion.text,
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
      _history.add({
        'role': 'assistant',
        'content': completion.text.isEmpty ? null : completion.text,
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
        _messages.add(
          AiMessage(
            id: call.id,
            role: 'assistant',
            content: '',
            toolName: call.name,
            toolArguments: call.arguments,
          ),
        );
      }
      _notify();
    } catch (error) {
      _error = error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  AiMessage _message({required String role, required String content}) =>
      AiMessage(id: _newId(), role: role, content: content);

  String _newId() => 'assistant-${_nextMessageId++}';
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
