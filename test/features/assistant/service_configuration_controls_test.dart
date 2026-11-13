import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/service_settings_content.dart';
import 'package:lilygobox/features/assistant/state/provider.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
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
