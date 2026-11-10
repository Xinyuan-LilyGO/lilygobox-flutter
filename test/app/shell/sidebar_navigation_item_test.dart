/*
 * @Description: 验证导航灯条上下移动、连续切换和减少动画模式。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 14:46:40
 * @LastEditTime: 2026-11-10 14:46:40
 */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/shell/widgets/sidebar_navigation_item.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:provider/provider.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('indicator slides between rows, reduced motion: $reduced', (
      tester,
    ) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 220,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return SidebarNavigationGroup(
                          selectedIndex: selected,
                          children: [
                            for (var index = 0; index < 2; index++)
                              SidebarNavigationItem(
                                icon: Icons.home,
                                label: 'Page $index',
                                isSelected: selected == index,
                                showIndicator: false,
                                onPressed: () =>
                                    setState(() => selected = index),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final indicator = find.byKey(
        const ValueKey('sidebar-selection-indicator'),
      );
      final initial = tester.getRect(indicator);
      expect(initial.top, 3);
      expect(initial.height, 36);
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      if (reduced) {
        expect(tester.getTopLeft(indicator).dy, 45);
      } else {
        expect(tester.getTopLeft(indicator).dy, initial.top);
        await tester.pump(const Duration(milliseconds: 100));
        final halfway = tester.getTopLeft(indicator).dy;
        expect(halfway, greaterThan(initial.top));
        expect(halfway, lessThan(45));
        update(() => selected = 0);
        await tester.pump();
        expect(tester.getTopLeft(indicator).dy, closeTo(halfway, .01));
        await tester.pumpAndSettle();
        expect(tester.getRect(indicator), initial);
        await tester.tap(find.text('Page 1'));
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(indicator).dy, 45);
      expect(tester.getSize(indicator).height, 36);
      expect(indicator, findsOneWidget);
      update(() => selected = 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(indicator), initial);
      expect(tester.takeException(), isNull);
    });
  }
}
