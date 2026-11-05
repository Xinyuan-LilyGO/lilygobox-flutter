/*
 * @Description: 验证 AI 主页居中与底部输入状态、键盘发送、直达设置及缩放布局。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 11:16:04
 * @LastEditTime: 2026-11-04 17:35:00
 * @License: GPL 3.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/split_view.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider splitView;
  late AppNavigationProvider navigation;
  late AssistantTestScope scope;
  var requests = 0;
  final boundaryKey = GlobalKey();

  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    splitView = SplitViewProvider();
    navigation = AppNavigationProvider();
    requests = 0;
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      final inter = FontLoader('LilygoBoxInter')
        ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf'));
      final defaultFont = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto/Roboto-Variable.ttf'));
      final symbols =
          FontLoader(
            'packages/material_symbols_icons/MaterialSymbolsRounded',
          )..addFont(
            rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
            ),
          );
      await Future.wait([inter.load(), defaultFont.load(), symbols.load()]);
    }
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Ready to help with LilygoBox.'},
              },
            ],
          }),
          200,
        );
      }),
    );
  });
  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    splitView.dispose();
    navigation.dispose();
  });

  Widget app({bool settings = false, double scale = 1, String locale = 'en'}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: scope.provider),
          ChangeNotifierProvider.value(value: navigation),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: theme.themeData.materialColors,
            fontFamily: 'LilygoBoxInter',
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: boundaryKey, child: child!),
          ),
          home: Scaffold(
            body: settings ? const SettingsSplitView() : const AssistantPage(),
          ),
        ),
      );

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('tmp/assistant-ui/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets(
    'composer stays at bottom with centered greeting and no assistant title',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final composer = find.byType(ChatComposer);
      expect(tester.getBottomRight(composer).dy, closeTo(736, 1));
      expect(
        tester.getRect(find.text('What can I help you with today?')).center.dx,
        closeTo(550, 1),
      );
      expect(find.text('LilygoBox Assistant'), findsNothing);
      expect(
        find.byKey(const ValueKey('ai-composer-context-layer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
        findsOneWidget,
      );
      final outerRect = tester.getRect(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final innerRect = tester.getRect(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      expect(innerRect.top - outerRect.top, 5);
      expect(outerRect.bottom - innerRect.bottom, 5);
      expect(innerRect.left - outerRect.left, 5);
      expect(outerRect.right - innerRect.right, 5);
      await capture(tester, 'home-empty-dark');
      expect(find.text('Adjust sidebar layout'), findsNothing);
      expect(find.text('Configure AI service'), findsNothing);
      final outer = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final inner = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      expect((outer.decoration as BoxDecoration).border, isNull);
      expect(
        (inner.decoration as BoxDecoration).border!.top.color,
        Colors.transparent,
      );
      expect(find.text('LilygoBox workspace'), findsNothing);
      final field = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(field, 'Adjust sidebar layout');
      tester.widget<TextField>(field).focusNode!.unfocus();
      await tester.pumpAndSettle();
      tester.widget<TextField>(field).focusNode!.requestFocus();
      await tester.pump(Duration.zero);
      final focusedOuter = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final focusedInner = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ai-composer-input-layer')),
      );
      Color renderedBorderColor() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byKey(
                                const ValueKey('ai-composer-input-layer'),
                              ),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .border!
              .top
              .color;
      expect((focusedOuter.decoration as BoxDecoration).border, isNull);
      expect(renderedBorderColor(), Colors.transparent);
      await tester.pump(const Duration(milliseconds: 90));
      final transitioningColor = renderedBorderColor();
      expect(transitioningColor, isNot(Colors.transparent));
      expect(transitioningColor, isNot(theme.themeData.basePrimary));
      await tester.pump(const Duration(milliseconds: 90));
      expect(renderedBorderColor(), theme.themeData.basePrimary);
      expect(focusedInner.duration, const Duration(milliseconds: 180));
      expect(requests, 0);
      await scope.provider.saveService(
        name: 'DeepSeek',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        models: ['deepseek-chat'],
        apiKey: 'test-key',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Ready to help with LilygoBox.'), findsOneWidget);
      expect(find.text('Adjust sidebar layout'), findsOneWidget);
      expect(tester.getBottomRight(composer).dy, closeTo(736, 1));
      expect(find.text('What can I help you with today?'), findsNothing);
      await capture(tester, 'home-conversation-dark');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing key opens model services without losing the draft', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'Keep this draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(navigation.currentPage, AppPage.settings);
    expect(navigation.settingsSection, AppSettingsSection.aiServices);
    expect(tester.widget<TextField>(field).controller!.text, 'Keep this draft');
    expect(requests, 0);
  });

  testWidgets('shift enter and IME confirmation do not submit messages', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ai-message-input'));
    await tester.enterText(field, 'First line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(requests, 0);
    expect(navigation.currentPage, AppPage.home);
    final controller = tester.widget<TextField>(field).controller!;
    controller.value = const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(navigation.currentPage, AppPage.home);
    expect(requests, 0);
  });

  testWidgets('home and AI settings adapt to narrow windows and large text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final type in ThemeType.values) {
      theme.setTheme(type);
      for (final locale in ['en', 'zh']) {
        await tester.binding.setSurfaceSize(const Size(390, 720));
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = find.byKey(const ValueKey('ai-message-input'));
        await tester.enterText(field, 'Line 1\nLine 2\nLine 3\nLine 4');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.openAiSettings();
        await tester.pumpWidget(
          app(settings: true, scale: 1.6, locale: locale),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai-add-service')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.closeSettings();
      }
    }
  });

  testWidgets(
    'model selector searches services and switches without navigation or lost drafts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(scope.provider.credentialLoaded, isTrue);
      final first = await scope.provider.saveService(
        name: 'DeepSeek',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        models: ['deepseek-chat', 'deepseek-reasoner'],
        apiKey: 'first-key',
      );
      final second = await scope.provider.saveService(
        name: 'Gateway',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['custom-model'],
        apiKey: 'second-key',
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(input, 'Keep this draft');
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      expect(navigation.currentPage, AppPage.home);
      expect(find.text('For next messages'), findsNothing);
      expect(find.text('Add model service'), findsNothing);
      await capture(tester, 'model-selector-dark');
      final search = find.byKey(const ValueKey('ai-model-search'));
      expect(find.text('Filter by model name or service name.'), findsNothing);
      final searchInput = search;
      expect(
        tester.widget<TextField>(searchInput).decoration!.labelText,
        isNull,
      );
      expect(tester.widget<TextField>(searchInput).autofocus, isFalse);
      expect(
        tester.widget<TextField>(searchInput).focusNode!.hasFocus,
        isFalse,
      );
      final searchDecoration = tester
          .widget<TextField>(searchInput)
          .decoration!;
      expect(searchDecoration.hintText, 'Search models or providers');
      expect(searchDecoration.isDense, isTrue);
      expect(
        (searchDecoration.border as OutlineInputBorder).borderRadius,
        BorderRadius.circular(999),
      );
      await tester.enterText(search, 'no-such-model');
      await tester.pumpAndSettle();
      expect(find.text('No matching models'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(
        find.byKey(ValueKey('ai-model-$first-deepseek-reasoner')),
        findsOneWidget,
      );
      await tester.enterText(search, 'gateway');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('ai-model-$first-deepseek-reasoner')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('ai-model-$second-custom-model')));
      await tester.pumpAndSettle();
      expect(scope.provider.selectedService?.id, second);
      expect(scope.provider.selectedModel, 'custom-model');
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Keep this draft',
      );
      expect(navigation.currentPage, AppPage.home);
      expect(requests, 0);
      expect(find.byKey(const ValueKey('ai-model-search')), findsNothing);
      expect(find.byKey(const ValueKey('ai-tools-button')), findsNothing);
      expect(find.text('Approval required for changes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'model menu stays compact without focusing search in narrow large text layouts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
        await tester.pumpAndSettle();
        final search = tester.widget<TextField>(
          find.byKey(const ValueKey('ai-model-search')),
        );
        expect(search.focusNode!.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'empty model menu shows its empty state without a duplicate service shortcut',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pump();
      double menuOpacity() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('ai-model-menu-fade')),
          )
          .opacity
          .value;
      expect(menuOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(menuOpacity(), closeTo(.5, .01));
      await tester.pump(const Duration(milliseconds: 75));
      expect(menuOpacity(), 1);
      await tester.pumpAndSettle();
      final menuRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-menu-surface')),
      );
      expect(menuRect.width, lessThanOrEqualTo(280));
      final selectorRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-selector')),
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('ai-model-menu-title')),
      );
      expect(menuRect.right, closeTo(selectorRect.right - 16, 1));
      expect(menuRect.right, lessThanOrEqualTo(784));
      expect(titleRect.top - menuRect.top, 10);
      expect(
        tester.getRect(find.byKey(const ValueKey('ai-model-search'))).top -
            titleRect.bottom,
        8,
      );
      expect(menuRect.height, lessThan(280));
      expect(
        find.text('No model services yet. Add a service to get started.'),
        findsOneWidget,
      );
      expect(navigation.currentPage, AppPage.home);
      expect(find.text('Add model service'), findsNothing);
      await capture(tester, 'model-selector-empty-compact');
      expect(tester.takeException(), isNull);
    },
  );
}
