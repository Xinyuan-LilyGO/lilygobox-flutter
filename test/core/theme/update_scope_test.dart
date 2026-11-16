/*
 * @Description: 验证隐藏页面不接收主题过渡帧，恢复显示后同步最新配色并保留状态。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/update_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _ThemeProbe extends StatefulWidget {
  const _ThemeProbe({super.key});

  @override
  State<_ThemeProbe> createState() => _ThemeProbeState();
}

class _ThemeProbeState extends State<_ThemeProbe> {
  int builds = 0;
  late AppTheme palette;
  late Brightness brightness;
  late String fontChoice;
  Color? defaultTextColor;

  @override
  Widget build(BuildContext context) {
    builds++;
    final source = context.watch<ThemeProvider>();
    palette = source.themeData;
    fontChoice = source.fontChoice;
    brightness = Theme.of(context).brightness;
    defaultTextColor = DefaultTextStyle.of(context).style.color;
    return ColoredBox(color: palette.primary);
  }
}

void main() {
  testWidgets(
    'hidden page skips theme frames and resumes with retained State',
    (tester) async {
      final source = ThemeProvider(vsync: tester);
      final active = ValueNotifier(true);
      addTearDown(source.dispose);
      addTearDown(active.dispose);
      const probeKey = ValueKey('retained-probe');
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: source,
          child: Consumer<ThemeProvider>(
            child: ValueListenableBuilder<bool>(
              valueListenable: active,
              child: const _ThemeProbe(key: probeKey),
              builder: (context, visible, child) =>
                  ThemeUpdateScope(active: visible, child: child!),
            ),
            builder: (context, provider, child) => MaterialApp(
              theme: ThemeData(
                brightness: provider.currentTheme == ThemeType.light
                    ? Brightness.light
                    : Brightness.dark,
              ),
              themeAnimationDuration: ThemeProvider.transitionDuration,
              builder: (context, navigator) => DefaultTextStyle(
                style: TextStyle(color: provider.themeData.textColorPrimary),
                child: navigator!,
              ),
              home: child,
            ),
          ),
        ),
      );
      final retained = tester.state<_ThemeProbeState>(find.byKey(probeKey));
      active.value = false;
      await tester.pump();
      final hiddenBuilds = retained.builds;
      final hiddenPalette = retained.palette;
      final hiddenTextColor = retained.defaultTextColor;
      source.setTheme(ThemeType.dark);
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(retained.builds, hiddenBuilds);
      expect(identical(retained.palette, hiddenPalette), isTrue);
      expect(retained.brightness, Brightness.light);
      expect(retained.defaultTextColor, hiddenTextColor);
      source.setFontChoice('inter');
      await tester.pump();
      expect(retained.builds, hiddenBuilds);
      expect(retained.fontChoice, 'system');
      active.value = true;
      await tester.pump();
      expect(tester.state(find.byKey(probeKey)), same(retained));
      expect(retained.palette, same(source.themeData));
      expect(retained.brightness, Brightness.dark);
      expect(retained.defaultTextColor, source.themeData.textColorPrimary);
      expect(retained.fontChoice, 'inter');
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'visible page keeps intermediate palette frames and source actions',
    (tester) async {
      final source = ThemeProvider(vsync: tester);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: source,
          child: const MaterialApp(
            home: ThemeUpdateScope(active: true, child: _ThemeProbe()),
          ),
        ),
      );
      final probe = tester.state<_ThemeProbeState>(find.byType(_ThemeProbe));
      final initial = probe.palette;
      final context = tester.element(find.byType(_ThemeProbe));
      expect(context.read<ThemeProvider>(), same(source));
      context.read<ThemeProvider>().setTheme(ThemeType.dark);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(probe.palette, same(source.themeData));
      expect(probe.palette.primary, isNot(initial.primary));
      expect(probe.palette.lightProgress, closeTo(.5, .001));
      await tester.pumpAndSettle();
      expect(probe.palette.lightProgress, 0);
    },
  );
}
