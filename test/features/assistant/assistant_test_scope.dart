/*
 * @Description: 为 assistant 相关界面测试提供隔离的偏好与凭证存储。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 09:45:46
 */

import 'package:http/http.dart' as http;
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/chat_completion_client.dart';
import 'package:lilygobox/features/assistant/data/credential_store.dart';
import 'package:lilygobox/features/assistant/data/settings_tool_handler.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';

class AssistantTestScope {
  AssistantTestScope(this.preferences, this.provider);

  final AppPreferences preferences;
  final AiAssistantProvider provider;

  void dispose() {
    provider.dispose();
    preferences.dispose();
  }
}

Future<AssistantTestScope> createAssistantTestScope({
  required ThemeProvider theme,
  required LanguageProvider language,
  required AppShellProvider shell,
  required SplitViewProvider splitView,
  http.Client? client,
}) async {
  final preferences = await AppPreferences.load(
    storage: _MemoryPreferencesStorage(),
  );
  final provider = AiAssistantProvider(
    preferences: preferences,
    credentialStore: MemoryAiCredentialStore(),
    client: client == null ? null : ChatCompletionClient(client: client),
    settings: SettingsToolHandler(
      preferences: preferences,
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
    ),
  );
  return AssistantTestScope(preferences, provider);
}

class _MemoryPreferencesStorage implements PreferencesStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class MemoryAiCredentialStore implements AiCredentialStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read({String? serviceId}) async =>
      values[serviceId ?? 'legacy'];
  @override
  Future<void> write(String value, {String? serviceId}) async =>
      values[serviceId ?? 'legacy'] = value;
  @override
  Future<void> clear({String? serviceId}) async =>
      values.remove(serviceId ?? 'legacy');
}
