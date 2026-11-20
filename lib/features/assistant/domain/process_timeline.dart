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
  final groups = <String, List<AiProcessEvent>>{};
  for (final (index, event) in events.indexed) {
    final operationId = event.operationId;
    final id = operationId == null ? 'event-$index' : 'operation-$operationId';
    (groups[id] ??= []).add(event);
  }
  return List.unmodifiable([
    for (final group in groups.entries)
      AiProcessEntry(
        group.key,
        group.value.last,
        events: group.value.last.operationId == null
            ? const []
            : List.unmodifiable(group.value),
      ),
  ]);
}
