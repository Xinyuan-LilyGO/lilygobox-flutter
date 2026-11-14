import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/right_click_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';

void main() {
  Future<RightClickMenuController> mountMenu(
    WidgetTester tester, {
    bool openAbove = false,
    double scale = 1,
    Rect anchor = const Rect.fromLTWH(0, 100, 800, 480),
  }) async {
    final theme = ThemeProvider();
    addTearDown(theme.dispose);
    final controller = RightClickMenuController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fromRect(
                rect: anchor,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: Builder(
                    builder: (context) => RightClickMenuBuilder.buildMenuAnchor(
                      context: context,
                      controller: controller,
                      theme: theme.themeData,
                      openAbove: openAbove,
                      onSecondaryTap: () {},
                      menuItems: [
                        for (var index = 0; index < 7; index++)
                          RightClickMenuItem(
                            label: 'Action $index',
                            onTap: controller.close,
                            showDivider: index == 5,
                          ),
                      ],
                      child: const ColoredBox(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  // Seven 28px rows, 10px outer padding, five 4px gaps and one 9px divider gap.
  const menuHeight = 235.0;

  testWidgets(
    'bottom overflow is flipped around pointer instead of tall anchor top',
    (tester) async {
      await mountMenu(tester);
      const pointer = Offset(400, 530);
      await tester.tapAt(pointer, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(PopupMenuSurface));
      expect(menu.top, closeTo(pointer.dy + 8 - menuHeight, .01));
      expect(menu.left, pointer.dx);
      expect(menu.height, menuHeight);
      expect(menu.bottom, lessThanOrEqualTo(592));
    },
  );

  testWidgets(
    'right overflow flips around pointer and respects eight pixel inset',
    (tester) async {
      final controller = await mountMenu(tester);
      await tester.tapAt(
        const Offset(760, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(PopupMenuSurface)).topLeft,
        const Offset(610, 192),
      );
      controller.close();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 200), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PopupMenuSurface)).left, 8);
    },
  );

  testWidgets(
    'unconstrained pointer positioning remains unchanged inside scaled anchor',
    (tester) async {
      await mountMenu(tester, scale: .5);
      await tester.tapAt(
        const Offset(250, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(PopupMenuSurface));
      expect(menu.topLeft, const Offset(250, 192));
      expect(menu.width, 150);
    },
  );

  testWidgets('openAbove still uses anchor location regardless of pointer', (
    tester,
  ) async {
    final controller = await mountMenu(
      tester,
      openAbove: true,
      anchor: const Rect.fromLTWH(300, 400, 120, 120),
    );
    await tester.tapAt(const Offset(310, 410), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byType(PopupMenuSurface));
    expect(first.topLeft, const Offset(300, 157));
    controller.close();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 500), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(PopupMenuSurface)), first);
  });
}
