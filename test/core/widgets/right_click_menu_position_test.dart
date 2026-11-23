import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/context_menu/right_click_menu.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_transition.dart';
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
    List<RightClickMenuItem>? items,
    ThemeProvider? themeProvider,
  }) async {
    final theme = themeProvider ?? ThemeProvider();
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
                      menuItems:
                          items ??
                          [
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

  List<RightClickMenuItem> cascadingItems() => [
    RightClickMenuItem(
      label: 'Character',
      icon: Icons.badge_outlined,
      children: [RightClickMenuItem(label: 'Character details', onTap: () {})],
    ),
    RightClickMenuItem(label: 'Copy', icon: Icons.copy, onTap: () {}),
    RightClickMenuItem(
      label: 'Storage',
      icon: Icons.storage,
      children: [
        RightClickMenuItem(label: 'Manage stored conversations', onTap: () {}),
      ],
    ),
  ];

  for (final opensLeft in [false, true]) {
    testWidgets(
      'submenu leaves a gap and stays open while crossing it on the ${opensLeft ? 'left' : 'right'}',
      (tester) async {
        await mountMenu(tester, fitWidthToItems: true, items: cascadingItems());
        await tester.tapAt(
          Offset(opensLeft ? 760 : 140, 200),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final group = find.text('Storage');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(group));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pumpAndSettle();
        final panels = find.byType(PopupMenuSurface);
        expect(panels, findsNWidgets(2));
        final root = tester.getRect(panels.first);
        final submenu = tester.getRect(panels.last);
        final (gapLeft, gapRight) = opensLeft
            ? (submenu.right, root.left)
            : (root.right, submenu.left);
        expect(gapRight - gapLeft, 8);
        await mouse.moveTo(
          Offset((gapLeft + gapRight) / 2, tester.getCenter(group).dy),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(panels, findsNWidgets(2));
        final action = find.text('Manage stored conversations');
        await mouse.moveTo(tester.getCenter(action));
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        await mouse.removePointer();
      },
    );
  }

  testWidgets(
    'clicking an already open submenu category leaves its panel open',
    (tester) async {
      await mountMenu(tester, items: cascadingItems());
      await tester.tapAt(
        const Offset(150, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final category = tester.getCenter(find.text('Character'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(category);
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();
      final details = find.text('Character details');
      expect(details.hitTestable(), findsOneWidget);
      final panel = tester.element(find.byType(PopupMenuSurface).last);

      for (var click = 0; click < 2; click++) {
        await mouse.down(category);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(details.hitTestable(), findsOneWidget);
        expect(tester.element(find.byType(PopupMenuSurface).last), same(panel));
      }

      await mouse.moveTo(const Offset(30, 50));
      await mouse.down(const Offset(30, 50));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuSurface), findsNothing);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'a centered context menu reserves space for a long submenu in a narrow window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 400);
      addTearDown(tester.view.reset);
      await mountMenu(tester, fitWidthToItems: true, items: cascadingItems());
      await tester.tapAt(
        const Offset(180, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storage'));
      await tester.pumpAndSettle();
      final panels = find.byType(PopupMenuSurface);
      expect(panels, findsNWidgets(2));
      final root = tester.getRect(panels.first);
      final submenu = tester.getRect(panels.last);
      expect(
        submenu.left >= root.right + 8 || submenu.right <= root.left - 8,
        isTrue,
        reason: 'The root $root and submenu $submenu must not overlap.',
      );
      expect(
        find.text('Manage stored conversations').hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'only the active submenu is highlighted and both icons use its foreground',
    (tester) async {
      final theme = ThemeProvider();
      await mountMenu(tester, items: cascadingItems(), themeProvider: theme);
      await tester.tapAt(
        const Offset(150, 200),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final character = find.text('Character');
      final storage = find.text('Storage');
      final details = find.text('Character details');
      final storedChats = find.text('Manage stored conversations');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);

      Future<void> hover(Finder item) async {
        await mouse.moveTo(tester.getCenter(item));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pumpAndSettle();
      }

      Color? iconColor(Finder group, IconData symbol) {
        final button = find.ancestor(
          of: group,
          matching: find.byType(SubmenuButton),
        );
        final icon = find.descendant(of: button, matching: find.byIcon(symbol));
        return IconTheme.of(tester.element(icon)).color;
      }

      await hover(character);
      expect(details, findsOneWidget);
      expect(iconColor(character, Icons.badge_outlined), Colors.white);
      expect(iconColor(character, Icons.chevron_right), Colors.white);
      await hover(storage);
      expect(details, findsNothing);
      expect(storedChats, findsOneWidget);
      expect(iconColor(character, Icons.chevron_right), isNot(Colors.white));
      expect(iconColor(storage, Icons.storage), Colors.white);
      await hover(find.text('Copy'));
      expect(find.byType(PopupMenuSurface), findsOneWidget);
      expect(iconColor(storage, Icons.storage), isNot(Colors.white));
      expect(iconColor(storage, Icons.chevron_right), isNot(Colors.white));
      final storageButton = tester.widget<TextButton>(
        find.ancestor(of: storage, matching: find.byType(TextButton)),
      );
      expect(storageButton.focusNode?.hasFocus, isTrue);
      const focused = {WidgetState.focused};
      expect(
        storageButton.style?.overlayColor?.resolve(focused),
        Colors.transparent,
      );
      expect(
        storageButton.style?.backgroundColor?.resolve(focused),
        Colors.transparent,
      );
      expect(
        DefaultTextStyle.of(tester.element(storage)).style.color,
        theme.themeData.textColorSecondary,
      );
      await mouse.removePointer();
    },
  );

  testWidgets('submenu uses the shared menu entrance animation', (
    tester,
  ) async {
    await mountMenu(tester, items: cascadingItems());
    await tester.tapAt(const Offset(150, 200), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Character'));
    await tester.pump();

    final panels = find.byType(PopupMenuSurface);
    expect(panels, findsNWidgets(2));
    final submenuTransition = find
        .ancestor(of: panels.last, matching: find.byType(PopupMenuTransition))
        .first;
    final fade = find.descendant(
      of: submenuTransition,
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    await tester.pump(PopupMenuTransition.duration ~/ 2);
    expect(tester.widget<FadeTransition>(fade).opacity.value, closeTo(.5, .01));
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(find.text('Character details').hitTestable(), findsOneWidget);
  });

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
