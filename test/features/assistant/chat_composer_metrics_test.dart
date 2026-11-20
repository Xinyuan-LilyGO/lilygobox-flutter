import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/features/assistant/data/context_compaction.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'assistant_test_scope.dart';

void main() {
  testWidgets('context metric opens its details on left click', (tester) async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
    );
    await scope.provider.initialized;
    final message = {'role': 'user', 'content': '界' * 1000};
    final messageTokens = estimateContextTokens(message);
    const used = 153694;
    scope.provider.restoreWorkspaceConversation({
      'history': List.filled(used ~/ messageTokens, message),
      'messages': [],
      'summary': '界' * (used % messageTokens),
      'contextBudgetTokens': 272000,
      'contextCompactionPercent': 90,
    });
    final input = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      input.dispose();
      focus.dispose();
      scroll.dispose();
      scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 820,
              child: ChatComposer(
                input: input,
                focusNode: focus,
                scrollController: scroll,
                theme: theme.themeData,
                assistant: scope.provider,
                ready: true,
                onSend: (_) {},
                attachments: const [],
                onAttachmentsChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metric = find.byKey(const ValueKey('ai-context-usage-metric'));
    final cache = find.byKey(const ValueKey('ai-cache-usage-metric'));
    final speed = find.byKey(const ValueKey('ai-output-speed-metric'));
    expect(
      find.descendant(of: speed, matching: find.text('平均速度')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: speed, matching: find.text('—')),
      findsOneWidget,
    );
    final surface = find.byKey(const ValueKey('ai-composer-context-layer'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final control in [cache, metric]) {
      final hover = theme.themeData.secondaryTextHoverColor;
      final background = find
          .descendant(of: control, matching: find.byType(DecoratedBox))
          .first;
      Color painted() =>
          (tester.widget<DecoratedBox>(background).decoration as BoxDecoration)
              .color!;
      for (final entering in [true, false]) {
        await mouse.moveTo(entering ? tester.getCenter(control) : Offset.zero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        final midpoint = painted();
        expect(midpoint.a, closeTo(.5, .01));
        expect(midpoint.withValues(alpha: 1), hover);
        await tester.pump(const Duration(milliseconds: 75));
        expect(painted().a, entering ? 1 : 0);
      }
    }
    await mouse.removePointer();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final width in [1200.0, 450.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = width == 450
          ? 1.5
          : 1;
      await tester.binding.setSurfaceSize(Size(width, 650));
      await tester.pumpAndSettle();
      final card = tester.getRect(surface);
      expect(tester.getTopLeft(speed).dy, greaterThan(card.bottom));
      expect(
        tester.getTopRight(speed).dx,
        lessThan(tester.getTopLeft(cache).dx),
      );
      expect(tester.getTopLeft(cache).dy, greaterThan(card.bottom));
      expect(tester.getTopLeft(metric).dy, greaterThan(card.bottom));
      final sameRow = tester.getCenter(cache).dy == tester.getCenter(metric).dy;
      expect(
        (tester.getTopLeft(speed).dx +
                tester.getTopRight(sameRow ? metric : cache).dx) /
            2,
        closeTo(card.center.dx, 1),
      );
      if (sameRow) {
        expect(
          tester.getTopRight(cache).dx,
          lessThan(tester.getTopLeft(metric).dx),
        );
      } else {
        expect(tester.getCenter(metric).dx, closeTo(card.center.dx, 1));
      }
    }
    expect(
      find.descendant(of: cache, matching: find.text('—')),
      findsOneWidget,
    );
    await tester.tap(cache);
    await tester.pumpAndSettle();
    expect(find.textContaining('缓存使用详情'), findsOneWidget);
    expect(find.text('当前对话尚未收到此模型的缓存用量统计。'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('缓存使用详情'), findsNothing);
    await tester.tap(metric);
    await tester.pumpAndSettle();
    expect(find.textContaining('上下文使用详情'), findsOneWidget);
    expect(find.text('估算使用量'), findsOneWidget);
    expect(find.text('上次压缩'), findsOneWidget);
    expect(find.text('~153.7K / 272K'), findsOneWidget);
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars.map((bar) => bar.color), [
      const Color(0xffa3d52d),
      const Color(0xff54a9ff),
    ]);
    for (final (label, expected) in [
      ('对话历史', const Color(0xffa3d52d)),
      ('压缩摘要', const Color(0xff54a9ff)),
    ]) {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final swatch = tester.widget<DecoratedBox>(
        find.descendant(of: row, matching: find.byType(DecoratedBox)),
      );
      expect((swatch.decoration as BoxDecoration).color, expected);
    }
    for (final count in [used, 272000, 244800]) {
      final text = '$count token';
      final finder = find.text(text);
      expect(finder, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      expect(boxes.map((box) => box.top).toSet(), hasLength(1));
    }
    final details = tester.getRect(find.byType(PopupMenuSurface));
    final lastRowBottom = tester.getBottomLeft(find.text('上次压缩')).dy;
    expect(details.bottom - lastRowBottom, inInclusiveRange(8, 16));
    expect(details.bottom, lessThan(tester.getTopLeft(metric).dy));
    expect(
      details.right,
      closeTo(tester.getTopRight(metric).dx.clamp(308.0, 442.0), 1),
    );
    await tester.tap(
      metric,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('上下文使用详情'), findsNothing);
    expect(find.text('立即压缩'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache metric opens token details on left click', (tester) async {
    final theme = ThemeProvider();
    final language = LanguageProvider();
    final shell = AppShellProvider();
    final split = SplitViewProvider();
    int? cachedTokens = 7;
    final scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: split,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Done'},
              },
            ],
            'usage': {
              'prompt_tokens': 2000,
              if (cachedTokens != null)
                'prompt_tokens_details': {'cached_tokens': cachedTokens},
              'completion_tokens': 3,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await scope.provider.initialized;
    await scope.provider.saveService(
      name: 'Test',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['test-model'],
      apiKey: 'test-key',
    );
    await tester.runAsync(
      () => scope.provider.sendMessage('Test cache metrics'),
    );
    final input = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      input.dispose();
      focus.dispose();
      scroll.dispose();
      scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 820,
              child: ChatComposer(
                input: input,
                focusNode: focus,
                scrollController: scroll,
                theme: theme.themeData,
                assistant: scope.provider,
                ready: true,
                onSend: (_) {},
                attachments: const [],
                onAttachmentsChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metric = find.byKey(const ValueKey('ai-cache-usage-metric'));
    expect(metric, findsOneWidget);
    final label = find.descendant(of: metric, matching: find.text('缓存命中'));
    final value = find.descendant(of: metric, matching: find.text('<1%'));
    expect(tester.getTopRight(label).dx, lessThan(tester.getTopLeft(value).dx));
    final ring = find.descendant(
      of: metric,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(tester.widget<CircularProgressIndicator>(ring).value, 7 / 2000);
    await tester.tap(metric);
    await tester.pumpAndSettle();
    expect(find.textContaining('缓存使用详情'), findsOneWidget);
    expect(find.text('缓存输入 token'), findsOneWidget);
    expect(find.text('7 token'), findsOneWidget);
    final details = tester.getRect(find.byType(PopupMenuSurface));
    final lastRowBottom = tester.getBottomLeft(find.text('输出 token')).dy;
    expect(details.bottom - lastRowBottom, inInclusiveRange(8, 16));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    cachedTokens = 0;
    await tester.runAsync(() => scope.provider.sendMessage('Uncached request'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: metric, matching: find.text('0%')),
      findsOneWidget,
    );
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0);
    cachedTokens = null;
    await tester.runAsync(
      () => scope.provider.sendMessage('Missing cached tokens'),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: metric, matching: find.text('—')),
      findsOneWidget,
    );
    await tester.tap(metric);
    await tester.pumpAndSettle();
    expect(find.text('2000 token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
