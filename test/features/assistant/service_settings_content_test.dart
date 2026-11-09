/*
 * @Description: 验证模型服务列表排序、确认添加、取消、编辑与删除。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-09 10:36:06
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/service_settings_content.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider splitView;
  late AssistantTestScope scope;
  var requests = 0;
  var invalidChatResponse = false;
  Completer<void>? modelRequestGate;
  final boundaryKey = GlobalKey();
  setUp(() async {
    theme = ThemeProvider();
    language = LanguageProvider();
    shell = AppShellProvider();
    splitView = SplitViewProvider();
    requests = 0;
    invalidChatResponse = false;
    modelRequestGate = null;
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      await (FontLoader('LilygoBoxInter')
            ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf')))
          .load();
      await (FontLoader('Roboto')..addFont(
            rootBundle.load('assets/fonts/Roboto/Roboto-Variable.ttf'),
          ))
          .load();
      await (FontLoader(
            'packages/material_symbols_icons/MaterialSymbolsRounded',
          )..addFont(
            rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
            ),
          ))
          .load();
    }
    scope = await createAssistantTestScope(
      theme: theme,
      language: language,
      shell: shell,
      splitView: splitView,
      client: MockClient((request) async {
        requests++;
        expect(request.headers['authorization'], 'Bearer test-key');
        if (request.method == 'GET') {
          await modelRequestGate?.future;
          expect(request.url.path, '/v1/models');
          return http.Response(
            '{"data":[{"id":"model-a"},{"id":"model-b"}]}',
            200,
          );
        }
        if (invalidChatResponse) return http.Response('invalid body', 200);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'OK'},
              },
            ],
          }),
          200,
        );
      }),
    );
    await scope.provider.initialized;
  });
  tearDown(() {
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    splitView.dispose();
  });

  Widget app({double scale = 1, String locale = 'en'}) =>
      ChangeNotifierProvider<AiAssistantProvider>.value(
        value: scope.provider,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: theme.themeData.materialColors,
          ),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: boundaryKey, child: child!),
          ),
          home: Scaffold(
            backgroundColor: theme.themeData.secondary,
            body: AiServiceSettingsContent(theme: theme.themeData),
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

  Finder field(String key) => find.byKey(ValueKey('ai-service-$key'));
  Finder input(String key) =>
      find.descendant(of: field(key), matching: find.byType(TextField));
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai-add-service')));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(field('name'), 'My gateway');
    await tester.enterText(field('address'), 'https://example.test/v1');
    await tester.enterText(field('key'), 'test-key');
    await tester.enterText(field('models'), 'model-a\nmodel-b');
  }

  testWidgets('chat request errors are not shown in model service settings', (
    tester,
  ) async {
    await scope.provider.saveService(
      name: 'Gateway',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['model-a'],
      apiKey: 'test-key',
    );
    invalidChatResponse = true;
    await tester.runAsync(() => scope.provider.sendMessage('Hello'));
    expect(scope.provider.error, isNotNull);
    expect(scope.provider.configurationError, isNull);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.text('The service returned an invalid response. Check the API URL.'),
      findsNothing,
    );
    expect(find.text('invalid body'), findsNothing);
  });

  testWidgets(
    'service only appears after explicit confirmation; editing retains key and deletion confirms',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(scope.provider.services, isEmpty);
      expect(find.text('DeepSeek'), findsNothing);
      expect(find.text('Service presets'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await capture(tester, 'services-empty');
      await open(tester);
      expect(tester.widget<TextField>(input('name')).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(input('address')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(input('models')).controller!.text,
        isEmpty,
      );
      final modelTitle = find.text('Model');
      final fetchButton = find.byKey(const ValueKey('ai-discover-models'));
      expect(
        tester.getTopLeft(fetchButton).dy,
        greaterThan(tester.getBottomLeft(modelTitle).dy),
      );
      await fill(tester);
      expect(scope.provider.services, isEmpty);
      await tester.pumpAndSettle();
      await capture(tester, 'service-add-dialog');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(scope.provider.services, isEmpty);
      await open(tester);
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('ai-confirm-service')));
      await tester.pump();
      for (var frame = 0; frame < 8 && scope.provider.saving; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(scope.provider.services.single.name, 'My gateway');
      expect(scope.provider.hasApiKey, isTrue);
      expect(requests, 0);
      await capture(tester, 'services-added');
      final card = find.byKey(
        ValueKey('ai-service-card-${scope.provider.services.single.id}'),
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-confirm-service')), findsNothing);
      expect(find.text('Test connection'), findsNothing);
      await tester.tap(find.text('Edit service'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-confirm-service')), findsOneWidget);
      expect(tester.widget<TextField>(input('key')).controller!.text, isEmpty);
      await tester.enterText(field('name'), 'Renamed service');
      await tester.tap(find.byKey(const ValueKey('ai-confirm-service')));
      await tester.pumpAndSettle();
      expect(scope.provider.hasApiKey, isTrue);
      expect(scope.provider.services.single.name, 'Renamed service');
      await tester.tap(find.widgetWithText(AppActionButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-ai-service')));
      await tester.pumpAndSettle();
      expect(scope.provider.services, hasLength(1));
      await tester.tap(find.widgetWithText(AppActionButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-ai-service')));
      await tester.pumpAndSettle();
      expect(scope.provider.services, isEmpty);
      expect(scope.provider.selectedModel, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clicking outside the add dialog cancels without saving', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);
    await fill(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-confirm-service')), findsNothing);
    expect(scope.provider.services, isEmpty);
  });

  testWidgets(
    'official provider presets hide endpoint fields and save defaults',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await open(tester);

      final presetSelect = find.byKey(const ValueKey('ai-service-preset'));
      expect(
        tester.widget<SettingSelect<AiServicePreset>>(presetSelect).value,
        AiServicePreset.custom,
      );
      await tester.tap(presetSelect);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek (official)').last);
      await tester.pumpAndSettle();
      expect(field('address'), findsNothing);
      expect(find.byKey(const ValueKey('ai-service-protocol')), findsNothing);
      expect(field('key'), findsOneWidget);
      expect(field('models'), findsOneWidget);

      await tester.enterText(field('name'), 'Official DeepSeek');
      await tester.enterText(field('key'), 'deepseek-key');
      await tester.enterText(field('models'), 'deepseek-chat');
      await tester.tap(find.byKey(const ValueKey('ai-confirm-service')));
      await tester.pumpAndSettle();

      final service = scope.provider.services.single;
      expect(service.preset, AiServicePreset.deepSeek);
      expect(service.baseUrl, 'https://api.deepseek.com');
      expect(service.protocol, AiApiProtocol.openAiChatCompletions);
      await tester.tap(find.text('Edit service'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingSelect<AiServicePreset>>(presetSelect).value,
        AiServicePreset.deepSeek,
      );
      await tester.enterText(field('key'), 'do-not-reuse');
      await tester.tap(presetSelect);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI (official)').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input('key')).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(input('models')).controller!.text,
        isEmpty,
      );
      expect(field('address'), findsNothing);
      await tester.enterText(field('key'), 'test-key');
      await tester.tap(find.byKey(const ValueKey('ai-discover-models')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('models')).controller!.text,
        'model-a\nmodel-b',
      );
      await tester.tap(find.byKey(const ValueKey('ai-confirm-service')));
      await tester.pumpAndSettle();
      expect(scope.provider.services.single.preset, AiServicePreset.openAi);
      expect(
        scope.provider.services.single.baseUrl,
        'https://api.openai.com/v1',
      );
      expect(
        scope.provider.services.single.protocol,
        AiApiProtocol.openAiResponses,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a service updates the shared model selector order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final name in ['First service', 'Second service']) {
      await scope.provider.saveService(
        name: name,
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://${name.toLowerCase().replaceAll(' ', '-')}.test/v1',
        models: [name],
        apiKey: 'test-key',
      );
    }
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(scope.provider.services.first.name, 'First service');
    final firstHandle = find.byKey(
      ValueKey('ai-drag-service-${scope.provider.services.first.id}'),
    );
    final firstCard = find.byKey(
      ValueKey('ai-service-card-${scope.provider.services.first.id}'),
    );
    expect(firstHandle, findsOneWidget);
    expect(firstCard, findsOneWidget);
    final drag = await tester.startGesture(
      tester.getCenter(firstHandle),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveBy(const Offset(0, 10));
    await tester.pump();
    await drag.moveBy(const Offset(0, 40));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(scope.provider.services.map((service) => service.name), [
      'Second service',
      'First service',
    ]);
    await capture(tester, 'services-reordered');
    final dragUp = await tester.startGesture(
      tester.getCenter(firstHandle),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await dragUp.moveBy(const Offset(0, -10));
    await tester.pump();
    await dragUp.moveBy(const Offset(0, -40));
    await tester.pump();
    await dragUp.up();
    await tester.pumpAndSettle();
    expect(scope.provider.services.map((service) => service.name), [
      'First service',
      'Second service',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'service cards keep two text levels across themes and narrow windows',
    (tester) async {
      final serviceId = await scope.provider.saveService(
        name: 'Example model service',
        protocol: AiApiProtocol.openAiChatCompletions,
        baseUrl: 'https://example.test/v1',
        models: ['model-a', 'model-b'],
        apiKey: 'test-key',
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ThemeType.values) {
        theme.setTheme(type);
        for (final narrow in [false, true]) {
          await tester.binding.setSurfaceSize(
            narrow ? const Size(390, 720) : const Size(1120, 800),
          );
          await tester.pumpWidget(app(scale: narrow ? 1.6 : 1));
          await tester.pumpAndSettle();
          expect(find.text('Example model service'), findsOneWidget);
          expect(find.text('API URL: https://example.test/v1'), findsOneWidget);
          expect(find.text('OpenAI Chat Completions'), findsNothing);
          expect(find.text('Current service'), findsNothing);
          expect(find.text('model-a · model-b'), findsNothing);
          expect(
            tester
                .widget<Material>(
                  find.byKey(ValueKey('ai-service-card-$serviceId')),
                )
                .color,
            theme.themeData.tertiary,
          );
          final serviceButtons = tester.widgetList<AppActionButton>(
            find.descendant(
              of: find.byKey(ValueKey('ai-service-card-$serviceId')),
              matching: find.byType(AppActionButton),
            ),
          );
          expect(serviceButtons, hasLength(2));
          expect(serviceButtons.first.tertiaryBackground, isTrue);
          expect(serviceButtons.last.destructive, isTrue);
          expect(
            serviceButtons.last.padding,
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          );
          expect(
            serviceButtons.last.borderRadius,
            serviceButtons.first.borderRadius,
          );
          expect(serviceButtons.last.fontSize, serviceButtons.first.fontSize);
          expect(find.text('Edit service'), findsOneWidget);
          expect(
            theme.themeData.tertiarySurfaceButtonColors.background,
            theme.themeData.tertiarySurfaceButtonBackgroundColor,
          );
          expect(
            theme.themeData.tertiarySurfaceButtonColors.hover,
            theme.themeData.tertiarySurfaceButtonHoverColor,
          );
          expect(
            theme.themeData.tertiarySurfaceButtonColors.pressed,
            theme.themeData.tertiarySurfaceButtonPressedColor,
          );
          final testButtonSurface = find.descendant(
            of: find.widgetWithText(AppActionButton, 'Edit service'),
            matching: find.byType(MenuItemSurface),
          );
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(testButtonSurface));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          final buttonDecoration = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: testButtonSurface,
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(
            (buttonDecoration.decoration as BoxDecoration).color,
            theme.themeData.tertiarySurfaceButtonHoverColor,
          );
          await mouse.removePointer();
          if (type == ThemeType.light) {
            expect(
              theme.themeData.tertiarySurfaceButtonHoverColor
                  .computeLuminance(),
              lessThan(
                theme.themeData.tertiarySurfaceButtonBackgroundColor
                    .computeLuminance(),
              ),
            );
            expect(theme.themeData.tertiary, const Color(0xFFD0D0D0));
          } else {
            expect(theme.themeData.tertiary, const Color(0xFF414141));
          }
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'services-${type.name}-${narrow ? 'narrow' : 'wide'}',
          );
        }
      }
    },
  );

  testWidgets('fetching models reveals progress without manual scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(field('address'), 'https://example.test/v1');
    await tester.enterText(field('key'), 'test-key');
    final fetch = find.byKey(const ValueKey('ai-discover-models'));
    await tester.ensureVisible(fetch);
    modelRequestGate = Completer<void>();
    await tester.tap(fetch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    final progress = find.byType(LinearProgressIndicator);
    expect(progress, findsOneWidget);
    final viewport = find
        .ancestor(
          of: field('models'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(
      tester.getRect(viewport).contains(tester.getCenter(progress)),
      isTrue,
    );
    modelRequestGate!.complete();
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(
      tester.widget<TextField>(input('models')).controller!.text,
      'model-a\nmodel-b',
    );
    expect(
      tester.getBottomLeft(field('models')).dy,
      lessThanOrEqualTo(tester.getBottomLeft(viewport).dy + 1),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'validation keeps dialog open; fetching models never adds a service',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await open(tester);
      await tester.enterText(field('name'), 'Test API');
      await tester.enterText(field('address'), 'https://example.test/v1');
      await tester.enterText(field('models'), 'model-a');
      await tester.tap(find.byKey(const ValueKey('ai-confirm-service')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(scope.provider.services, isEmpty);
      expect(
        find.text(
          'Enter an API key. A new key is required when changing the service provider or host.',
        ),
        findsOneWidget,
      );
      await tester.enterText(field('key'), 'test-key');
      await tester.ensureVisible(
        find.byKey(const ValueKey('ai-discover-models')),
      );
      await tester.tap(find.byKey(const ValueKey('ai-discover-models')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('models')).controller!.text,
        'model-a\nmodel-b',
      );
      expect(scope.provider.services, isEmpty);
      expect(requests, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('service form headings and descriptions stay above shared inputs', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);
    for (final (title, description, key) in [
      (
        'Service name',
        'Identifies this service in the home model selector.',
        'name',
      ),
      (
        'API URL',
        'Enter the API URL. The client adds the path required by the selected protocol.',
        'address',
      ),
      (
        'API key',
        'The key is saved locally using the operating system secure storage.',
        'key',
      ),
      (
        'Model',
        'Enter one model ID per line, or separate with commas. You can enter IDs manually if fetching fails.',
        'models',
      ),
    ]) {
      expect(
        tester.getTopLeft(find.text(title)).dy,
        lessThan(tester.getTopLeft(find.text(description)).dy),
      );
      expect(
        tester.getTopLeft(find.text(description)).dy,
        lessThan(tester.getTopLeft(field(key)).dy),
      );
      expect(
        tester.widget<TextField>(input(key)).decoration!.labelText,
        isNull,
      );
    }
    expect(find.text('API protocol'), findsOneWidget);
    expect(
      find.text('Choose the API protocol supported by your provider.'),
      findsOneWidget,
    );
    expect(find.text('Anthropic Messages'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-service-protocol')));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI Chat Completions'), findsWidgets);
    expect(find.text('OpenAI Responses'), findsOneWidget);
    expect(find.text('Anthropic Messages'), findsNothing);
    expect(tester.widget<TextField>(input('models')).maxLines, 5);
    final decoration = tester.widget<TextField>(input('name')).decoration!;
    expect(
      decoration.contentPadding,
      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
    expect(decoration.enabledBorder!.borderSide.style, BorderStyle.none);
    expect(decoration.focusedBorder!.borderSide.style, BorderStyle.solid);
  });

  testWidgets(
    'add dialog scrolls without overflow in narrow windows and translated large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in ['en', 'zh']) {
        await tester.pumpWidget(app(scale: 1.6, locale: locale));
        await tester.pumpAndSettle();
        await open(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(locale == 'en' ? 'Cancel' : '取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
