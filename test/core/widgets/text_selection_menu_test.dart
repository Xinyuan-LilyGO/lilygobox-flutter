/*
 * @Description: 验证公共文本右键菜单的剪切复制粘贴、只读限制和窗口边界。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 00:00:00
 * @LastEditTime: 2026-10-07 00:00:00
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/text_selection_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late ThemeProvider theme;
  String clipboard = '';
  setUp(() {
    theme = ThemeProvider();
    clipboard = 'paste value';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String;
              return null;
            case 'Clipboard.getData':
              return {'text': clipboard};
            case 'Clipboard.hasStrings':
              return {'value': clipboard.isNotEmpty};
          }
          return null;
        });
  });
  tearDown(() {
    ContextMenuController.removeAny();
    theme.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app(
    Widget field, {
    String locale = 'en',
    Alignment alignment = Alignment.center,
    bool windowFrame = false,
  }) => ChangeNotifierProvider.value(
    value: theme,
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: windowFrame
          ? (context, navigator) => Padding(
              padding: const EdgeInsets.all(10),
              child: Overlay.wrap(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Expanded(child: ClipRect(child: navigator!)),
                  ],
                ),
              ),
            )
          : null,
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: SizedBox(width: 240, child: field),
        ),
      ),
    ),
  );

  testWidgets(
    'right-click uses shared menu and preserves copy cut paste and shortcuts',
    (tester) async {
      final controller = TextEditingController(text: 'alpha beta');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          TextField(
            controller: controller,
            contextMenuBuilder: AppTextSelectionMenu.build,
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      final click = tester.getTopLeft(field) + const Offset(20, 20);
      await tester.tapAt(click, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuSurface), findsOneWidget);
      expect(find.byType(MenuItemSurface), findsWidgets);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard, 'alpha');
      expect(controller.text, 'alpha beta');
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      editable.showToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(controller.text, ' beta');
      expect(clipboard, 'alpha');
      clipboard = 'gamma';
      controller.selection = const TextSelection.collapsed(offset: 0);
      editable.showToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(controller.text, 'gamma beta');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(clipboard, 'gamma beta');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'menu hover uses click cursor and stays mounted inside window overlay',
    (tester) async {
      await tester.pumpWidget(
        app(
          TextField(contextMenuBuilder: AppTextSelectionMenu.build),
          windowFrame: true,
        ),
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(
        location: tester.getCenter(find.byType(TextField)),
      );
      addTearDown(mouse.removePointer);
      await tester.tap(find.byType(TextField), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final panel = find.byType(PopupMenuSurface);
      expect(panel, findsOneWidget);
      final element = tester.element(panel);
      await mouse.moveTo(tester.getTopLeft(panel) + const Offset(2, 2));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      final item = tester.getCenter(find.text('Paste'));
      await mouse.moveTo(item);
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.element(panel), same(element));
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );
      }
      await mouse.down(item);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(find.text('paste value'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'waits for clipboard status before showing the complete menu',
    (tester) async {
      final ready = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.hasStrings') return ready.future;
            return null;
          });
      await tester.pumpWidget(
        app(
          TextField(contextMenuBuilder: AppTextSelectionMenu.build),
          alignment: Alignment.bottomRight,
        ),
      );
      await tester.enterText(find.byType(TextField), 'selected text');
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      editable.showToolbar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(PopupMenuSurface), findsNothing);
      ready.complete({'value': true});
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuSurface), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'readonly selection offers copy without destructive operations',
    (tester) async {
      await tester.pumpWidget(
        app(
          SelectableText(
            'device-info',
            contextMenuBuilder: AppTextSelectionMenu.build,
          ),
          locale: 'zh',
        ),
      );
      await tester.tap(find.byType(SelectableText));
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 11,
      );
      editable.showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('剪切'), findsNothing);
      expect(find.text('粘贴'), findsNothing);
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(clipboard, 'device-info');
      expect(find.text('device-info'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'menu at lower right stays on screen in both themes and dismisses outside',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final mode in ThemeType.values) {
        theme.setTheme(mode);
        await tester.pumpWidget(
          app(
            TextField(
              key: ValueKey(mode),
              contextMenuBuilder: AppTextSelectionMenu.build,
            ),
            alignment: Alignment.bottomRight,
          ),
        );
        await tester.tapAt(
          const Offset(340, 230),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final panel = find.byType(PopupMenuSurface);
        expect(panel, findsOneWidget);
        final rect = tester.getRect(panel);
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(260));
        expect(rect.left, greaterThanOrEqualTo(0));
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
