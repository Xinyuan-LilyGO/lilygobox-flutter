import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/features/assistant/data/chat_completion_client.dart';
import 'package:lilygobox/features/assistant/data/reasoning_text_filter.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

void main() {
  for (final sample in [
    ('<thinking>Plan</thinking>Answer', 'Plan', 'Answer'),
    (' \n<think>Plan</think>\n\nAnswer', 'Plan', 'Answer'),
    ('<think>One</think> <thinking>Two</thinking>Answer', 'OneTwo', 'Answer'),
    ('<thinking>Incomplete reasoning', 'Incomplete reasoning', ''),
    (
      '<thinking>Check <tag> content</thinking>Answer',
      'Check <tag> content',
      'Answer',
    ),
    (
      'Normal <thinking>example</thinking>',
      '',
      'Normal <thinking>example</thinking>',
    ),
    (
      '\x60\x60\x60xml\n<thinking>example</thinking>\n\x60\x60\x60',
      '',
      '\x60\x60\x60xml\n<thinking>example</thinking>\n\x60\x60\x60',
    ),
    ('<thing>Example', '', '<thing>Example'),
    ('<thi', '', '<thi'),
    ('1 < 2', '', '1 < 2'),
  ]) {
    test('preserves response boundaries: ${sample.$1}', () {
      // Exercise every possible split, including splits inside both tags.
      for (var split = 0; split <= sample.$1.length; split++) {
        final text = StringBuffer();
        final reasoning = StringBuffer();
        final filter = ReasoningTextFilter(
          onText: text.write,
          onReasoning: reasoning.write,
        );
        filter.add(sample.$1.substring(0, split));
        filter.add(sample.$1.substring(split));
        filter.finish();
        expect(text.toString(), sample.$3, reason: 'split=$split');
        expect(reasoning.toString(), sample.$2, reason: 'split=$split');
      }
    });
  }

  for (final protocol in AiApiProtocol.values) {
    for (final streaming in [false, true]) {
      test(
        'filters gateway reasoning in ${protocol.name}, streaming=$streaming',
        () async {
          const raw = '<thinking>Inline plan.</thinking>\nAnswer';
          final responses = protocol == AiApiProtocol.openAiResponses;
          final payload = responses
              ? {
                  'output': [
                    {
                      'type': 'reasoning',
                      'summary': [
                        {'type': 'summary_text', 'text': 'Structured.'},
                      ],
                      'encrypted_content': 'opaque',
                    },
                    {
                      'type': 'message',
                      'content': [
                        {'type': 'output_text', 'text': raw},
                      ],
                    },
                  ],
                }
              : {
                  'choices': [
                    {
                      'message': {
                        'content': raw,
                        'reasoning_content': 'Structured.',
                      },
                    },
                  ],
                };
          final events = <Map<String, Object?>>[
            if (responses)
              {
                'type': 'response.reasoning_summary_text.delta',
                'delta': 'Structured.',
              }
            else
              {
                'choices': [
                  {
                    'delta': {'reasoning_content': 'Structured.'},
                  },
                ],
              },
            for (final character in raw.split(''))
              if (responses)
                {'type': 'response.output_text.delta', 'delta': character}
              else
                {
                  'choices': [
                    {
                      'delta': {'content': character},
                    },
                  ],
                },
            if (responses) {'type': 'response.completed', 'response': payload},
          ];
          final client = ChatCompletionClient(
            client: MockClient(
              (_) async => http.Response(
                streaming
                    ? events
                          .map((event) => 'data: ${jsonEncode(event)}\n\n')
                          .join()
                    : jsonEncode(payload),
                200,
                headers: {
                  'content-type': streaming
                      ? 'text/event-stream'
                      : 'application/json',
                },
              ),
            ),
          );
          addTearDown(client.close);
          final text = <String>[];
          final reasoning = <String>[];
          final completion = await client.complete(
            configuration: AiServiceConfiguration(
              protocol: protocol,
              model: 'gpt-6.1-sol',
            ),
            apiKey: 'key',
            messages: const [],
            tools: const [],
            onTextDelta: text.add,
            onReasoningDelta: reasoning.add,
          );
          expect(text.join(), 'Answer');
          expect(completion.text, text.join());
          expect(reasoning.join(), 'Structured.Inline plan.');
          expect(completion.reasoning, reasoning.join());
          expect(text.join(), isNot(contains('<thinking>')));
          if (responses) {
            expect(
              completion.responseItems.first['encrypted_content'],
              'opaque',
            );
            expect(
              ((completion.responseItems.last['content'] as List).first
                  as Map)['text'],
              raw,
            );
          }
        },
      );
    }
  }

  test(
    'Responses completion supplies text omitted from deltas without leaking tags',
    () async {
      final payload = {
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '<think>Plan</think>Answer'},
            ],
          },
        ],
      };
      final client = ChatCompletionClient(
        client: MockClient(
          (_) async => http.Response(
            'data: ${jsonEncode({'type': 'response.completed', 'response': payload})}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      addTearDown(client.close);
      final text = StringBuffer();
      final reasoning = StringBuffer();
      final completion = await client.complete(
        configuration: AiServiceConfiguration(
          protocol: AiApiProtocol.openAiResponses,
        ),
        apiKey: 'key',
        messages: const [],
        tools: const [],
        onTextDelta: text.write,
        onReasoningDelta: reasoning.write,
      );
      expect(text.toString(), 'Answer');
      expect(reasoning.toString(), 'Plan');
      expect(completion.text, text.toString());
    },
  );
}
