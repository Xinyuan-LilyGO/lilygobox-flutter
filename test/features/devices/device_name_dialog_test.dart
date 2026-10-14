/*
 * @Description: 验证设备名称编辑的长度校验、保存等待及失败后输入保留。
 * @Author: LILYGO_L
 * @Date: 2026-10-13 00:00:00
 * @LastEditTime: 2026-10-13 00:00:00
 * @License: GPL 3.0
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_name_dialog.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

void main() {
  testWidgets('name editor validates and retains input after save failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    final gate = Completer<bool>();
    String? sent;
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
                builder: (_) => DeviceNameDialog(
                  theme: theme.themeData,
                  name: 'Original',
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
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sent, isNull);
    expect(
      find.text(
        'Enter a non-empty name within 64 UTF-8 bytes, without control characters.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField), 'New device');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sent, 'New device');
    expect(find.text('Saving…'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceNameDialog), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    gate.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not save the name. Check the device connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('New device'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceNameDialog), findsNothing);
    expect(sent, 'New device');
    expect(tester.takeException(), isNull);
  });
}
