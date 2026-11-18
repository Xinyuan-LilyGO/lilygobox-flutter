import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

void main() {
  test('completion time round trips independently from creation time', () {
    final created = DateTime.utc(2026, 11, 18, 1);
    final finished = created.add(const Duration(minutes: 2));
    final message = AiMessage(
      id: 'reply',
      role: 'assistant',
      content: 'Done',
      createdAt: created,
      finishedAt: finished,
    );
    final restored = ConversationCodec.read(ConversationCodec.message(message));
    expect(restored.createdAt, created);
    expect(restored.finishedAt, finished);
    expect(restored.copyWith(content: 'Edited').finishedAt, finished);
    expect(restored.copyWith(clearFinishedAt: true).finishedAt, isNull);
  });

  test('messages missing current fields are rejected without migration', () {
    final encoded = ConversationCodec.message(
      const AiMessage(id: 'reply', role: 'assistant', content: 'Done'),
    );
    for (final field in [
      'createdAt',
      'finishedAt',
      'steps',
      'retries',
      'attachments',
      'events',
    ]) {
      final incomplete = {...encoded}..remove(field);
      expect(() => ConversationCodec.read(incomplete), throwsFormatException);
    }
  });

  test('current messages permit explicit null times before completion', () {
    final encoded = ConversationCodec.message(
      const AiMessage(id: 'pending', role: 'assistant', content: ''),
    );
    final restored = ConversationCodec.read(encoded);
    expect(restored.createdAt, isNull);
    expect(restored.finishedAt, isNull);
  });
}
