import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'assistant_test_scope.dart';

class _SpanBuildController extends TextEditingController {
  int spanBuilds = 0;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    spanBuilds++;
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
  }
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late AssistantTestScope scope;
  late _SpanBuildController input;
  late FocusNode focus;
  late ScrollController scroll;
  var outsidePaints = 0;
  var sends = 0;
  final results = <Map<String, Object?>>[];

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    split = SplitViewProvider();
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
    );
    input = _SpanBuildController();
    focus = FocusNode();
    scroll = ScrollController();
    outsidePaints = 0;
    sends = 0;
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
    scroll.dispose();
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    List<AiImageAttachment> attachments = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2560, 1560);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: _PaintProbe(
                  onPaint: () => outsidePaints++,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              SizedBox(
                width: 820,
                child: ChatComposer(
                  input: input,
                  focusNode: focus,
                  scrollController: scroll,
                  theme: theme.themeData,
                  assistant: scope.provider,
                  ready: true,
                  onSend: (_) => sends++,
                  attachments: attachments,
                  onAttachmentsChanged: (_) {},
                  readClipboardImage: () async => null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final selected in [false, true]) {
    testWidgets(
      'long composer scroll retains full text (selected: $selected)',
      (tester) async {
        final text = List.generate(
          2000,
          (index) => '$index 中文输入 English 🌿 é العربية 文本保持完整。\n\n',
        ).join();
        input.value = TextEditingValue(
          text: text,
          selection: selected
              ? TextSelection(baseOffset: 0, extentOffset: text.length)
              : const TextSelection.collapsed(offset: 0),
        );
        await pumpComposer(tester);
        focus.requestFocus();
        await tester.pumpAndSettle();
        scroll.jumpTo(0);
        await tester.pump();
        expect(scroll.position.maxScrollExtent, greaterThan(10000));
        final initialSpanBuilds = input.spanBuilds;
        final initialOutsidePaints = outsidePaints;
        final watch = Stopwatch()..start();
        for (var step = 1; step <= 30; step++) {
          scroll.jumpTo(step * 63.0);
          await tester.pump(const Duration(milliseconds: 16));
        }
        watch.stop();
        results.add({
          'selected': selected,
          'characters': text.length,
          'scroll_frames': 30,
          'wall_microseconds': watch.elapsedMicroseconds,
          'outside_paints': outsidePaints - initialOutsidePaints,
          'span_builds': input.spanBuilds - initialSpanBuilds,
        });
        if (selected &&
            const bool.fromEnvironment('COMPOSER_PERFORMANCE_PROBE')) {
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          final foreground = editable.renderEditable.foregroundPainter;
          editable.renderEditable.foregroundPainter = null;
          await tester.pump();
          final withoutHighlight = Stopwatch()..start();
          for (var step = 1; step <= 30; step++) {
            scroll.jumpTo(step * 63.0);
            await tester.pump(const Duration(milliseconds: 16));
          }
          withoutHighlight.stop();
          results.add({
            'selected': true,
            'empty_line_highlight': false,
            'characters': text.length,
            'scroll_frames': 30,
            'wall_microseconds': withoutHighlight.elapsedMicroseconds,
          });
          editable.renderEditable.foregroundPainter = foreground;
        }
        expect(input.text, text);
        expect(
          input.selection,
          selected
              ? TextSelection(baseOffset: 0, extentOffset: text.length)
              : const TextSelection.collapsed(offset: 0),
        );
        expect(input.spanBuilds, initialSpanBuilds);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'long composer keeps wheel scrolling editing IME and undo intact',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final text = List.generate(
        1000,
        (index) => '$index 中文 English 🌿 é العربية\n\n',
      ).join();
      input.value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpComposer(tester);
      focus.requestFocus();
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('ai-input-scrollbar'));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(field),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(scroll.offset, greaterThan(0));
      expect(input.text, text);
      final midpoint = text.indexOf('500 中文') + 4;
      input.selection = TextSelection.collapsed(offset: midpoint);
      await tester.pump();
      final composingText = text.replaceRange(midpoint, midpoint, '中文');
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: composingText,
          selection: TextSelection.collapsed(offset: midpoint + 2),
          composing: TextRange(start: midpoint, end: midpoint + 2),
        ),
      );
      await tester.pump();
      expect(input.text, composingText);
      expect(
        input.value.composing,
        TextRange(start: midpoint, end: midpoint + 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sends, 0);
      tester.testTextInput.updateEditingValue(
        input.value.copyWith(composing: TextRange.empty),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final committed = input.value;
      tester.testTextInput.updateEditingValue(
        committed.copyWith(
          text: '${committed.text}undo-check',
          selection: TextSelection.collapsed(
            offset: committed.text.length + 10,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(input.text, committed.text);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(input.selection.textInside(input.text), committed.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('composer reveals the caret at both document ends', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(400, (index) => 'Line $index 中文内容\n').join();
    input.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await pumpComposer(tester);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(
      find.byKey(const ValueKey('ai-input-scrollbar')),
    );
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    Future<void> documentBoundary(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final caret = editable.renderEditable.getLocalRectForCaret(
        input.selection.extent,
      );
      final center = editable.renderEditable.localToGlobal(caret.center);
      expect(viewport.inflate(1).contains(center), isTrue);
    }

    await documentBoundary(LogicalKeyboardKey.end);
    expect(input.selection.extentOffset, text.length);
    expect(scroll.offset, greaterThan(1000));
    await documentBoundary(LogicalKeyboardKey.home);
    expect(input.selection.extentOffset, 0);
    expect(scroll.offset, 0);
    expect(input.text, text);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('composer drag selection follows the outer viewport', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(400, (index) => 'Line $index 中文内容\n').join();
    input.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await pumpComposer(tester);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    scroll.jumpTo(1000);
    await tester.pump();
    final viewport = tester.getRect(
      find.byKey(const ValueKey('ai-input-scrollbar')),
    );
    final pointer = await tester.startGesture(
      viewport.topLeft + const Offset(10, 10),
      kind: PointerDeviceKind.mouse,
    );
    await pointer.moveTo(viewport.topLeft + const Offset(30, 20));
    await tester.pump();
    final base = input.selection.baseOffset;
    expect(base, greaterThan(0));
    expect(focus.hasFocus, isTrue);
    for (var move = 0; move < 12; move++) {
      await pointer.moveTo(
        Offset(viewport.left + 90 + move, viewport.bottom + 40),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(scroll.offset, greaterThan(1000));
    expect(input.selection.baseOffset, base);
    expect(input.selection.extentOffset, greaterThan(base + 100));
    final afterDown = scroll.offset;
    for (var move = 0; move < 12; move++) {
      await pointer.moveTo(
        Offset(viewport.left + 70 + move, viewport.top - 40),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    await pointer.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(afterDown));
    expect(input.selection.baseOffset, base);
    expect(input.text, text);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ctrl+V preserves complete long input and copies it back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(
      2000,
      (index) => '$index 中文输入 English 🌿 é العربية 文本保持完整。\n\n',
    ).join();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': text},
        'Clipboard.hasStrings' => {'value': true},
        'Clipboard.setData' =>
          copied = (call.arguments as Map)['text'] as String,
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpComposer(tester);
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(input.text, text);
    expect(input.selection.extentOffset, text.length);
    expect(scroll.offset, greaterThan(1000));
    expect(find.byType(Scrollbar), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied, text);
    expect(input.text, text);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long editor and attachments scroll independently with focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(400, (index) => 'Line $index 中文内容\n').join();
    input.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    );
    await pumpComposer(
      tester,
      attachments: List.generate(
        40,
        (index) => AiImageAttachment(
          name: 'image-$index.png',
          bytes: bytes,
          mimeType: 'image/png',
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(
      find.byKey(const ValueKey('ai-input-scrollbar')),
    );
    final images = find.byKey(const ValueKey('ai-attachments-scroll'));
    final attachmentScroll = tester
        .widget<SingleChildScrollView>(images)
        .controller!;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(images),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(attachmentScroll.offset, greaterThan(0));
    expect(scroll.offset, 0);
    final imageOffset = attachmentScroll.offset;
    scroll.jumpTo(scroll.position.maxScrollExtent * .5);
    await tester.pumpAndSettle();
    final before = scroll.offset;
    final selection = input.selection;
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(Offset(viewport.right - 4, viewport.center.dy));
    await tester.pumpAndSettle();
    await pointer.down(Offset(viewport.right - 4, viewport.center.dy));
    await tester.pump();
    await pointer.moveBy(const Offset(0, 30));
    await tester.pumpAndSettle();
    await pointer.up();
    await pointer.removePointer();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(before));
    expect(attachmentScroll.offset, imageOffset);
    expect(focus.hasFocus, isTrue);
    expect(input.selection, selection);
    expect(input.text, text);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  tearDownAll(() async {
    if (const bool.fromEnvironment('COMPOSER_PERFORMANCE_PROBE')) {
      final report = File('tmp/chat-composer-performance.json');
      await report.parent.create(recursive: true);
      await report.writeAsString(
        const JsonEncoder.withIndent('  ').convert(results),
      );
    }
  });
}
