/*
 * @Description: 验证电池容量编辑的范围校验、保存等待及失败后输入保留。
 * @Author: LILYGO_L
 * @Date: 2026-10-13 00:00:00
 * @LastEditTime: 2026-10-13 00:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/presentation/widgets/battery_capacity_dialog.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'capacity editor validates and retains input after save failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final gate = Completer<bool>();
      int? sent;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => BatteryCapacityDialog(
                    theme: theme.themeData,
                    capacity: 1000,
                    minimum: 1,
                    maximum: 32767,
                    onSave: (value) {
                      sent = value;
                      return gate.future;
                    },
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent, isNull);
      expect(
        find.text('Enter a whole-number capacity within the range.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), '2000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent, 2000);
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryCapacityDialog), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse,
      );
      gate.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save. Check the device connection and try again.'),
        findsOneWidget,
      );
      expect(find.text('2000'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryCapacityDialog), findsNothing);
      expect(sent, 2000);
      expect(tester.takeException(), isNull);
    },
  );
}
