import 'dart:ffi' as ffi;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/empty_line_selection.dart';
import 'package:material_ui/material_ui.dart';

class _InputFixture extends StatelessWidget {
  const _InputFixture({
    required this.input,
    required this.focus,
    required this.scroll,
    required this.outer,
  });

  final TextEditingController input;
  final FocusNode focus;
  final ScrollController scroll;
  final bool outer;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: const ValueKey('editing-input'),
      controller: input,
      focusNode: focus,
      scrollController: outer ? null : scroll,
      scrollPhysics: outer ? const NeverScrollableScrollPhysics() : null,
      minLines: 2,
      maxLines: outer ? null : 8,
      selectionWidthStyle: ui.BoxWidthStyle.tight,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(fontSize: 14, height: 1.5),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isCollapsed: true,
      ),
    );
    return EmptyLineSelection(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 168),
        child: Scrollbar(
          controller: scroll,
          child: ScrollConfiguration(
            behavior: const AppScrollBehavior(scrollbars: false),
            child: outer
                ? SingleChildScrollView(
                    controller: scroll,
                    primary: false,
                    child: field,
                  )
                : field,
          ),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile inner and outer long input editing and composition', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final handle = (await tester.runAsync(
      () =>
          const MethodChannel('lilygobox/window_layout')
              .invokeMethod<int>('getWindowHandle'),
    ))!;
    final isMaximized = ffi.DynamicLibrary.open('user32.dll')
        .lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
          'IsZoomed',
        );
    final input = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    final outer = ValueNotifier(false);
    final semantics = tester.ensureSemantics();
    final text = List.generate(
      2000,
      (index) => '$index 中文输入 English 🌿 é العربية 文本保持完整。\n\n',
    ).join();
    final results = <Map<String, Object?>>[];
    Future<void> frames([int count = 16]) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 770,
                child: ValueListenableBuilder(
                  valueListenable: outer,
                  builder: (context, useOuter, _) => _InputFixture(
                    input: input,
                    focus: focus,
                    scroll: scroll,
                    outer: useOuter,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await frames();
      if (isMaximized(handle) == 0) {
        await tester.runAsync(
          () =>
              const MethodChannel('lilygobox/window_layout')
                  .invokeMethod<void>('toggleMaximize'),
        );
      }
      await frames(60);
      expect(isMaximized(handle), isNot(0));
      binding.reportData = {
        'fixture': {
          'characters': text.length,
          'input_width': 770,
          'viewport_height': 168,
          'physical_width': tester.view.physicalSize.width,
          'physical_height': tester.view.physicalSize.height,
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'refresh_rate': tester.view.display.refreshRate,
          'native_maximized': isMaximized(handle) != 0,
          'semantics_enabled': true,
        },
      };
      for (final variant in ['inner_standard', 'outer_standard']) {
        outer.value = variant != 'inner_standard';
        input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        await frames();
        focus.requestFocus();
        await frames();
        for (final operation in [
          'plain_append',
          'composing_append',
          'delete',
        ]) {
          final base = operation == 'delete' ? '$text中中中中中中中中中中' : text;
          input.value = TextEditingValue(
            text: base,
            selection: TextSelection.collapsed(offset: base.length),
          );
          await frames();
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await frames();
          final editor = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          final key = '${variant}_$operation';
          final latency = <int>[];
          debugPrint('COMPOSER_CPU_START: $key');
          await frames(2);
          await binding.watchPerformance(() async {
            for (var edit = 0; edit < 10; edit++) {
              final next = operation == 'delete'
                  ? input.text.substring(0, input.text.length - 1)
                  : '${input.text}中';
              final composing = operation == 'composing_append'
                  ? TextRange(start: next.length - 1, end: next.length)
                  : TextRange.empty;
              final watch = Stopwatch()..start();
              editor.updateEditingValue(
                TextEditingValue(
                  text: next,
                  selection: TextSelection.collapsed(offset: next.length),
                  composing: composing,
                ),
              );
              await tester.pump();
              latency.add(watch.elapsedMicroseconds);
              expect(input.text, next);
              expect(input.value.composing, composing);
              await frames(1);
            }
            await frames(18);
          }, reportKey: key);
          results.add({
            'key': key,
            'update_through_layout_microseconds': latency,
            'foreground_painter_preserved':
                editor.renderEditable.foregroundPainter != null,
            'composing_range': [
              input.value.composing.start,
              input.value.composing.end,
            ],
          });
          debugPrint('COMPOSER_CPU_DONE: $key');
          await frames(4);
        }
      }
      binding.reportData!['editing_latency'] = results;
      final style = tester
          .widget<EditableText>(find.byType(EditableText))
          .style;
      final textPainterResults = <Map<String, Object?>>[];
      final phaseInput = TextEditingController();
      for (final rich in [false, true]) {
        final key = 'text_painter_${rich ? 'composing' : 'plain'}';
        debugPrint('COMPOSER_CPU_START: $key');
        await frames(2);
        for (var iteration = 0; iteration < 5; iteration++) {
          final content = '$text中$iteration';
          phaseInput.value = TextEditingValue(
            text: content,
            selection: TextSelection.collapsed(offset: content.length),
            composing: rich
                ? TextRange(start: content.length - 2, end: content.length)
                : TextRange.empty,
          );
          final span = phaseInput.buildTextSpan(
            context: tester.element(
              find.byKey(const ValueKey('editing-input')),
            ),
            style: style,
            withComposing: true,
          );
          final textPainter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          );
          final watch = Stopwatch()..start();
          textPainter.layout(minWidth: 770, maxWidth: 770);
          final layout = watch.elapsedMicroseconds;
          watch.reset();
          textPainter.getBoxesForSelection(
            TextSelection(
              baseOffset: content.length - 2,
              extentOffset: content.length,
            ),
          );
          final range = watch.elapsedMicroseconds;
          watch.reset();
          textPainter.getOffsetForCaret(
            TextPosition(offset: content.length),
            const Rect.fromLTWH(0, 0, 2, 21),
          );
          final caret = watch.elapsedMicroseconds;
          final recorder = ui.PictureRecorder();
          watch.reset();
          textPainter.paint(Canvas(recorder), Offset.zero);
          final paint = watch.elapsedMicroseconds;
          recorder.endRecording().dispose();
          textPainter.dispose();
          textPainterResults.add({
            'key': key,
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
      phaseInput.dispose();
      binding.reportData!['text_painter_phases'] = textPainterResults;
      await frames(80);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      input.dispose();
      focus.dispose();
      scroll.dispose();
      outer.dispose();
    }
  });
}
