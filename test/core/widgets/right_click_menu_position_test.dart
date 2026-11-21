import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/right_click_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<RightClickMenuController> mountMenu(
    WidgetTester tester, {
    bool openAbove = false,
    int itemCount = 7,
    double scale = 1,
    Rect anchor = const Rect.fromLTWH(0, 100, 800, 480),
    bool fitWidthToItems = false,
    String? label,
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
                      fitWidthToItems: fitWidthToItems,
                      onSecondaryTap: () {},
                      menuItems: [
                        for (var index = 0; index < itemCount; index++)
                          RightClickMenuItem(
                            label: label ?? 'Action $index',
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

  testWidgets('adaptive menu keeps short labels at the shared minimum', (
    tester,
  ) async {
    await mountMenu(tester, fitWidthToItems: true, label: 'Copy', itemCount: 1);
    await tester.tapAt(const Offset(400, 200), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(PopupMenuSurface));
    expect(menu.size, const Size(150, 38));
  });

  testWidgets('adaptive right-edge positioning uses the measured width', (
    tester,
  ) async {
    await mountMenu(
      tester,
      fitWidthToItems: true,
      label: 'Manage chat history and context',
      itemCount: 1,
    );
    const pointer = Offset(760, 200);
    await tester.tapAt(pointer, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(PopupMenuSurface));
    expect(menu.width, greaterThan(150));
    expect(menu.right, closeTo(pointer.dx, .01));
    expect(menu.height, 38);
  });

  testWidgets('adaptive menu fits a narrow window without wrapping', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 600);
    addTearDown(tester.view.reset);
    await mountMenu(
      tester,
      fitWidthToItems: true,
      label: 'Manage chat history and context',
      itemCount: 1,
    );
    await tester.tapAt(const Offset(100, 200), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(PopupMenuSurface));
    expect(menu.left, 8);
    expect(menu.right, 192);
    expect(menu.height, 38);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'card menu builds its items on demand and uses the current item count',
    (tester) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final controller = RightClickMenuController();
      var builds = 0;
      var count = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => RightClickMenuBuilder.buildMenuAnchor(
                context: context,
                controller: controller,
                theme: theme.themeData,
                onSecondaryTap: () {},
                menuItemsBuilder: () {
                  builds++;
                  return [
                    for (var index = 0; index < count; index++)
                      RightClickMenuItem(label: 'Action $index'),
                  ];
                },
                child: const ColoredBox(
                  color: Colors.white,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(builds, 0);
      count = 7;
      await tester.tapAt(
        const Offset(100, 150),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Action 6'), findsOneWidget);
      expect(builds, greaterThan(0));
    },
  );

  testWidgets(
    'overflowing menu reserves scrollbar space outside item targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(880, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mountMenu(tester, itemCount: 24);
      await tester.tapAt(
        const Offset(400, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(PopupMenuSurface));
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(scroll.viewportDimension, lessThanOrEqualTo(640));
      expect(scroll.maxScrollExtent, greaterThan(0));
      final firstItem = tester.getRect(
        find
            .ancestor(
              of: find.text('Action 0'),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(firstItem.right, lessThanOrEqualTo(panel.right - 20));
      expect(tester.takeException(), isNull);
    },
  );

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
