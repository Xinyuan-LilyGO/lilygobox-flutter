import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';
import 'package:lilygobox/features/assistant/domain/roleplay_card.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  for (final protocol in AiApiProtocol.values) {
    group(protocol.name, () {
      late AssistantTestScope scope;
      late AiAssistantProvider agent;
      late String serviceId;
      late List<Map<String, Object?>> requests;

      setUp(() async {
        final theme = ThemeProvider();
        final language = LanguageProvider();
        final shell = AppShellProvider();
        final splitView = SplitViewProvider();
        requests = [];
        addTearDown(theme.dispose);
        addTearDown(language.dispose);
        addTearDown(shell.dispose);
        addTearDown(splitView.dispose);
        scope = await createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: splitView,
          client: MockClient((request) async {
            requests.add(_decodeObject(request.body));
            return http.Response(jsonEncode(_response(protocol)), 200);
          }),
        );
        addTearDown(scope.dispose);
        await scope.provider.initialized;
        serviceId = await scope.provider.saveService(
          name: 'Roleplay test',
          protocol: protocol,
          baseUrl: 'https://example.test/v1',
          models: ['initial-model'],
          apiKey: 'test-key',
        );
        agent = scope.provider.forkForWorkspace();
        addTearDown(agent.dispose);
        await agent.selectModel(serviceId, 'initial-model');
      });

      AiAssistantProvider restore(Map<String, Object?> snapshot) {
        final restored = scope.provider.forkForWorkspace();
        addTearDown(restored.dispose);
        restored.restoreWorkspaceConversation(
          _decodeObject(jsonEncode(snapshot)),
        );
        return restored;
      }

      test(
        'applies selected card context without replacing history or tools',
        () async {
          await agent.sendMessage('Keep my task history');
          expect(
            _systemPrompt(requests.single, protocol),
            contains('Reply in'),
          );
          final before = agent.messages.toList();
          expect(agent.bindRoleplay(_binding(_card)), isTrue);
          expect(agent.canChooseRoleplayOpening, isTrue);
          expect(agent.startRoleplayOpening(0, clearExisting: false), isFalse);
          expect(agent.messages, orderedEquals(before));
          expect(requests, hasLength(1));

          await agent.sendMessage('What do you do?');
          final noMatch = jsonEncode(requests.last);
          final activePrompt = _systemPrompt(requests.last, protocol);
          expect(
            activePrompt,
            contains('Earlier replies do not override the role'),
          );
          expect(activePrompt, contains('within permissions'));
          expect(activePrompt, isNot(contains('Reply in')));
          expect(activePrompt, isNot(contains('wait_timer')));
          expect(requests.last['tools'], isNotEmpty);
          for (final content in [
            'Use available tools',
            'Keep my task history',
            'Lan repairs clocks.',
            'Quiet and meticulous.',
            'Use a fairy-tale rhythm.',
            'End on a quiet note.',
          ]) {
            expect(noMatch, contains(content));
          }
          for (final content in [
            'It is close to midnight.',
            'A clock never forgets.',
            'Welcome to the shop.',
            'Good evening, Player.',
            'Author notes stay local.',
            'The trees bloom every winter.',
          ]) {
            expect(noMatch, isNot(contains(content)));
          }

          await agent.sendMessage('Tell me about the Orchard.');
          final matched = jsonEncode(requests.last);
          expect(matched, contains('The trees bloom every winter.'));
          expect(matched, isNot(contains('A disabled world entry.')));

          agent.setRoleplayEnabled(false);
          final restored = restore(agent.snapshotWorkspaceConversation());
          expect(restored.roleplayEnabled, isFalse);
          expect(restored.roleplayBinding?.card.name, 'Lan');
          await agent.sendMessage('Speak normally about the Orchard.');
          final paused = jsonEncode(requests.last);
          expect(_systemPrompt(requests.last, protocol), contains('Reply in'));
          expect(paused, contains('Keep my task history'));
          for (final content in [
            'Lan repairs clocks.',
            'It is close to midnight.',
            'Use a fairy-tale rhythm.',
            'End on a quiet note.',
            'The trees bloom every winter.',
          ]) {
            expect(paused, isNot(contains(content)));
          }
          expect(agent.removeRoleplay(), isTrue);
          expect(agent.messages.first.content, 'Keep my task history');
        },
      );

      test('uses one selected opening in the empty current chat', () async {
        expect(agent.bindRoleplay(_binding(_card)), isTrue);
        expect(agent.canChooseRoleplayOpening, isTrue);
        expect(agent.startRoleplayOpening(2, clearExisting: false), isFalse);
        expect(agent.messages, isEmpty);
        expect(agent.startRoleplayOpening(1, clearExisting: false), isTrue);
        expect(agent.startRoleplayOpening(0, clearExisting: false), isFalse);
        expect(agent.messages.single.content, 'Good evening, Player.');
        expect(agent.messages.single.isRoleplayOpening, isTrue);
        expect(requests, isEmpty);

        final restored = restore(agent.snapshotWorkspaceConversation());
        expect(restored.messages.single.isRoleplayOpening, isTrue);
        expect(restored.canChooseRoleplayOpening, isTrue);
        expect(restored.roleplayBinding?.storyActive, isTrue);
        await restored.sendMessage('May I come in?');
        final body = jsonEncode(requests.single);
        expect(body, contains('Good evening, Player.'));
        expect(body, contains('May I come in?'));
        expect(body, contains('It is close to midnight.'));
        expect(body, contains('A clock never forgets.'));
        expect(body, isNot(contains('Welcome to the shop.')));
      });

      test(
        'confirmed restart replaces only the chat and its context',
        () async {
          expect(agent.bindRoleplay(_binding(_card)), isTrue);
          await agent.sendMessage('Old chat to clear');
          final permissions = AiPermissions(mode: AiApprovalMode.custom);
          agent.setPermissions(permissions);
          expect(agent.hasConversationToRestart, isTrue);
          expect(agent.startRoleplayOpening(2, clearExisting: true), isFalse);
          expect(agent.messages.first.content, 'Old chat to clear');
          expect(agent.startRoleplayOpening(0, clearExisting: true), isTrue);
          expect(agent.messages.single.content, 'Welcome to the shop.');
          expect(agent.permissions, same(permissions));

          await agent.sendMessage('My first message in the story');
          final body = jsonEncode(requests.last);
          expect(body, contains('Welcome to the shop.'));
          expect(body, contains('It is close to midnight.'));
          expect(body, isNot(contains('Old chat to clear')));

          agent.clearConversation();
          expect(agent.messages, isEmpty);
          expect(agent.roleplayBinding?.storyActive, isFalse);
          expect(agent.canChooseRoleplayOpening, isTrue);
        },
      );

      test(
        'saving card options changes only future roleplay context',
        () async {
          agent.bindRoleplay(
            AiRoleplayBinding(
              card: _card,
              playerName: 'Player',
              includeProfile: true,
            ),
          );
          final restored = restore(agent.snapshotWorkspaceConversation());
          await restored.selectModel(serviceId, 'initial-model');
          await restored.sendMessage('Tell me about the orchard.');
          final before = restored.messages.toList();
          final initial = restored.roleplayBinding!;
          expect(initial.card.worldEntryCount, isZero);
          expect(initial.sourceCard.worldEntryCount, greaterThan(0));
          expect(
            jsonEncode(requests.single),
            isNot(contains('bloom every winter')),
          );

          restored.updateRoleplayOptions(
            initial,
            AiRoleplayBinding(
              card: initial.sourceCard,
              playerName: initial.playerName,
              includeWorldBook: true,
            ),
          );
          expect(restored.messages, orderedEquals(before));
          expect(restored.roleplayEnabled, isTrue);
          expect(restored.canChooseRoleplayOpening, isTrue);
          await restored.sendMessage('Tell me more about the orchard.');
          final body = jsonEncode(requests.last);
          expect(body, contains('The trees bloom every winter.'));
          expect(body, isNot(contains('A clock never forgets.')));
          expect(body, isNot(contains('Lan repairs clocks.')));
          expect(body, isNot(contains('Welcome to the shop.')));
        },
      );

      test(
        'can start without a greeting and use world book by itself',
        () async {
          expect(
            agent.bindRoleplay(
              AiRoleplayBinding(
                card: _card,
                playerName: 'Player',
                includeWorldBook: true,
              ),
            ),
            isTrue,
          );
          expect(agent.canChooseRoleplayOpening, isTrue);
          await agent.sendMessage('Tell me about the orchard.');
          final body = jsonEncode(requests.single);
          final worldBookPrompt = _systemPrompt(requests.single, protocol);
          expect(worldBookPrompt, contains('Reply in'));
          expect(worldBookPrompt, isNot(contains('fictional profile')));
          expect(agent.messages.first.role, 'user');
          expect(body, contains('The trees bloom every winter.'));
          expect(body, isNot(contains('Lan repairs clocks.')));
          expect(body, isNot(contains('A clock never forgets.')));
          expect(body, isNot(contains('Use a fairy-tale rhythm.')));
          expect(body, isNot(contains('Welcome to the shop.')));
        },
      );

      test(
        'restores the current card binding without retaining old story data',
        () async {
          await agent.sendMessage('Original task');
          const oldGreeting = AiMessage(
            id: 'old-greeting',
            role: 'assistant',
            content: 'An archived greeting.',
          );
          final legacyStory = {
            'card': _card.toSnapshot(),
            'player': 'Player',
            'conversation': {
              'messages': [ConversationCodec.message(oldGreeting)],
              'history': [
                {'role': oldGreeting.role, 'content': oldGreeting.content},
              ],
            },
            'bound': true,
          };
          final restored = restore({
            ...agent.snapshotWorkspaceConversation(),
            'roleplay': {
              'binding': _binding(_card).withStory(active: true).toSnapshot(),
              'enabled': true,
              'stories': [legacyStory],
            },
          });
          expect(restored.roleplayEnabled, isTrue);
          expect(restored.messages.first.content, 'Original task');
          final saved = restored.snapshotWorkspaceConversation();
          expect(saved['roleplay'], {
            'binding': _binding(_card).toSnapshot(),
            'enabled': true,
          });
          expect(jsonEncode(saved), isNot(contains(oldGreeting.content)));
          expect(
            restored.startRoleplayOpening(0, clearExisting: false),
            isFalse,
          );
          final replacement = AiRoleplayCard.fromFields({'name': 'Noor'});
          expect(restored.bindRoleplay(_binding(replacement)), isTrue);
          expect(restored.removeRoleplay(), isTrue);
          final reloaded = restore(restored.snapshotWorkspaceConversation());
          expect(reloaded.messages.first.content, 'Original task');
          expect(reloaded.roleplayBinding, isNull);
        },
      );
    });
  }
}

AiRoleplayBinding _binding(AiRoleplayCard card) => AiRoleplayBinding(
  card: card,
  playerName: 'Player',
  includeProfile: true,
  includeWorldBook: true,
  includeAdvancedPrompts: true,
);

final _card = AiRoleplayCard.fromFields({
  'name': 'Lan',
  'description': '{{char}} repairs clocks.',
  'personality': 'Quiet and meticulous.',
  'creator_notes': 'Author notes stay local.',
  'scenario': 'It is close to midnight.',
  'first_mes': 'Welcome to the shop.',
  'alternate_greetings': ['Good evening, {{user}}.'],
  'mes_example': 'Lan: A clock never forgets.',
  'character_book': {
    'entries': [
      {
        'keys': ['orchard'],
        'content': 'The trees bloom every winter.',
      },
      {
        'constant': true,
        'enabled': false,
        'content': 'A disabled world entry.',
      },
    ],
  },
  'system_prompt': 'Use a fairy-tale rhythm.',
  'post_history_instructions': 'End on a quiet note.',
});

Map<String, Object?> _decodeObject(String json) =>
    jsonDecode(json) as Map<String, Object?>;

String _systemPrompt(Map<String, Object?> request, AiApiProtocol protocol) =>
    switch (protocol) {
      AiApiProtocol.openAiResponses => request['instructions'] as String,
      AiApiProtocol.openAiChatCompletions =>
        ((request['messages'] as List).first as Map)['content'] as String,
    };

Map<String, Object?> _response(AiApiProtocol protocol) => switch (protocol) {
  AiApiProtocol.openAiResponses => {
    'output': [
      {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': 'Reply'},
        ],
      },
    ],
  },
  AiApiProtocol.openAiChatCompletions => {
    'choices': [
      {
        'message': {'content': 'Reply'},
      },
    ],
  },
};
