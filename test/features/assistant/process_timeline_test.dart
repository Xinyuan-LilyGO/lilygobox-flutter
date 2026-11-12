import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/process_timeline.dart';

AiProcessEvent running(String id, {String name = 'read_file'}) =>
    AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: const Duration(seconds: 1),
      status: AiResponseStatus.executingTools,
      operationId: id,
      toolName: name,
    );

AiProcessEvent completed(String? id, {bool success = true}) => AiProcessEvent(
  type: AiProcessEventType.action,
  elapsed: const Duration(seconds: 2),
  operationId: id,
  action: AiProcessingStep(
    name: 'read_file',
    arguments: {'path': 'a.txt'},
    succeeded: success,
    output: success ? 'file contents' : 'permission denied',
  ),
);

void main() {
  test(
    'one call updates one row without changing its identity or raw events',
    () {
      final start = running('one');
      final finish = completed('one');
      final events = [start, finish];
      final before = buildAiProcessTimeline([start]);
      final after = buildAiProcessTimeline(events);
      expect(after, hasLength(1));
      expect(after.single.id, before.single.id);
      expect(after.single.event, same(finish));
      expect(after.single.events, [start, finish]);
      expect(events, [start, finish]);
    },
  );

  test('repeated calls to the same tool stay separate', () {
    final result = buildAiProcessTimeline([
      running('one'),
      completed('one'),
      running('two'),
      completed('two'),
    ]);
    expect(result, hasLength(2));
    expect(result.map((entry) => entry.id).toSet(), hasLength(2));
  });

  test('approval, reasoning and retries remain in chronological order', () {
    const approval = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration.zero,
      status: AiResponseStatus.awaitingApproval,
    );
    const thought = AiProcessEvent(
      type: AiProcessEventType.reasoning,
      elapsed: Duration.zero,
      text: 'Inspect the file.',
    );
    const retry = AiProcessEvent(
      type: AiProcessEventType.retry,
      elapsed: Duration(seconds: 3),
      retry: AiRequestRetry(1, 'error'),
    );
    final result = buildAiProcessTimeline([
      thought,
      approval,
      running('one'),
      completed('one', success: false),
      retry,
    ]);
    expect(result, hasLength(4));
    expect(result[0].event, same(thought));
    expect(result[1].event, same(approval));
    expect(result[2].event.action!.succeeded, isFalse);
    expect(result[3].event, same(retry));
  });

  test('legacy records without call IDs are not merged by tool name', () {
    const old = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration.zero,
      status: AiResponseStatus.executingTools,
      toolName: 'read_file',
    );
    expect(
      buildAiProcessTimeline([old, completed(null), old, completed(null)]),
      hasLength(4),
    );
  });

  test('an interrupted operation and its stop record remain visible', () {
    const stop = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration(seconds: 2),
      status: AiResponseStatus.stopped,
    );
    final result = buildAiProcessTimeline([running('one'), stop]);
    expect(result, hasLength(2));
    expect(result.last.event, same(stop));
  });

  test('web execution and result use the same grouping rule', () {
    const start = AiProcessEvent(
      type: AiProcessEventType.status,
      elapsed: Duration.zero,
      status: AiResponseStatus.accessingWeb,
      toolName: 'read_webpage',
      operationId: 'web',
    );
    final result = AiProcessEvent(
      type: AiProcessEventType.action,
      elapsed: const Duration(seconds: 2),
      operationId: 'web',
      action: AiProcessingStep(
        name: 'read_webpage',
        arguments: {'url': 'https://example.com'},
        succeeded: true,
        output: 'Page text',
      ),
    );
    expect(buildAiProcessTimeline([start, result]).single.event, same(result));
  });

  test(
    'preparation and approval belong to the same operation, retries stay outside',
    () {
      const prepare = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        operationId: 'one',
        toolName: 'read_file',
        status: AiResponseStatus.preparingTools,
      );
      const approval = AiProcessEvent(
        type: AiProcessEventType.status,
        elapsed: Duration.zero,
        operationId: 'one',
        toolName: 'read_file',
        status: AiResponseStatus.awaitingApproval,
      );
      const retry = AiProcessEvent(
        type: AiProcessEventType.retry,
        elapsed: Duration(seconds: 3),
        retry: AiRequestRetry(1, 'failure'),
      );
      final start = running('one');
      final finish = completed('one');
      final original = [prepare, approval, start, finish, retry];
      final result = buildAiProcessTimeline(original);
      expect(result, hasLength(2));
      expect(result.first.events, [prepare, approval, start, finish]);
      expect(result.first.event, same(finish));
      expect(result.last.event, same(retry));
      expect(original, hasLength(5));
    },
  );
}
