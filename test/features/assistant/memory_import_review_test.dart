import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/core/widgets/confirmation_dialog.dart';
import 'package:lilygobox/core/widgets/settings/select.dart';
import 'package:lilygobox/features/assistant/domain/memory_conflict.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/memory_import_review.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

MemoryImportItem memory(
  int index, {
  bool conflict = false,
  bool duplicate = false,
}) => MemoryImportItem(
  incoming: {
    'id': 'incoming-$index',
    'owner': 'agent',
    'content':
        'Incoming memory $index. ${List.filled(20, 'A long fact with complete details.').join(' ')}',
  },
  target: 'agent',
  existing: conflict || duplicate
      ? {
          'id': 'existing-$index',
          'owner': 'agent',
          'content': 'Existing memory $index',
        }
      : null,
  duplicate: duplicate,
);

Future<void> openReview(
  WidgetTester tester,
  List<MemoryImportItem> items, {
  ThemeType type = ThemeType.light,
  Size size = const Size(900, 900),
  double scale = 1,
  ValueChanged<bool>? onResult,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = ThemeProvider()..setTheme(type);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: appLocalizationDelegates,
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final accepted = await reviewMemoryImport(
                context,
                theme.themeData,
                items,
              );
              onResult?.call(accepted);
            },
            child: const Text('Open review'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

void main() {
  for (final type in ThemeType.values) {
    for (final compact in [false, true]) {
      testWidgets(
        'memory import review fits ${type.name} ${compact ? 'compact large text' : 'normal'}',
        (tester) async {
          final items = [
            for (var i = 0; i < 12; i++)
              memory(i, conflict: i.isEven, duplicate: i % 3 == 0),
          ];
          await openReview(
            tester,
            items,
            type: type,
            size: compact ? const Size(420, 620) : const Size(900, 900),
            scale: compact ? 1.5 : 1,
          );
          expect(tester.takeException(), isNull);
          expect(find.textContaining('SHA-256'), findsNothing);
          final list = find.byKey(const ValueKey('memory-review-list'));
          final dialog = find.byType(AppDialog);
          final cancel = find.byKey(const ValueKey('memory-review-cancel'));
          final confirm = find.byKey(const ValueKey('memory-review-import'));
          final dialogRect = tester.getRect(dialog);
          final cancelRect = tester.getRect(cancel);
          final confirmRect = tester.getRect(confirm);
          final scrollable = find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('memory-review-card-11')),
            240,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(dialog), dialogRect);
          expect(tester.getRect(cancel), cancelRect);
          expect(tester.getRect(confirm), confirmRect);
          expect(cancel.hitTestable(), findsOneWidget);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
        },
      );
    }
  }

  testWidgets(
    'cancelling discards resolution changes and review has no editor',
    (tester) async {
      final item = memory(0, conflict: true);
      final originalContent = item.content;
      final originalResolution = item.resolution;
      bool? accepted;
      await openReview(tester, [item], onResult: (value) => accepted = value);
      await tester.tap(
        find.byKey(const ValueKey('memory-review-resolution-0')),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(AppDialog)));
      await tester.tap(find.text(l.agentMemoryBoth).last);
      await tester.pumpAndSettle();
      expect(
        item.resolution,
        originalResolution,
        reason: 'resolution stays a draft until import',
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('memory-review-edit-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('memory-review-cancel')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(item.content, originalContent);
      expect(item.resolution, originalResolution);
    },
  );

  testWidgets(
    'import preserves memory content and commits chosen conflict resolution',
    (tester) async {
      final item = memory(0, conflict: true);
      bool? accepted;
      await openReview(tester, [item], onResult: (value) => accepted = value);
      await tester.tap(
        find.byKey(const ValueKey('memory-review-resolution-0')),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(AppDialog)));
      await tester.tap(find.text(l.agentMemoryReplace).last);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('memory-review-import')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(item.content, item.incoming['content']);
      expect(item.resolution, MemoryResolution.replace);
    },
  );

  testWidgets('identical entries stay skipped without editable controls', (
    tester,
  ) async {
    final item = memory(0, duplicate: true);
    await openReview(tester, [item]);
    expect(
      find.byKey(const ValueKey('memory-review-resolution-0')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('memory-review-edit-0')), findsNothing);
    expect(find.byType(SettingSelect<MemoryResolution>), findsNothing);
    // Other package contents may still be imported when all memories skip.
    await tester.tap(find.byKey(const ValueKey('memory-review-import')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(item.resolution, MemoryResolution.skip);
    expect(tester.takeException(), isNull);
  });
}
