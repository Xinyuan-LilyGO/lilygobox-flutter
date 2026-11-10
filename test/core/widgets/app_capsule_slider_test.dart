/*
 * @Description: 验证共享胶囊滑条的连续调节、离散等级和禁用行为。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 12:00:08
 * @LastEditTime: 2026-11-10 13:53:32
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/app_capsule_slider.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'effort follows dragging and snaps on release, reduced motion: $reducedMotion',
      (tester) async {
        var value = .5;
        double? committed;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, setState) => SizedBox(
                      width: 280,
                      child: AppCapsuleSlider(
                        theme: MaterialPalette.create(ThemeType.light),
                        value: value,
                        icon: Icons.psychology,
                        label: 'Reasoning effort',
                        divisions: 4,
                        snapToDivisions: true,
                        onChanged: (next) =>
                            setState(() => value = (next * 4).round() / 4),
                        onChangeEnd: (next) => committed = next,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final slider = find.byType(Slider);
        double position() => tester.widget<Slider>(slider).value;
        final rect = tester.getRect(slider);
        final pointer = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 160));
        await pointer.moveTo(
          Offset(rect.left + 18 + (rect.width - 36) * .63, rect.center.dy),
        );
        await tester.pump();
        expect(position(), closeTo(.63, .01));
        expect(committed, isNull);
        await pointer.up();
        await tester.pump();
        expect(committed, .75);
        if (!reducedMotion) {
          expect(position(), closeTo(.63, .01));
          await tester.pump(const Duration(milliseconds: 75));
          expect(position(), greaterThan(.63));
          expect(position(), lessThan(.75));
        }
        await tester.pumpAndSettle();
        expect(position(), .75);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(committed, .5);
        expect(position(), .5);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('continuous device slider preserves drag and disabled behavior', (
    tester,
  ) async {
    var value = .4;
    var changes = 0;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SizedBox(
                  width: 280,
                  child: AppCapsuleSlider(
                    theme: MaterialPalette.create(ThemeType.light),
                    value: value,
                    icon: Icons.volume_up,
                    label: 'Volume',
                    onChanged: enabled
                        ? (next) => setState(() {
                            value = next;
                            changes++;
                          })
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).divisions, isNull);
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * .73, rect.center.dy));
    await tester.pumpAndSettle();
    expect(value, closeTo(.73, .03));
    expect(changes, greaterThan(0));
    update(() => enabled = false);
    await tester.pumpAndSettle();
    final previous = changes;
    await tester.tapAt(rect.centerLeft + const Offset(10, 0));
    await tester.pumpAndSettle();
    expect(changes, previous);
  });

  testWidgets('discrete effort slider snaps before committing', (tester) async {
    var value = 0.0;
    double? committed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 280,
                child: AppCapsuleSlider(
                  theme: MaterialPalette.create(ThemeType.dark),
                  value: value,
                  icon: Icons.psychology,
                  label: 'Reasoning effort',
                  divisions: 4,
                  onChanged: (next) => setState(() => value = next),
                  onChangeEnd: (next) => committed = next,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.left + rect.width * .61, rect.center.dy));
    await tester.pumpAndSettle();
    expect(value, .5);
    expect(committed, .5);
    expect(tester.takeException(), isNull);
  });
}
