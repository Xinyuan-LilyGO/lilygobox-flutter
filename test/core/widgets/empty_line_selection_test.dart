import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/empty_line_selection.dart';

void main() {
  testWidgets('read-only selection highlights blank lines and clears them', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: const SizedBox(
              width: 240,
              height: 200,
              child: ColoredBox(
                color: Colors.white,
                child: SelectionArea(
                  child: EmptyLineSelection(
                    child: Text(
                      'first\n\nlast',
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final line = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 6, extentOffset: 7),
        )
        .first;
    final origin = paragraph.localToGlobal(
      Offset.zero,
      ancestor: tester.renderObject(find.byKey(boundary)),
    );
    final sample = origin + Offset(line.left + 1, (line.top + line.bottom) / 2);
    Future<int> pixel() async {
      final image = await tester.runAsync(
        () => tester
            .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
            .toImage(),
      );
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final value = data!.getUint32(
        (sample.dy.floor() * image!.width + sample.dx.floor()) * 4,
      );
      image.dispose();
      return value;
    }

    final original = await pixel();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();
    expect(await pixel(), isNot(original));
    region.clearSelection();
    await tester.pumpAndSettle();
    expect(await pixel(), original);
    expect(find.text('first\n\nlast'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected blank lines paint narrow markers without changing content',
    (tester) async {
      final controller = TextEditingController(text: 'first\n\n\nlast\n');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyLineSelection(
              child: TextField(
                controller: controller,
                maxLines: 8,
                selectionWidthStyle: ui.BoxWidthStyle.tight,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(editable.foregroundPainter, isNotNull);
      Future<int> paintedPixels() async {
        final recorder = ui.PictureRecorder();
        editable.foregroundPainter!.paint(
          Canvas(recorder),
          editable.size,
          editable,
        );
        final picture = recorder.endRecording();
        final image = await tester.runAsync(
          () => picture.toImage(
            editable.size.width.ceil(),
            editable.size.height.ceil(),
          ),
        );
        final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        var painted = 0;
        for (var i = 3; i < bytes!.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) != 0) painted++;
        }
        image!.dispose();
        picture.dispose();
        return painted;
      }

      final count = await paintedPixels();
      expect(count, greaterThan(0));
      expect(
        count,
        lessThan(editable.size.width * editable.preferredLineHeight),
      );
      expect(
        controller.selection.textInside(controller.text),
        'first\n\n\nlast\n',
      );
      // 只选择正常文字不绘制空行标记，选区反向仍保留相同反馈。
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      expect(await paintedPixels(), 0);
      controller.selection = TextSelection(
        baseOffset: controller.text.length,
        extentOffset: 0,
      );
      await tester.pump();
      expect(await paintedPixels(), count);
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(await paintedPixels(), 0);
      expect(controller.text, 'first\n\n\nlast\n');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
