import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/bootstrap/startup.dart';
import 'package:lilygobox/app/widgets/window_frame.dart';
import 'package:lilygobox/core/storage/preferences.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:window_manager/window_manager.dart';

class _Storage implements PreferencesStorage {
  _Storage([this.value]);
  final String? value;
  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {}
}

void main() {
  for (final type in ThemeType.values) {
    testWidgets('startup uses saved ${type.name} theme on its first frame', (
      tester,
    ) async {
      final preferences = await AppPreferences.load(
        storage: _Storage('{"theme":"${type.name}"}'),
      );
      addTearDown(preferences.dispose);
      await tester.pumpWidget(AppStartup(preferences: preferences));
      expect(
        tester.widget<StartupScreen>(find.byType(StartupScreen)).themeType,
        type,
      );
      final background = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(StartupScreen),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(background.color, MaterialPalette.create(type).primary);
      final frame = find.descendant(
        of: find.byType(StartupScreen),
        matching: find.byType(AppWindowFrame),
      );
      expect(frame, findsOneWidget);
      final drag = find.descendant(
        of: frame,
        matching: find.byType(DragToMoveArea),
      );
      expect(drag, findsOneWidget);
      expect(tester.getTopLeft(drag), const Offset(10, 10));
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: frame, matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, BorderRadius.circular(10));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('startup waits at least three seconds before entering the app', (
    tester,
  ) async {
    final loaded = Completer<AppPreferences>();
    var requested = 0;
    await tester.pumpWidget(
      AppStartup(
        loadPreferences: () {
          requested++;
          return loaded.future;
        },
        applicationBuilder: (_) =>
            const ColoredBox(key: ValueKey('ready'), color: Colors.white),
      ),
    );
    expect(find.byType(StartupScreen), findsOneWidget);
    expect(requested, 1);
    expect(find.byKey(const ValueKey('ready')), findsNothing);
    final preferences = await AppPreferences.load(storage: _Storage());
    addTearDown(preferences.dispose);
    loaded.complete(preferences);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('ready')), findsOneWidget);
    expect(find.byType(StartupScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byType(StartupScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ready')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    final startup = find.byType(StartupScreen);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: startup, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(find.byType(StartupScreen), findsNothing);
    expect(requested, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late startup completion does not update a disposed screen', (
    tester,
  ) async {
    final loaded = Completer<AppPreferences>();
    await tester.pumpWidget(AppStartup(loadPreferences: () => loaded.future));
    await tester.pumpWidget(const SizedBox.shrink());
    loaded.complete(await AppPreferences.load(storage: _Storage()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
