import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/settings/fields.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late ThemeProvider theme;
  var clipboard = '';

  setUp(() {
    theme = ThemeProvider();
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String;
            case 'Clipboard.getData':
              return {'text': clipboard};
            case 'Clipboard.hasStrings':
              return {'value': clipboard.isNotEmpty};
          }
          return null;
        });
  });

  tearDown(() {
    ContextMenuController.removeAny();
    theme.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app(Widget field) => ChangeNotifierProvider.value(
    value: theme,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 440, child: field)),
      ),
    ),
  );

  testWidgets(
    'multiline selection ends at each actual line and copy retains whitespace',
    (tester) async {
      const text = 'a much longer first line  \nx\n  tail  ';
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          SettingControlledTextField(
            theme: theme.themeData,
            controller: controller,
            minLines: 3,
            maxLines: 4,
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await tester.tapAt(
        tester.getTopLeft(field) + const Offset(15, 16),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(controller.selection.start, 0);
      expect(controller.selection.end, text.length);
      expect(controller.text, text);

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final render = editable.renderEditable;
      expect(render.selectionWidthStyle, ui.BoxWidthStyle.tight);
      final boxes = render.getBoxesForSelection(controller.selection);
      final rows = <double, double>{};
      for (final box in boxes) {
        if (box.right > box.left) {
          rows.update(
            box.top,
            (right) => right > box.right ? right : box.right,
            ifAbsent: () => box.right,
          );
        }
      }
      final rights = rows.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      expect(rights, hasLength(3));
      // 短行选区不能扩展到上一行的长度，也不能填满输入框剩余宽度。
      expect(rights[1].value, lessThan(rights[0].value / 3));
      expect(rights[2].value, lessThan(rights[0].value));
      expect(rights[0].value, lessThan(render.size.width - 20));

      editable.showToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard, text);
      expect(controller.text, text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'multiline field has one scrollbar at the field edge and scrolls its editor',
    (tester) async {
      final controller = TextEditingController(
        text: List.generate(50, (i) => 'model-$i').join('\n'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          SettingControlledTextField(
            theme: theme.themeData,
            controller: controller,
            minLines: 3,
            maxLines: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);
      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(bar.controller, same(field.scrollController));
      final barTheme = ScrollbarTheme.of(
        tester.element(find.byType(Scrollbar)),
      );
      expect(barTheme.crossAxisMargin, 6);
      expect(barTheme.mainAxisMargin, 6);
      final fieldRect = tester.getRect(find.byType(TextField));
      expect(tester.getRect(find.byType(Scrollbar)), fieldRect);
      expect(bar.controller!.position.maxScrollExtent, greaterThan(0));
      bar.controller!.jumpTo(0);
      await tester.drag(find.byType(TextField), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(bar.controller!.offset, greaterThan(0));
      expect(controller.text, contains('model-49'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('uncontrolled setting field also highlights only its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(SettingTextField(theme: theme.themeData, value: 'short')),
    );
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();
    final RenderEditable render = state.renderEditable;
    expect(render.selectionWidthStyle, ui.BoxWidthStyle.tight);
    final boxes = render.getBoxesForSelection(
      state.widget.controller.selection,
    );
    expect(boxes, hasLength(1));
    expect(
      boxes.single.right - boxes.single.left,
      lessThan(render.size.width / 2),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
