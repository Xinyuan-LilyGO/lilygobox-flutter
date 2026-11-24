import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';

import '../test/features/assistant/assistant_test_scope.dart';

const _count = 10000;
const _title = '滚动压力测试 · 10,000 条消息';

String _content(int number) {
  final label = 'MSG-${number.toString().padLeft(5, '0')}';
  return switch (number) {
    1 => '$label｜历史起点',
    9995 || 9996 =>
      '$label｜段首｜${List.generate(6000, (index) => '〔$index〕春天的列车驶过河岸，窗边的读者翻过一页。').join()}｜段尾',
    9998 =>
      '$label｜多段 Markdown\n\n${List.generate(1000, (index) => '**段落 $index**：读到这一段时，可以记下编号，向上滚动，再原路返回。').join('\n\n')}',
    10000 =>
      '$label｜历史终点 · 代码块\n\n```text\n${List.generate(2000, (index) => 'ROW-${index.toString().padLeft(4, '0')} | ${index.isEven ? '水平滚动定位点 ' * 24 : '短行'}').join('\n')}\n```\n\nEND-10000｜代码块结束',
    _ when number % 20 == 0 =>
      '$label｜观察记录\n\n- 第一项：保留编号\n- 第二项：对比位置\n\n**备注**：快速滚动后仍应能看到这段话。',
    _ => '$label｜${number.isOdd ? '观察手记' : '记录回执'}：沿途第 $number 个路标。',
  };
}

void main() {
  test('write and import a synthetic 10k-message agent package', () async {
    final directory = await Directory.systemTemp.createTemp('long-chat-test-');
    final storage = AgentStorage(path: '${directory.path}/main.db');
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      storage: storage,
    );
    final workspaces = AiWorkspaceProvider(scope.provider);
    final controller = AgentStorageController(workspaces);
    addTearDown(() async {
      controller.dispose();
      workspaces.dispose();
      scope.dispose();
      await storage.close();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
      await directory.delete(recursive: true);
    });
    await workspaces.initialized;
    final records = <Map<String, Object?>>[];
    final history = <Map<String, Object?>>[];
    for (var number = 1; number <= _count; number++) {
      final time = DateTime.utc(2020).add(Duration(minutes: number));
      final role = number.isOdd ? 'user' : 'assistant';
      final content = _content(number);
      records.add(
        ConversationCodec.message(
          AiMessage(
            id: 'fixture-$number',
            role: role,
            content: content,
            createdAt: time,
            finishedAt: number.isEven
                ? time.add(const Duration(seconds: 2))
                : null,
            elapsed: number.isEven ? const Duration(seconds: 2) : null,
            status: number.isEven ? AiResponseStatus.completed : null,
          ),
        ),
      );
      history.add({'role': role, 'content': content});
    }
    final output = File('artifacts/lilygobox-long-chat-10000.tar.zst');
    await output.parent.create(recursive: true);
    await AgentPackage.write(output.path, {
      'type': 'agent',
      'createdAt': DateTime.utc(2020, 2).toIso8601String(),
      'workflow': {
        'version': 1,
        'selectedId': '10000-0',
        'connections': [],
        'canvas': {},
        'sessions': [
          {
            'id': '10000-0',
            'kind': 'primary',
            'title': _title,
            'task': '',
            'conversation': {
              'serviceId': '',
              'model': '',
              'messages': records,
              'history': history,
              'useMemory': false,
              'autoSaveMemory': false,
            },
          },
        ],
      },
      'memories': [],
    });
    final package = await controller.inspect(output.path);
    expect(package['type'], 'agent');
    await controller.import(package);
    final agent = workspaces.sessions.single;
    expect(agent.title, _title);
    expect(agent.kind, AiWorkspaceKind.primary);
    final messages = agent.assistant.messages;
    expect(messages, hasLength(_count));
    for (var index = 0; index < messages.length; index++) {
      expect(messages[index].id, records[index]['id']);
      expect(messages[index].role, history[index]['role']);
      expect(messages[index].content, history[index]['content']);
    }
    final saved = await storage.request('exportSnapshot') as Map;
    final savedAgent = (saved['workflow']['sessions'] as List).single;
    expect(savedAgent['conversation']['messages'], hasLength(_count));
    expect(savedAgent['conversation']['history'], history);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
