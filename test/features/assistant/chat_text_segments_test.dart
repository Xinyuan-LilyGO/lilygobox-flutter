import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_text_segments.dart';

void main() {
  group('splitChatText', () {
    test('preserves empty and short text without changing its whitespace', () {
      for (final text in ['', 'hello', '  hello\t ', '\n', 'one\n\ntwo\n']) {
        expect(splitChatText(text), [text]);
      }
    });

    test('defaults to a target of 2048 UTF-16 code units', () {
      final first = 'first line\n${'x' * 2037}';
      final text = '$first\nlast';

      expect(first.length, 2048);
      expect(splitChatText(text), [first, 'last']);
    });

    test('uses the last newline at or before the target', () {
      expect(splitChatText('ab\ncd\nef\ngh', targetLength: 8), [
        'ab\ncd\nef',
        'gh',
      ]);
      expect(splitChatText('ab\ncd\nef\ngh', targetLength: 7), [
        'ab\ncd',
        'ef\ngh',
      ]);
    });

    test('keeps a logical line longer than the target intact', () {
      final longLine = 'line without separators ' * 1000;

      expect(splitChatText(longLine, targetLength: 32), [longLine]);
      expect(splitChatText('a\n$longLine\nz', targetLength: 32), [
        'a',
        longLine,
        'z',
      ]);
    });

    test('windows long text without requiring newline separators', () {
      final text = '${'one very long logical line ' * 300}尾';
      final segments = splitChatTextForWindow(text, targetLength: 32);

      expect(segments.length, greaterThan(10));
      expect(segments.join(), text);
      expect(segments.every((segment) => segment.length <= 32), isTrue);
    });

    test(
      'prefers whitespace boundaries without dropping source characters',
      () {
        final text = 'word-boundary ${'several words stay intact ' * 20}tail';
        final segments = splitChatTextForWindow(text, targetLength: 32);

        expect(segments.join(), text);
        expect(segments.length, greaterThan(2));
        expect(
          segments
              .take(segments.length - 1)
              .every((segment) => RegExp(r'\s$').hasMatch(segment)),
          isTrue,
        );
      },
    );

    test('keeps grapheme clusters intact while windowing long text', () {
      final text = '${'👩🏽‍💻🇭🇰e\u0301' * 100}末尾';
      final segments = splitChatTextForWindow(text, targetLength: 32);

      expect(segments.join(), text);
      expect(segments.every((segment) => segment.length <= 32), isTrue);
      expect(
        segments.fold(0, (count, segment) => count + segment.characters.length),
        text.characters.length,
      );
    });

    test('retains leading, repeated, and trailing newlines exactly', () {
      const text = '\n\nfirst\n\nsecond\n\n';

      for (var target = 1; target <= text.length; target++) {
        expect(splitChatText(text, targetLength: target).join('\n'), text);
      }
      expect(splitChatText('a\n', targetLength: 1), ['a', '']);
      expect(splitChatText('\nlong', targetLength: 1), ['', 'long']);
    });

    test('preserves CRLF separators and standalone carriage returns', () {
      const text = 'one\r\ntwo\r\n\r\nlast\r';

      expect(splitChatText('one\r\ntwo', targetLength: 4), ['one\r', 'two']);
      expect(splitChatText('one\rtwo\rlast', targetLength: 2), [
        'one\rtwo\rlast',
      ]);
      for (var target = 1; target <= text.length; target++) {
        expect(splitChatText(text, targetLength: target).join('\n'), text);
      }
    });

    test(
      'keeps emoji, surrogate pairs, and combining sequences in their lines',
      () {
        final lines = [
          '😀' * 30,
          'e\u0301' * 30,
          '👩🏽‍💻' * 30,
          '🇭🇰' * 30,
          'العَرَبِيَّة' * 30,
        ];
        final text = lines.join('\n');

        for (var target = 1; target <= 40; target++) {
          expect(splitChatText(text, targetLength: target), lines);
        }
      },
    );

    test('leaves other Unicode line separators within their logical line', () {
      const text = 'one\u2028two\u2029three';

      expect(splitChatText(text, targetLength: 2), [text]);
    });

    test('reconstructs mixed text across many line lengths and targets', () {
      final random = Random(1731);
      const atoms = ['x', '中文', '😀', 'e\u0301', '👩🏽‍💻', '\t', '\r'];
      final text = List.generate(120, (line) {
        final atomCount = random.nextInt(80);
        return [
          for (var atom = 0; atom < atomCount; atom++)
            atoms[random.nextInt(atoms.length)],
        ].join();
      }).join('\n');

      for (final target in [1, 2, 3, 7, 31, 128, 2048, text.length + 1]) {
        final segments = splitChatText(text, targetLength: target);

        expect(segments, isNotEmpty);
        expect(segments.join('\n'), text);
        expect(
          segments.every(
            (segment) => segment.length <= target || !segment.contains('\n'),
          ),
          isTrue,
        );
      }
    });

    test('rejects nonpositive targets even for empty text', () {
      for (final target in [0, -1, -2048]) {
        for (final text in ['', 'line\nanother line']) {
          expect(
            () => splitChatText(text, targetLength: target),
            throwsRangeError,
          );
        }
      }
    });
  });
}
