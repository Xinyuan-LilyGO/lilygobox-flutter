import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/core/widgets/dialog_style.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';

void main() {
  for (final type in ThemeType.values) {
    for (final embedded in [false, true]) {
      testWidgets('dialog actions share style ($type/embedded:$embedded)', (
        tester,
      ) async {
        final theme = MaterialPalette.create(type);
        final surface = type == ThemeType.light
            ? Colors.white
            : AppDialogStyle.backgroundColor(theme);
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppActionButton(
              key: const ValueKey('secondary'),
              theme: theme,
              label: 'Cancel',
              onPressed: () {},
            ),
            AppActionButton(
              key: const ValueKey('primary'),
              theme: theme,
              label: 'Save',
              primary: true,
              onPressed: () {},
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: embedded
                    ? AppDialogScope(surfaceColor: surface, child: actions)
                    : Dialog(backgroundColor: surface, child: actions),
              ),
            ),
          ),
        );
        MenuItemSurface button(String key) => tester.widget<MenuItemSurface>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(MenuItemSurface),
          ),
        );
        expect(
          button('secondary').backgroundColor,
          type == ThemeType.light
              ? Color.lerp(surface, theme.textColorPrimary, .06)
              : theme.settingsControlBackgroundColor,
        );
        expect(button('primary').backgroundColor, theme.basePrimary);
        expect(tester.widget<Text>(find.text('Cancel')).style?.fontSize, 12);
        expect(tester.widget<Text>(find.text('Save')).style?.fontSize, 12);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
