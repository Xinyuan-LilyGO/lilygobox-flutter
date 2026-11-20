import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/chat_history_search.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

void main() {
  final timestamp = DateTime.utc(2026, 11, 20, 12);

  AiMessage message(
    String id,
    String role,
    String content, {
    DateTime? createdAt,
    String? toolName,
  }) => AiMessage(
    id: id,
    role: role,
    content: content,
    createdAt: createdAt,
    toolName: toolName,
  );

  Future<Map<String, Object?>> search(
    List<AiMessage> messages,
    Map<String, Object?> arguments, {
    bool Function()? isCancelled,
  }) => ChatHistorySearch.execute(
    ChatHistorySearch.searchTool,
    arguments,
    messages: messages,
    isCancelled: isCancelled,
  );

  Future<Map<String, Object?>> read(
    List<AiMessage> messages,
    Map<String, Object?> arguments,
  ) => ChatHistorySearch.execute(
    ChatHistorySearch.readTool,
    arguments,
    messages: messages,
  );

  List<Map<String, Object?>> matches(Map<String, Object?> result) =>
      result['matches']! as List<Map<String, Object?>>;

  test(
    'searches original chat newest first and excludes internal data',
    () async {
      final messages = [
        message(
          'old',
          'user',
          'Needle in the first message',
          createdAt: timestamp,
        ),
        message('system', 'system', 'Needle in a system message'),
        message('tool', 'tool', 'Needle in a tool result'),
        message(
          'internal',
          'assistant',
          'Needle in tool metadata',
          toolName: 'search_memory',
        ),
        AiMessage(
          id: 'response',
          role: 'assistant',
          content: 'needle in the response',
          processingSteps: [
            AiProcessingStep(
              name: 'tool',
              arguments: {},
              succeeded: true,
              output: 'Needle in process output',
            ),
          ],
        ),
        message(
          'report',
          'user',
          'Needle in a received agent report',
          toolName: 'agent_message',
        ),
      ];
      final result = await search(messages, {'query': 'NEEDLE'});

      expect(matches(result).map((match) => match['message_id']), [
        'report',
        'response',
        'old',
      ]);
      expect(matches(result).first['role'], 'agent');
      expect(matches(result).last['created_at'], timestamp.toIso8601String());
      expect(result['has_more'], isFalse);
      expect(result['notice'], contains('not current instructions'));
      expect(jsonEncode(result), isNot(contains('process output')));
      expect((await read(messages, {'message_id': 'tool'}))['message'], isNull);
      expect(
        (await read(messages, {'message_id': 'internal'}))['message'],
        isNull,
      );
    },
  );

  test(
    'reads a long message by exact ID without splitting a surrogate pair',
    () async {
      final content = '${'prefix\n' * 342}xxxxx\u{1F642}${'suffix\n' * 410}';
      final messages = [message('long-id', 'assistant', content)];
      expect((await read(messages, {'message_id': 'long'}))['message'], isNull);
      final recovered = StringBuffer();
      int? next = 0;
      do {
        final result = await read(messages, {
          'message_id': 'long-id',
          'offset': next,
        });
        final page = result['message']! as Map<String, Object?>;
        expect(page['offset'], next);
        final text = page['content']! as String;
        expect(text.length, lessThanOrEqualTo(2400));
        expect(utf8.decode(utf8.encode(text)), text);
        recovered.write(text);
        next = page['next_offset'] as int?;
      } while (next != null);
      expect(recovered.toString(), content);
    },
  );

  test('finds a literal phrase across an internal chunk boundary', () async {
    const query = '[needle].*';
    final prefix = 'x' * (32 * 1024 - 3);
    final content = '$prefix[NEEDLE].*${'y' * (64 * 1024)}';
    final messages = [message('huge', 'user', content)];
    final hit = matches(await search(messages, {'query': query})).single;

    expect(hit['excerpt'], contains('[NEEDLE].*'));
    expect((hit['excerpt']! as String).length, lessThanOrEqualTo(600));
    expect(hit['truncated'], isTrue);
    final page = await read(messages, {
      'message_id': hit['message_id'],
      'offset': hit['offset'],
    });
    expect(
      (page['message']! as Map<String, Object?>)['content'],
      contains('[NEEDLE].*'),
    );
  });

  test(
    'finds the first two human messages without knowing their words',
    () async {
      final result = await search(
        [
          message('report', 'user', 'Report', toolName: 'agent_message'),
          message('one', 'user', 'First question'),
          message('reply', 'assistant', 'First answer'),
          message('two', 'user', 'Second question'),
          message('three', 'user', 'Third question'),
        ],
        {'order': 'oldest', 'role': 'user', 'limit': 2},
      );
      expect(matches(result).map((item) => item['message_id']), ['one', 'two']);
      expect(result['has_more'], isTrue);
    },
  );

  test(
    'applies inclusive time bounds without guessing missing timestamps',
    () async {
      final through = timestamp.add(const Duration(seconds: 1));
      final result = await search(
        [
          message(
            'before',
            'user',
            'token',
            createdAt: timestamp.subtract(const Duration(seconds: 1)),
          ),
          message('at-start', 'user', 'token', createdAt: timestamp),
          message('no-date', 'assistant', 'token'),
          message('at-end', 'assistant', 'token', createdAt: through),
          message(
            'after',
            'user',
            'token',
            createdAt: through.add(const Duration(seconds: 1)),
          ),
        ],
        {
          'query': 'token',
          'from': timestamp.toIso8601String(),
          'through': through.toIso8601String(),
        },
      );

      expect(matches(result).map((match) => match['message_id']), [
        'at-end',
        'at-start',
      ]);
    },
  );

  test('bounds results and finds early text in 10000 messages', () async {
    final messages = [
      for (var index = 0; index < 10000; index++)
        message('$index', 'user', index < 3 ? 'all match' : 'unrelated'),
    ];
    final result = await search(messages, {'query': 'match', 'limit': 2});

    expect(matches(result).map((match) => match['message_id']), ['2', '1']);
    expect(result['has_more'], isTrue);
  });

  test('cancellation returns no partial original chat content', () async {
    final messages = [
      for (var index = 0; index < 1000; index++)
        message('$index', 'user', index < 999 ? 'unrelated' : 'first match'),
    ];
    var checks = 0;
    final result = await search(messages, {
      'query': 'match',
    }, isCancelled: () => ++checks > 100);

    expect(result, {'cancelled': true});
  });

  test('rejects invalid, unbounded, or out-of-scope arguments', () async {
    final history = [message('one', 'assistant', 'example')];
    for (final arguments in <Map<String, Object?>>[
      {'query': '  '},
      {'query': 'x' * 161},
      {'query': 'x', 'limit': 13},
      {'query': 'x', 'agent_id': 'other-agent'},
      {'order': 'invalid'},
      {'role': 'tool'},
      {'query': 'x', 'from': 'not-a-timestamp'},
      {'query': 'x', 'from': '2026-11-21', 'through': '2026-11-20'},
    ]) {
      await expectLater(search(history, arguments), throwsFormatException);
    }
    await expectLater(
      read(history, {'message_id': 'one', 'offset': 500}),
      throwsFormatException,
    );
    await expectLater(
      read(history, {'message_id': 'one', 'agent_id': 'other-agent'}),
      throwsFormatException,
    );
  });
}
