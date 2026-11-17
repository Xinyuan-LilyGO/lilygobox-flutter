/*
 * @Description: 复用模型菜单、推理等级和提示浮层的完整无障碍交互流程。
 */
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/model_selector.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'assistant_test_scope.dart';

Future<void> runModelSelectorSemanticsScenario(WidgetTester tester) async {
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
  final service = await scope.provider.saveService(
    name: 'Models',
    protocol: AiApiProtocol.openAiResponses,
    baseUrl: 'https://example.test/v1',
    apiKey: 'test-key',
    models: ['gpt-6.1-sol', 'gpt-6-astra', 'custom-model'],
    serviceTiers: {
      'gpt-6.1-sol': ['priority'],
    },
  );
  await scope.provider.selectModel(service, 'gpt-6.1-sol');
  final semantics = tester.ensureSemantics();
  Future<void> frameTransition() async {
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ModelSelector(
            theme: theme.themeData,
            assistant: scope.provider,
          ),
        ),
      ),
    ),
  );
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer();
  for (var cycle = 0; cycle < 3; cycle++) {
    await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
    await frameTransition();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('ai-processing-speed-toggle')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await frameTransition();
    await tester.tap(find.byKey(const ValueKey('ai-reasoning-models')));
    await frameTransition();
    await tester.tap(find.byKey(ValueKey('ai-model-$service-gpt-6-astra')));
    await frameTransition();
    await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
    await frameTransition();
    await scope.provider.selectModel(service, 'gpt-6.1-sol');
    await frameTransition();
  }
  await mouse.removePointer();
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  semantics.dispose();
  scope.dispose();
  theme.dispose();
  language.dispose();
  shell.dispose();
  split.dispose();
}
