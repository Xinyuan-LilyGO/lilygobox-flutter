import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:material_ui/material_ui.dart';

Future<List<({String name, String text})>> _inputs() async {
  final mixed = List.generate(
    2000,
    (index) => '$index 中文输入 English 🌿 é العربية 文本保持完整。\n\n',
  ).join();
  final inputs = [
    (name: 'mixed', text: mixed),
    (
      name: 'chinese',
      text: mixed.replaceAll(RegExp(r'[^\u4e00-\u9fff\n]'), '中'),
    ),
    (name: 'ascii', text: mixed.replaceAll(RegExp(r'[^\n]'), 'a')),
  ];
  const path = String.fromEnvironment('COMPOSER_PERF_PAYLOAD');
  if (path.isEmpty) return inputs;
  final payload = jsonDecode(await File(path).readAsString()) as Map;
  final workflow = payload['workflow'] as Map;
  final sessions = (workflow['sessions'] as List).cast<Map>();
  final session = sessions.firstWhere(
    (candidate) => candidate['id'] == workflow['selectedId'],
    orElse: () => sessions.first,
  );
  final messages = ((session['conversation'] as Map)['messages'] as List)
      .cast<Map>();
  final contents = [
    for (final message in messages) message['content'] as String,
  ];
  return [
    (
      name: 'real_longest',
      text: contents.reduce(
        (first, second) => first.length >= second.length ? first : second,
      ),
    ),
    (name: 'real_conversation', text: contents.join('\n\n')),
    ...inputs,
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile native long input layout phases and font fallback', (
    tester,
  ) async {
    final input = TextEditingController();
    final focus = FocusNode();
    final inputs = (await tester.runAsync(_inputs))!;
    final preferences = (await tester.runAsync(AppPreferences.load))!;
    expect(preferences.error, isNull);
    final theme = ThemeProvider(preferences: preferences);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 770,
            child: TextField(
              controller: input,
              focusNode: focus,
              minLines: 2,
              maxLines: 8,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ),
      ),
    );
    final style = tester.widget<EditableText>(find.byType(EditableText)).style;
    final phaseInput = TextEditingController();
    final results = <Map<String, Object?>>[];
    Future<void> frames([int count = 2]) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }

    try {
      await frames(30);
      for (final entry in inputs) {
        for (final font in [
          'default',
          if (theme.fontFamily != null) 'current',
          'fallback',
          'cjk_primary',
        ]) {
          final fontStyle = switch (font) {
            'current' => style.copyWith(fontFamily: theme.fontFamily),
            'fallback' => style.copyWith(
              fontFamilyFallback: const [
                'Microsoft YaHei UI',
                'Segoe UI',
                'Segoe UI Emoji',
              ],
            ),
            'cjk_primary' => style.copyWith(
              fontFamily: 'Microsoft YaHei UI',
              fontFamilyFallback: const ['Segoe UI', 'Segoe UI Emoji'],
            ),
            _ => style,
          };
          final key = '${entry.name}_$font';
          debugPrint('COMPOSER_CPU_START: $key');
          await frames(2);
          for (var iteration = 0; iteration < 3; iteration++) {
            final content = '${entry.text}中$iteration';
            phaseInput.value = TextEditingValue(
              text: content,
              selection: TextSelection.collapsed(offset: content.length),
              composing: TextRange(
                start: content.length - 2,
                end: content.length,
              ),
            );
            final span = phaseInput.buildTextSpan(
              context: tester.element(find.byType(TextField)),
              style: fontStyle,
              withComposing: true,
            );
            final painter = TextPainter(
              text: span,
              textDirection: TextDirection.ltr,
              locale: const Locale('zh', 'CN'),
            );
            final watch = Stopwatch()..start();
            painter.layout(minWidth: 770, maxWidth: 770);
            final layout = watch.elapsedMicroseconds;
            watch.reset();
            painter.getBoxesForSelection(
              TextSelection(
                baseOffset: content.length - 2,
                extentOffset: content.length,
              ),
            );
            final range = watch.elapsedMicroseconds;
            watch.reset();
            painter.getOffsetForCaret(
              TextPosition(offset: content.length),
              const Rect.fromLTWH(0, 0, 2, 21),
            );
            final caret = watch.elapsedMicroseconds;
            final recorder = ui.PictureRecorder();
            watch.reset();
            painter.paint(Canvas(recorder), Offset.zero);
            final paint = watch.elapsedMicroseconds;
            recorder.endRecording().dispose();
            painter.dispose();
            results.add({
              'key': key,
              'characters': content.length,
              'iteration': iteration,
              'layout_microseconds': layout,
              'range_microseconds': range,
              'caret_microseconds': caret,
              'paint_microseconds': paint,
            });
            await frames(2);
          }
          debugPrint('COMPOSER_CPU_DONE: $key');
          await frames(4);
        }
      }
      binding.reportData = {
        'fixture': {
          'preference_font_choice': theme.fontChoice,
          'preference_font_family': theme.fontFamily,
          'default_text_field_family': style.fontFamily,
          'default_text_field_fallback': style.fontFamilyFallback,
        },
        'text_painter_phases': results,
      };
      await frames(80);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      phaseInput.dispose();
      input.dispose();
      focus.dispose();
      theme.dispose();
      preferences.dispose();
    }
  });
}
