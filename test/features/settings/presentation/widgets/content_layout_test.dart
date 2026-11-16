import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/settings/presentation/widgets/content_layout.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'settings information cards share compact padding and grow with text',
    (tester) async {
      final themes = ThemeProvider();
      addTearDown(themes.dispose);
      for (final width in [760.0, 360.0]) {
        for (final scale in [1.0, 1.5]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SettingsSection(
                            theme: themes.themeData,
                            title: 'Copyright',
                            description: 'LilygoBox 2026 LILYGO Corporation',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final card = tester.getRect(find.byType(SettingsPanel));
          final title = tester.getRect(find.text('Copyright'));
          final description = tester.getRect(
            find.text('LilygoBox 2026 LILYGO Corporation'),
          );
          expect(title.left - card.left, 16);
          expect(title.top - card.top, 10);
          expect(card.bottom - description.bottom, closeTo(10, .01));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
