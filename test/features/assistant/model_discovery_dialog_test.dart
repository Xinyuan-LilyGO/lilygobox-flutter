import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/model_discovery_dialog.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late ThemeProvider theme;
  setUp(() => theme = ThemeProvider());
  tearDown(() => theme.dispose());

  Future<void> open(
    WidgetTester tester,
    Future<AiModelCatalog> Function(Future<void>) load, {
    ValueChanged<AiModelCatalog?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        theme: ThemeData(platform: TargetPlatform.windows),
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<AiModelCatalog>(
                  context: context,
                  barrierDismissible: true,
                  builder: (context) => ModelDiscoveryDialog(
                    theme: theme.themeData,
                    existingModels: const {'existing'},
                    load: load,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  bool selected(WidgetTester tester, Finder row) => tester
      .widget<Semantics>(
        find.ancestor(of: row, matching: find.byType(Semantics)).first,
      )
      .properties
      .selected!;

  Future<void> controlTap(WidgetTester tester, Finder row) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(row);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  for (final type in [ThemeType.light, ThemeType.dark]) {
    testWidgets('model cards select without checkboxes in ${type.name}', (
      tester,
    ) async {
      theme.setTheme(type);
      AiModelCatalog? applied;
      await open(
        tester,
        (_) async => AiModelCatalog(
          models: ['existing', 'first', 'second'],
          imageInputs: {
            'existing': AiImageInput.supported,
            'first': AiImageInput.unsupported,
            'second': AiImageInput.supported,
          },
          serviceTiers: {
            'first': ['priority'],
            'second': ['ultrafast'],
          },
        ),
        onResult: (result) => applied = result,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      final first = find.byKey(const ValueKey('ai-model-discovery-row-first'));
      expect(selected(tester, first), isTrue);
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: first,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .border!
            .top
            .color,
        theme.themeData.basePrimary,
      );
      expect(
        find.descendant(of: first, matching: find.byType(MenuItemSurface)),
        findsNothing,
      );
      expect(
        find.descendant(of: first, matching: find.byType(InkWell)),
        findsNothing,
      );
      await controlTap(tester, first);
      expect(selected(tester, first), isFalse);
      await tester.tap(find.byKey(const ValueKey('ai-apply-model-discovery')));
      await tester.pumpAndSettle();
      expect(applied!.models, ['existing', 'second']);
      expect(
        applied!.imageInputs.keys,
        unorderedEquals(['existing', 'second']),
      );
      expect(applied!.serviceTiers, {
        'second': ['ultrafast'],
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no selection disables adding models and long lists scroll', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => AiModelCatalog(
        models: List.generate(65, (index) => 'model-$index'),
        imageInputs: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsOneWidget);
    final last = find.byKey(const ValueKey('ai-model-discovery-row-model-64'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await controlTap(tester, last);
    expect(selected(tester, last), isFalse);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await open(
      tester,
      (_) async => AiModelCatalog(models: ['only'], imageInputs: {}),
    );
    await tester.pumpAndSettle();
    await controlTap(
      tester,
      find.byKey(const ValueKey('ai-model-discovery-row-only')),
    );
    expect(
      tester
          .widget<AppActionButton>(
            find.byKey(const ValueKey('ai-apply-model-discovery')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('model cards share recycle bin range and keyboard selection', (
    tester,
  ) async {
    AiModelCatalog? applied;
    await open(
      tester,
      (_) async => AiModelCatalog(
        models: ['first', 'second', 'third', 'fourth'],
        imageInputs: {},
      ),
      onResult: (result) => applied = result,
    );
    await tester.pumpAndSettle();
    Finder row(String name) =>
        find.byKey(ValueKey('ai-model-discovery-row-$name'));
    await tester.tap(row('second'));
    await tester.pumpAndSettle();
    expect(selected(tester, row('first')), isFalse);
    expect(selected(tester, row('second')), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row('fourth'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    for (final name in ['second', 'third', 'fourth']) {
      expect(selected(tester, row(name)), isTrue);
    }
    await controlTap(tester, row('third'));
    expect(selected(tester, row('third')), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selected(tester, row('first')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ModelDiscoveryDialog), findsOneWidget);
    for (final name in ['first', 'second', 'third', 'fourth']) {
      expect(selected(tester, row(name)), isFalse);
    }
    await tester.tap(row('second'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-apply-model-discovery')));
    await tester.pumpAndSettle();
    expect(applied!.models, ['second']);
  });

  testWidgets('model context menu shares the keyboard selection', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => AiModelCatalog(models: ['first', 'second'], imageInputs: {}),
    );
    final first = find.byKey(const ValueKey('ai-model-discovery-row-first'));
    final second = find.byKey(const ValueKey('ai-model-discovery-row-second'));
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(second, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(selected(tester, first), isTrue);
    expect(selected(tester, second), isFalse);
    expect(find.byIcon(Symbols.check_box), findsOneWidget);
    expect(find.byIcon(Symbols.select_all), findsOneWidget);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(selected(tester, first), isTrue);
    expect(selected(tester, second), isTrue);
    await tester.tap(first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Symbols.check_box_outline_blank), findsOneWidget);
    await tester.tap(find.text('Deselect'));
    await tester.pumpAndSettle();
    expect(selected(tester, first), isFalse);
    expect(selected(tester, second), isTrue);
    await tester.tap(second, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(selected(tester, first), isTrue);
    expect(selected(tester, second), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected(tester, first), isFalse);
    expect(selected(tester, second), isFalse);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('model scroll channel preserves card edges at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(520, 680);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(
        tester,
        (_) async => AiModelCatalog(
          models: List.generate(65, (index) => 'provider/model-$index'),
          imageInputs: {},
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byKey(const ValueKey('ai-model-discovery-scroll'));
      final viewport = tester.getRect(scroll);
      final summary = find.byKey(const ValueKey('ai-model-discovery-summary'));
      final heading = find.byKey(
        const ValueKey('ai-model-discovery-list-heading'),
      );
      final summaryBounds = tester.getRect(summary);
      final headingBounds = tester.getRect(heading);
      final titleBounds = tester.getRect(find.text('Fetch models'));
      expect(summaryBounds.bottom, lessThanOrEqualTo(viewport.top));
      expect(headingBounds.bottom, lessThanOrEqualTo(viewport.top));
      expect(find.descendant(of: scroll, matching: summary), findsNothing);
      expect(find.descendant(of: scroll, matching: heading), findsNothing);
      final surface = tester.getRect(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(viewport.left, surface.left);
      expect(viewport.right, surface.right);
      expect(
        tester.widget<SingleChildScrollView>(scroll).padding,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      );
      final scrollbarTheme = ScrollbarTheme.of(tester.element(scroll));
      expect(scrollbarTheme.crossAxisMargin, 6);
      expect(scrollbarTheme.mainAxisMargin, 6);
      expect(scrollbarTheme.thumbVisibility?.resolve({}), isNot(true));
      expect(
        find.descendant(of: scroll, matching: find.byType(Scrollbar)),
        findsOneWidget,
      );
      for (final index in [0, 64]) {
        final row = find.byKey(
          ValueKey('ai-model-discovery-row-provider/model-$index'),
        );
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(tester.getRect(summary), summaryBounds);
        expect(tester.getRect(heading), headingBounds);
        expect(tester.getRect(find.text('Fetch models')), titleBounds);
        final bounds = tester.getRect(row);
        expect(bounds.left, greaterThanOrEqualTo(viewport.left + 24));
        expect(bounds.right, lessThanOrEqualTo(viewport.right - 24));
        expect(bounds.top, greaterThanOrEqualTo(viewport.top));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(
          bounds.bottom,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('ai-apply-model-discovery')),
                )
                .dy,
          ),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in [ThemeType.light, ThemeType.dark]) {
    testWidgets(
      'selection border fades without press effects in ${type.name}',
      (tester) async {
        theme.setTheme(type);
        await open(
          tester,
          (_) async => AiModelCatalog(models: ['only'], imageInputs: {}),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('ai-model-discovery-row-only'));
        final bounds = tester.getRect(row);
        final animation = tester.widget<AnimatedContainer>(
          find.descendant(of: row, matching: find.byType(AnimatedContainer)),
        );
        expect(animation.duration, const Duration(milliseconds: 167));
        expect(animation.curve, Curves.fastOutSlowIn);
        Color borderColor() =>
            (tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: row,
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
                .top
                .color;
        expect(borderColor(), theme.themeData.basePrimary);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(row);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(borderColor(), theme.themeData.basePrimary);
        await tester.pump(const Duration(milliseconds: 80));
        expect(borderColor(), isNot(theme.themeData.basePrimary));
        expect(borderColor().a, greaterThan(0));
        expect(tester.getRect(row), bounds);
        await tester.pumpAndSettle();
        expect(borderColor().a, 0);
        await tester.tap(row);
        await tester.pump();
        expect(borderColor().a, 0);
        await tester.pump(const Duration(milliseconds: 80));
        expect(borderColor().a, greaterThan(0));
        expect(borderColor(), isNot(theme.themeData.basePrimary));
        await tester.pumpAndSettle();
        expect(borderColor(), theme.themeData.basePrimary);
        expect(tester.getRect(row), bounds);
        expect(
          find.descendant(of: row, matching: find.byType(InkWell)),
          findsNothing,
        );
      },
    );
  }

  for (final action in ['outside', 'button', 'escape']) {
    testWidgets('$action cancels discovery and ignores late results', (
      tester,
    ) async {
      final gate = Completer<AiModelCatalog>();
      var cancelled = false;
      await open(tester, (abort) {
        unawaited(abort.then((_) => cancelled = true));
        return gate.future;
      });
      expect(find.text('Reading model list…'), findsOneWidget);
      switch (action) {
        case 'outside':
          await tester.tapAt(const Offset(5, 5));
        case 'button':
          await tester.tap(
            find.byKey(const ValueKey('ai-cancel-model-discovery')),
          );
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.byType(ModelDiscoveryDialog), findsNothing);
      gate.complete(AiModelCatalog(models: ['late-model'], imageInputs: {}));
      await tester.pumpAndSettle();
      expect(find.text('late-model'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty catalog differs from unchanged catalog', (tester) async {
    await open(
      tester,
      (_) async => AiModelCatalog(models: [], imageInputs: {}),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The service returned no available models.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-apply-model-discovery')),
      findsNothing,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await open(
      tester,
      (_) async => AiModelCatalog(models: ['existing'], imageInputs: {}),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Found 1 models: 0 new, 1 already listed.'),
      findsOneWidget,
    );
    expect(
      find.text('No new models. Your existing list is unchanged.'),
      findsOneWidget,
    );
    expect(find.text('Update model information'), findsOneWidget);
  });

  testWidgets('failure remains dismissible and never offers apply', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => throw const AiConfigurationException(AiProblem.keyRequired),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-apply-model-discovery')),
      findsNothing,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(ModelDiscoveryDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
