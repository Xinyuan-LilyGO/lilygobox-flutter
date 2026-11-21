import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/context_compaction.dart';

void main() {
  test('mid-turn compaction keeps the original request and complete tool exchanges', () {
    final history = <Map<String, Object?>>[
      {'role': 'user', 'content': 'Keep this exact request'},
      {'role': 'assistant', 'content': 'Earlier current-turn work. ' * 256},
      {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'first',
            'function': {'name': 'test_tool', 'arguments': '{}'},
          },
          {
            'id': 'second',
            'function': {'name': 'test_tool', 'arguments': '{}'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'first', 'content': 'First result'},
      {'role': 'tool', 'tool_call_id': 'second', 'content': 'Second result'},
      {'role': 'assistant', 'content': 'Current checkpoint'},
    ];
    final plan = planContextCompaction(
      history,
      1000,
      threshold: 850,
      underPressure: true,
      previousSummary: 'Prior summary',
    )!;
    expect(plan.retainedUserIndex, 0);
    expect(plan.cut, 2);
    expect(plan.assistantTail, isNull);
    final records = plan.batches.expand((batch) => batch).join('\n');
    expect(records, contains('Prior summary'));
    expect(records, contains('Earlier current-turn work.'));
    expect(records, isNot(contains('Keep this exact request')));
    expect(records, isNot(contains('First result')));

    final tight = planContextCompaction(
      history,
      1000,
      threshold: 160,
      underPressure: true,
      previousSummary: '',
    )!;
    expect(tight.cut, 5);
    final tightRecords = tight.batches.expand((batch) => batch).join('\n');
    expect(tightRecords, contains('First result'));
    expect(tightRecords, contains('Second result'));
  });

  test('a lone oversized user request is never replaced with a summary', () {
    expect(
      planContextCompaction(
        [
          {'role': 'user', 'content': 'Keep this exact request. ' * 1000},
        ],
        1000,
        threshold: 850,
        underPressure: true,
        previousSummary: '',
      ),
      isNull,
    );
  });
}
