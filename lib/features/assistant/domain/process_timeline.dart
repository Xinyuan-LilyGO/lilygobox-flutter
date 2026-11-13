import 'models.dart';

/// 展示条目保留稳定标识，使执行状态更新后仍保持用户的展开选择。
class AiProcessEntry {
  const AiProcessEntry(this.id, this.event, {this.events = const []});

  final String id;
  final AiProcessEvent event;
  final List<AiProcessEvent> events;
}

/// 将同次调用的准备、批准、执行与结果归为一个操作，保留完整过程。
List<AiProcessEntry> buildAiProcessTimeline(List<AiProcessEvent> events) {
  final entries = <AiProcessEntry>[];
  final operationIndices = <String, int>{};
  for (final (index, event) in events.indexed) {
    final operationId = event.operationId;
    final operation =
        event.type == AiProcessEventType.action ||
        (event.type == AiProcessEventType.status &&
            (event.status == AiResponseStatus.preparingTools ||
                event.status == AiResponseStatus.awaitingUserInput ||
                event.status == AiResponseStatus.awaitingApproval ||
                event.status == AiResponseStatus.executingTools ||
                event.status == AiResponseStatus.accessingWeb));
    if (operation && operationId != null) {
      final previous = operationIndices[operationId];
      final entry = AiProcessEntry(
        'operation-$operationId',
        event,
        events: List.unmodifiable([
          if (previous != null) ...entries[previous].events,
          event,
        ]),
      );
      if (previous == null) {
        operationIndices[operationId] = entries.length;
        entries.add(entry);
      } else {
        entries[previous] = entry;
      }
    } else {
      // 旧记录没有调用标识时保留原顺序，不根据工具名称猜测归属。
      entries.add(AiProcessEntry('event-$index', event));
    }
  }
  return List.unmodifiable(entries);
}
