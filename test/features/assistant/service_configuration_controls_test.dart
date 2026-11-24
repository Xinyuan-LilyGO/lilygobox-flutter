import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/desktop_card_selection.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/service_settings_content.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'assistant_test_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppShellProvider shell;
  late SplitViewProvider split;
  late AssistantTestScope scope;
  late Directory directory;
  late File backup;
  Object? pickerResult;
  Completer<Object?>? pickerGate;
  final boundaryKey = GlobalKey();

  setUp(() async {
    if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
      await (FontLoader('LilygoBoxInter')
            ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Variable.ttf')))
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
    await scope.provider.initialized;
    directory = await Directory.systemTemp.createTemp('lilygobox-backup-ui-');
    backup = File('${directory.path}/services.json');
    pickerResult = null;
    pickerGate = null;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (pickerGate case final gate?) return gate.future;
      return pickerResult;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    scope.dispose();
    theme.dispose();
    language.dispose();
    shell.dispose();
    split.dispose();
    if (await backup.exists()) await backup.delete();
    await directory.delete();
  });

  Future<String> addService() async {
    final id = await scope.provider.saveService(
      name: 'Backup service',
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['model-a', 'model-b'],
      apiKey: 'backup-test-secret',
    );
    await scope.provider.selectModel(id, 'model-b');
    return id;
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AiAssistantProvider>.value(
        value: scope.provider,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: theme.themeData.materialColors,
            fontFamily: const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')
                ? 'LilygoBoxInter'
                : null,
          ),
          builder: (context, child) =>
              RepaintBoundary(key: boundaryKey, child: child!),
          home: Scaffold(
            backgroundColor: theme.themeData.secondary,
            body: AiServiceSettingsContent(theme: theme.themeData),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppActionButton button(WidgetTester tester, String key) =>
      tester.widget<AppActionButton>(find.byKey(ValueKey(key)));

  Future<void> tapAndWait(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      // Native picker and file operations complete outside fake frame time.
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('empty list permits importing but disables exporting', (
    tester,
  ) async {
    await mount(tester);
    expect(button(tester, 'ai-export-services').onPressed, isNull);
    expect(button(tester, 'ai-import-services').onPressed, isNotNull);
  });

  testWidgets('model service scrollbar follows the settings pane edge', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 360));
    await mount(tester);

    for (final width in [1200.0, 640.0]) {
      await tester.binding.setSurfaceSize(Size(width, 360));
      await tester.pumpAndSettle();
      final pane = tester.getRect(find.byType(AiServiceSettingsContent));
      final scrollView = tester.getRect(find.byType(CustomScrollView));
      final scrollbar = tester.getRect(find.byType(Scrollbar));
      final header = tester.getRect(find.byType(SettingsContentHeader));
      final pagePadding = SettingsContentLayout.pagePadding;
      final expectedContentWidth = (pane.width - pagePadding.horizontal).clamp(
        0.0,
        SettingsContentLayout.contentWidth,
      );
      expect(scrollView.right, pane.right);
      expect(scrollbar.right, pane.right);
      expect(header.center.dx, pane.center.dx);
      expect(header.width, expectedContentWidth);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('model services can be selected and deleted together', (
    tester,
  ) async {
    final first = await addService();
    Future<String> addNamed(String name) => scope.provider.saveService(
      name: name,
      protocol: AiApiProtocol.openAiChatCompletions,
      baseUrl: 'https://example.test/v1',
      models: ['model'],
      apiKey: 'test-key',
    );
    final retained = await addNamed('Retained service');
    final second = await addNamed('Second selected service');
    await tester.binding.setSurfaceSize(const Size(840, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester);
    const batchKey = 'ai-delete-selected-services';
    expect(find.byKey(const ValueKey(batchKey)), findsNothing);
    await tester.tap(find.text('Backup service'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Second selected service'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(button(tester, batchKey).label, 'Delete selected (2)');
    final batch = find.byKey(const ValueKey(batchKey));
    final add = find.byKey(const ValueKey('ai-add-service'));
    final firstCard = find.byKey(ValueKey('ai-service-card-$first'));
    expect(tester.getRect(batch).right, tester.getRect(firstCard).right);
    expect(tester.getRect(batch).left - tester.getRect(add).right, 8);
    expect(tester.getCenter(batch).dy, tester.getCenter(add).dy);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tapAndWait(tester, 'cancel-ai-service');
    expect(scope.provider.services, hasLength(3));
    expect(button(tester, batchKey).label, 'Delete selected (2)');
    await tapAndWait(tester, batchKey);
    await tapAndWait(tester, 'confirm-ai-service');
    expect(scope.provider.services.map((service) => service.id), [retained]);
    expect(scope.provider.hasServiceKey(retained), isTrue);
    expect(scope.provider.hasServiceKey(first), isFalse);
    expect(scope.provider.hasServiceKey(second), isFalse);
    expect(scope.provider.selectedModel, isNull);
    expect(find.byKey(const ValueKey(batchKey)), findsNothing);
  });

  testWidgets('dragging a model service selects it in the overlay and list', (
    tester,
  ) async {
    final ids = [
      for (final name in ['First service', 'Second service', 'Third service'])
        await scope.provider.saveService(
          name: name,
          protocol: AiApiProtocol.openAiChatCompletions,
          baseUrl: 'https://example.test/v1',
          models: ['model'],
          apiKey: 'test-key',
        ),
    ];
    await tester.binding.setSurfaceSize(const Size(840, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester);

    Set<String> selected() => tester
        .widget<DesktopCardSelectionRegion>(
          find.byType(DesktopCardSelectionRegion),
        )
        .selection
        .selected;
    final card = find.byKey(ValueKey('ai-service-card-${ids[1]}'));
    final handle = find.byKey(ValueKey('ai-drag-service-${ids[1]}'));
    final outline = find.ancestor(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.position == DecorationPosition.foreground,
      ),
    );
    Color outlineColor() {
      final decoration = tester.widget<DecoratedBox>(outline).decoration;
      return ((decoration as BoxDecoration).border! as Border).top.color;
    }

    await tester.tap(find.text('First service'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Third service'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selected(), {ids.first, ids.last});
    expect(outlineColor().a, 0);

    final start = tester.getCenter(handle);
    final drag = await tester.startGesture(
      start,
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(selected(), {ids.first, ids.last});
    await drag.moveBy(const Offset(0, 45));
    await tester.pumpAndSettle();
    expect(selected(), {ids[1]});
    expect(tester.getCenter(handle).dy, greaterThan(start.dy));
    expect(outlineColor(), theme.themeData.basePrimary);
    await drag.up();
    await tester.pumpAndSettle();
    expect(selected(), {ids[1]});
    expect(outlineColor(), theme.themeData.basePrimary);
    expect(scope.provider.services.map((service) => service.id), [
      ids.first,
      ids.last,
      ids[1],
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Third service'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final dragInPlace = await tester.startGesture(
      tester.getCenter(handle),
      kind: ui.PointerDeviceKind.mouse,
    );
    await dragInPlace.moveBy(const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(selected(), {ids[1], ids.last});
    expect(outlineColor(), theme.themeData.basePrimary);
    await dragInPlace.up();
    await tester.pumpAndSettle();
    expect(selected(), {ids[1], ids.last});
    expect(scope.provider.services.map((service) => service.id), [
      ids.first,
      ids.last,
      ids[1],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled picker leaves existing services and key unchanged', (
    tester,
  ) async {
    final id = await addService();
    await mount(tester);
    await tapAndWait(tester, 'ai-import-services');
    expect(scope.provider.services.single.id, id);
    expect(scope.provider.selectedModel, 'model-b');
    expect(scope.provider.hasServiceKey(id), isTrue);
    expect(
      find.byKey(const ValueKey('confirm-import-model-services')),
      findsNothing,
    );
  });

  testWidgets('pending picker disables both transfer controls', (tester) async {
    await addService();
    pickerGate = Completer<Object?>();
    await mount(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-import-services')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-import-services')));
    await tester.pump();
    expect(button(tester, 'ai-export-services').onPressed, isNull);
    expect(button(tester, 'ai-import-services').onPressed, isNull);
    pickerGate!.complete(null);
    await tester.pumpAndSettle();
    expect(button(tester, 'ai-export-services').onPressed, isNotNull);
  });

  testWidgets('cancelled import confirmation does not restore services', (
    tester,
  ) async {
    final id = await addService();
    final source = await scope.provider.exportServiceConfiguration();
    await tester.runAsync(() => backup.writeAsString(source));
    await scope.provider.removeService(id);
    pickerResult = [backup.path];
    await mount(tester);
    await tapAndWait(tester, 'ai-import-services');
    expect(
      find.byKey(const ValueKey('confirm-import-model-services')),
      findsOneWidget,
    );
    await tapAndWait(tester, 'cancel-import-model-services');
    expect(scope.provider.services, isEmpty);
    expect(scope.provider.hasServiceKey(id), isFalse);
  });

  testWidgets(
    'export and confirmed import restore selected model and credentials',
    (tester) async {
      final id = await addService();
      pickerResult = backup.path;
      await mount(tester);
      await tapAndWait(tester, 'ai-export-services');
      final exported = await tester.runAsync(() => backup.readAsString());
      final decoded = jsonDecode(exported!) as Map<String, dynamic>;
      expect(decoded['format'], 'lilygobox-model-services');
      expect(
        (decoded['services'] as List).single['apiKey'],
        'backup-test-secret',
      );
      expect(find.textContaining('backup-test-secret'), findsNothing);

      await scope.provider.removeService(id);
      await tester.pumpAndSettle();
      pickerResult = [backup.path];
      await tapAndWait(tester, 'ai-import-services');
      await tapAndWait(tester, 'confirm-import-model-services');
      expect(scope.provider.services.single.id, id);
      expect(scope.provider.selectedModel, 'model-b');
      expect(scope.provider.hasServiceKey(id), isTrue);
      expect(find.textContaining('backup-test-secret'), findsNothing);
      final restored =
          jsonDecode(await scope.provider.exportServiceConfiguration()) as Map;
      expect(
        (restored['services'] as List).single['apiKey'],
        'backup-test-secret',
      );
    },
  );
  if (const bool.fromEnvironment('CAPTURE_ASSISTANT_UI')) {
    testWidgets('captures the model service backup section', (tester) async {
      await addService();
      await mount(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('ai-import-services')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '${Directory.systemTemp.path}/lilygobox-model-service-backup-ui.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    });
  }
}
