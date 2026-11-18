import 'dart:convert';

import '../domain/models.dart';
import '../domain/reasoning.dart';
import '../domain/web_failure.dart';

abstract final class ConversationCodec {
  static Map<String, Object?> step(AiProcessingStep s) => {
    'name': s.name,
    'arguments': s.arguments,
    'succeeded': s.succeeded,
    'output': s.output,
    'webFailure': s.webFailure?.toJson(),
  };
  static AiProcessingStep readStep(Map s) => AiProcessingStep(
    name: s['name'] as String,
    arguments: Map<String, Object?>.from(s['arguments'] as Map),
    succeeded: s['succeeded'] == true,
    output: s['output'] as String? ?? '',
    webFailure: s['webFailure'] is Map
        ? AiWebFailure(
            AiWebProblem.values.singleWhere(
              (p) => p.name == s['webFailure']['error_code'],
            ),
            url: Uri.tryParse(s['webFailure']['url'] as String? ?? ''),
            statusCode: s['webFailure']['status_code'] as int?,
          )
        : null,
  );
  static Map<String, Object?> message(AiMessage m) => {
    'id': m.id,
    'role': m.role,
    'content': m.content,
    'createdAt': m.createdAt?.toIso8601String(),
    'finishedAt': m.finishedAt?.toIso8601String(),
    'toolName': m.toolName,
    'toolArguments': m.toolArguments,
    'toolDecision': m.toolDecision,
    'elapsed': m.elapsed?.inMicroseconds,
    'model': m.model,
    'effort': m.reasoningEffort?.name,
    'protocol': m.protocol?.name,
    'status': m.status?.name,
    'error': m.requestError?.toString(),
    'steps': m.processingSteps.map(step).toList(),
    'retries': [
      for (final r in m.retries)
        {'attempt': r.attempt, 'error': r.error.toString()},
    ],
    'attachments': [
      for (final a in m.attachments)
        {'name': a.name, 'mime': a.mimeType, 'bytes': base64Encode(a.bytes)},
    ],
    'events': [
      for (final e in m.processEvents)
        {
          'type': e.type.name,
          'elapsed': e.elapsed.inMicroseconds,
          'status': e.status?.name,
          'toolName': e.toolName,
          'operationId': e.operationId,
          'arguments': e.toolArguments,
          'text': e.text,
          'action': e.action == null ? null : step(e.action!),
          'retry': e.retry == null
              ? null
              : {
                  'attempt': e.retry!.attempt,
                  'error': e.retry!.error.toString(),
                },
        },
    ],
  };
  static T? value<T extends Enum>(List<T> values, Object? name) =>
      values.where((v) => v.name == name).firstOrNull;
  static AiResponseStatus? status(Object? name) {
    final s = value(AiResponseStatus.values, name);
    return s == null
        ? null
        : [
            AiResponseStatus.completed,
            AiResponseStatus.failed,
            AiResponseStatus.stopped,
          ].contains(s)
        ? s
        : AiResponseStatus.stopped;
  }

  static AiRequestRetry retry(Map r) =>
      AiRequestRetry(r['attempt'] as int, r['error']?.toString() ?? '');
  static AiMessage read(Map m) {
    if (!m.keys.toSet().containsAll({
          'createdAt',
          'finishedAt',
          'steps',
          'retries',
          'attachments',
          'events',
        }) ||
        m['steps'] is! List ||
        m['retries'] is! List ||
        m['attachments'] is! List ||
        m['events'] is! List) {
      throw const FormatException('Invalid current conversation message');
    }
    return AiMessage(
      id: m['id'] as String,
      role: m['role'] as String,
      content: m['content'] as String,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      finishedAt: DateTime.tryParse(m['finishedAt'] as String? ?? ''),
      toolName: m['toolName'] as String?,
      toolArguments: m['toolArguments'] == null
          ? null
          : Map<String, Object?>.from(m['toolArguments'] as Map),
      toolDecision: m['toolDecision'] as bool?,
      elapsed: m['elapsed'] == null
          ? null
          : Duration(microseconds: m['elapsed'] as int),
      model: m['model'] as String?,
      reasoningEffort: value(AiReasoningEffort.values, m['effort']),
      protocol: value(AiApiProtocol.values, m['protocol']),
      status: status(m['status']),
      requestError: m['error'],
      processingSteps: [for (final s in m['steps'] as List) readStep(s as Map)],
      retries: [for (final r in m['retries'] as List) retry(r as Map)],
      attachments: [
        for (final a in m['attachments'] as List)
          AiImageAttachment(
            name: a['name'] as String,
            bytes: base64Decode(a['bytes'] as String),
            mimeType: a['mime'] as String,
          ),
      ],
      processEvents: [
        for (final e in m['events'] as List)
          AiProcessEvent(
            type: value(AiProcessEventType.values, e['type'])!,
            elapsed: Duration(microseconds: e['elapsed'] as int),
            status: value(AiResponseStatus.values, e['status']),
            toolName: e['toolName'] as String?,
            operationId: e['operationId'] as String?,
            toolArguments: e['arguments'] == null
                ? null
                : Map<String, Object?>.from(e['arguments'] as Map),
            text: e['text'] as String? ?? '',
            action: e['action'] == null ? null : readStep(e['action'] as Map),
            retry: e['retry'] == null ? null : retry(e['retry'] as Map),
          ),
      ],
    );
  }
}
