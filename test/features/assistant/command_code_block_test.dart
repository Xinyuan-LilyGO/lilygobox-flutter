import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/title_bar_icon_button.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/code_block.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

Widget host(
  String text, {
  double? maxHeight = 160,
  bool initialSoftWrap = false,
  bool visibleScrollbars = false,
  ThemeType themeType = ThemeType.light,
  ValueChanged<SelectedContent?>? selection,
}) => MaterialApp(
  theme: ThemeData(
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(visibleScrollbars),
    ),
  ),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        child: SelectionArea(
          onSelectionChanged: selection,
          child: ChatCodeBlock(
            text: text,
            language: 'powershell',
            theme: MaterialPalette.create(themeType),
            maxBodyHeight: maxHeight,
            initialSoftWrap: initialSoftWrap,
          ),
        ),
      ),
    ),
  ),
);

Rect codeContentRect(WidgetTester tester) {
  final clip = tester.renderObject<RenderClipRect>(
    find.byKey(const ValueKey('ai-code-scroll-gutter')),
  );
  return clip.clipper!
      .getClip(clip.size)
      .shift(clip.localToGlobal(Offset.zero));
}

void main() {
  testWidgets(
    'short command uses ordinary text without unnecessary scroll views',
    (tester) async {
      await tester.pumpWidget(host('Write-Output hello'));
      await tester.pumpAndSettle();
      expect(find.text('powershell'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      final card = tester.getRect(find.byKey(const ValueKey('ai-code-block')));
      final textRect = tester.getRect(find.text('Write-Output hello'));
      expect(textRect.left - card.left, 12);
      expect(card.right - textRect.right, 12);
      expect(card.bottom - textRect.bottom, 12);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long single line scrolls horizontally without clipping source', (
    tester,
  ) async {
    final text = 'command ${List.filled(80, 'argument').join(' ')}';
    await tester.pumpWidget(host(text));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('ai-code-horizontal-scroll'));
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(find.byKey(const ValueKey('ai-code-vertical-scroll')), findsNothing);
    expect(find.text(text), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ai-code-body-viewport')))
          .height,
      lessThanOrEqualTo(160),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bounded multiline command keeps header fixed and uses independent scrollbar gutters',
    (tester) async {
      final text = List.generate(
        45,
        (index) => 'line $index ${List.filled(40, 'value').join(' ')}',
      ).join('\n');
      await tester.pumpWidget(host(text));
      await tester.pumpAndSettle();
      final viewport = find.byKey(const ValueKey('ai-code-body-viewport'));
      expect(tester.getSize(viewport).height, 160);
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-code-vertical-scroll')),
          )
          .controller!;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-code-horizontal-scroll')),
          )
          .controller!;
      expect(vertical.position.maxScrollExtent, greaterThan(0));
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      expect(find.byType(Scrollbar), findsNWidgets(2));
      for (final key in [
        'ai-code-vertical-scrollbar',
        'ai-code-horizontal-scrollbar',
      ]) {
        expect(
          ScrollbarTheme.of(
            tester.element(find.byKey(ValueKey(key))),
          ).crossAxisMargin,
          AppScrollBehavior.scrollbarEdgeInset,
        );
      }
      final bodyRect = tester.getRect(viewport);
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('ai-code-block')),
      );
      expect(bodyRect.left, cardRect.left);
      expect(bodyRect.right, cardRect.right);
      expect(bodyRect.bottom, cardRect.bottom);
      for (final key in [
        'ai-code-horizontal-scrollbar',
        'ai-code-vertical-scrollbar',
      ]) {
        final scrollbar = tester.getRect(find.byKey(ValueKey(key)));
        final margin = ScrollbarTheme.of(
          tester.element(find.byKey(ValueKey(key))),
        ).crossAxisMargin!;
        expect(cardRect.right - (scrollbar.right - margin), 6);
        expect(cardRect.bottom - (scrollbar.bottom - margin), 6);
      }
      expect(bodyRect.bottom - codeContentRect(tester).bottom, 20);
      expect(bodyRect.right - codeContentRect(tester).right, 20);
      final before = tester.getRect(find.byKey(const ValueKey('ai-copy-code')));
      vertical.jumpTo(vertical.position.maxScrollExtent);
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(bodyRect.bottom - codeContentRect(tester).bottom, 20);
      expect(bodyRect.right - codeContentRect(tester).right, 20);
      expect(
        tester.getRect(find.byKey(const ValueKey('ai-copy-code'))),
        before,
      );
      expect(
        find.byKey(const ValueKey('ai-copy-code')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy retains all raw characters and parent selection includes code',
    (tester) async {
      const text = "  Write-Output 'hello'\nWrite-Output done  \n";
      String? copied;
      String? selected;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        host(text, selection: (value) => selected = value?.plainText),
      );
      await tester.pumpAndSettle();
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected, contains(text));
      expect(find.byType(SelectableText), findsNothing);
      region.clearSelection();
      region.hideToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-copy-code')));
      await tester.pump();
      expect(copied, text);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  for (final maxHeight in <double?>[160, null]) {
    testWidgets(
      'horizontal scrollbar follows card bottom edge at height $maxHeight',
      (tester) async {
        final text = List.filled(100, 'long-argument').join(' ');
        await tester.pumpWidget(host(text, maxHeight: maxHeight));
        await tester.pumpAndSettle();
        final card = tester.getRect(
          find.byKey(const ValueKey('ai-code-block')),
        );
        final scrollbarFinder = find.byKey(
          const ValueKey('ai-code-horizontal-scrollbar'),
        );
        final scrollbar = tester.getRect(scrollbarFinder);
        final margin = ScrollbarTheme.of(
          tester.element(scrollbarFinder),
        ).crossAxisMargin!;
        expect(scrollbar.bottom, card.bottom);
        expect(card.bottom - (scrollbar.bottom - margin), 6);
        final scrollFinder = find.byKey(
          const ValueKey('ai-code-horizontal-scroll'),
        );
        final scroll = tester
            .widget<SingleChildScrollView>(scrollFinder)
            .controller!;
        expect(card.bottom - codeContentRect(tester).bottom, 20);
        expect(codeContentRect(tester).left - card.left, 12);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(card.bottom - codeContentRect(tester).bottom, 20);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('vertical-only scrollbar follows card right edge', (
    tester,
  ) async {
    final text = List.filled(40, 'short line').join('\n');
    await tester.pumpWidget(host(text));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const ValueKey('ai-code-block')));
    final scrollbarFinder = find.byKey(
      const ValueKey('ai-code-vertical-scrollbar'),
    );
    final scrollbar = tester.getRect(scrollbarFinder);
    final margin = ScrollbarTheme.of(
      tester.element(scrollbarFinder),
    ).crossAxisMargin!;
    expect(scrollbar.right, card.right);
    expect(card.right - (scrollbar.right - margin), 6);
    final scrollRect = codeContentRect(tester);
    expect(card.right - scrollRect.right, 20);
    expect(card.bottom - scrollRect.bottom, 12);
    expect(
      find.byKey(const ValueKey('ai-code-horizontal-scrollbar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final themeType in [ThemeType.light, ThemeType.dark]) {
    testWidgets(
      'wrap preserves original padding and inherits scrollbar style ($themeType)',
      (tester) async {
        const shortText = 'Write-Output hello';
        await tester.pumpWidget(
          host(shortText, initialSoftWrap: true, themeType: themeType),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(
          find.byKey(const ValueKey('ai-code-block')),
        );
        final textRect = tester.getRect(find.text(shortText));
        expect(textRect.left - card.left, 12);
        expect(card.right - textRect.right, 12);
        expect(find.byType(SingleChildScrollView), findsNothing);
        final longText = List.filled(100, '--argument value').join(' ');
        await tester.pumpWidget(
          host(longText, initialSoftWrap: true, themeType: themeType),
        );
        await tester.pumpAndSettle();
        final longCard = tester.getRect(
          find.byKey(const ValueKey('ai-code-block')),
        );
        final content = codeContentRect(tester);
        expect(content.left - longCard.left, 12);
        expect(longCard.right - content.right, 20);
        final scrollbar = find.byKey(
          const ValueKey('ai-code-vertical-scrollbar'),
        );
        final style = ScrollbarTheme.of(tester.element(scrollbar));
        expect(style.thickness, isNull);
        expect(style.crossAxisMargin, 6);
        expect(style.mainAxisMargin, 6);
        expect(tester.widget<Text>(find.text(longText)).data, longText);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('command wrap toggles scroll axes and keeps the header fixed', (
    tester,
  ) async {
    final text = List.filled(100, '--argument value').join(' ');
    await tester.pumpWidget(host(text, initialSoftWrap: true));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('ai-code-wrap'));
    final copy = find.byKey(const ValueKey('ai-copy-code'));
    final copyRect = tester.getRect(copy);
    expect(tester.getRect(toggle).right, lessThan(copyRect.left));
    expect(tester.widget<Text>(find.text(text)).softWrap, isTrue);
    expect(
      find.byKey(const ValueKey('ai-code-horizontal-scroll')),
      findsNothing,
    );
    final vertical = find.byKey(const ValueKey('ai-code-vertical-scroll'));
    expect(
      tester
          .widget<SingleChildScrollView>(vertical)
          .controller!
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ai-code-body-viewport')))
          .height,
      160,
    );
    final wrappedColor = tester
        .widget<TitleBarIconButton>(toggle)
        .backgroundColor;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final horizontal = find.byKey(const ValueKey('ai-code-horizontal-scroll'));
    expect(horizontal, findsOneWidget);
    expect(vertical, findsNothing);
    expect(
      tester.widget<TitleBarIconButton>(toggle).backgroundColor,
      isNot(wrappedColor),
    );
    final controller = tester
        .widget<SingleChildScrollView>(horizontal)
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(horizontal, findsNothing);
    expect(vertical, findsOneWidget);
    expect(tester.getRect(copy), copyRect);
    // 增量更新正文时保留该代码块的手动换行设置。
    await tester.pumpWidget(host('$text extra', initialSoftWrap: false));
    await tester.pumpAndSettle();
    expect(horizontal, findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary Markdown wrap is opt-in and keeps the full source selectable and copyable',
    (tester) async {
      // 普通 Markdown 正文不限制高度，为折行后的完整原文提供足够测试空间。
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final arguments = List.filled(30, '--argument value').join(' ');
      final text = '  command \t\n$arguments  \n';
      String? selected;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        host(
          text,
          maxHeight: null,
          selection: (value) => selected = value?.plainText,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ai-code-horizontal-scroll')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ai-code-wrap')));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.getSize(find.text(text)).height, greaterThan(160));
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(selected, contains(text));
      region.clearSelection();
      region.hideToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-copy-code')));
      await tester.pump();
      expect(copied, text);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary Markdown blocks do not gain a vertical height limit', (
    tester,
  ) async {
    final text = List.filled(20, 'short line').join('\n');
    await tester.pumpWidget(host(text, maxHeight: null));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-code-vertical-scroll')), findsNothing);
    expect(tester.getSize(find.text(text)).height, greaterThan(160));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'horizontal thumb leaves six pixels at both actual card endpoints',
    (tester) async {
      final text = List.filled(100, 'long-argument').join(' ');
      await tester.pumpWidget(host(text, visibleScrollbars: true));
      await tester.pumpAndSettle();
      final paintFinder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      );
      final painter =
          tester.widget<CustomPaint>(paintFinder).foregroundPainter!
              as ScrollbarPainter;
      final size = tester.getSize(paintFinder);
      final card = tester.getRect(find.byKey(const ValueKey('ai-code-block')));
      expect(size.width, card.width);
      final y = size.height - 6 - painter.thickness / 2;
      bool thumbContains(double x) => painter.hitTestOnlyThumbInteractive(
        Offset(x, y),
        PointerDeviceKind.mouse,
      );
      expect(thumbContains(5.9), isFalse);
      expect(thumbContains(6.1), isTrue);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('ai-code-horizontal-scroll')),
          )
          .controller!;
      expect(scroll.position.viewportDimension, card.width);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(thumbContains(size.width - 6.1), isTrue);
      expect(thumbContains(size.width - 5.9), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
