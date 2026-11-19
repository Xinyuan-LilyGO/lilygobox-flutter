/*
 * @Description: 验证隐藏页面不接收主题过渡帧，恢复显示后同步最新配色并保留状态。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/theme/update_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _NotifyingThemeProvider extends ThemeProvider {
  void notifyUnchanged() => notifyListeners();
}

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
  late ThemeProvider source;
  Color? defaultTextColor;

  @override
  Widget build(BuildContext context) {
    builds++;
    source = context.watch<ThemeProvider>();
    palette = source.themeData;
    fontChoice = source.fontChoice;
    brightness = Theme.of(context).brightness;
    defaultTextColor = DefaultTextStyle.of(context).style.color;
    return ColoredBox(color: palette.primary);
  }
}

void main() {
  testWidgets(
    'visible theme consumers ignore unrelated parent frames and unchanged notifications',
    (tester) async {
      final source = _NotifyingThemeProvider();
      final frame = ValueNotifier(0);
      addTearDown(source.dispose);
      addTearDown(frame.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: source,
          child: MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: frame,
              child: const _ThemeProbe(),
              builder: (context, _, child) =>
                  ThemeUpdateScope(active: true, child: child!),
            ),
          ),
        ),
      );
      final probe = tester.state<_ThemeProbeState>(find.byType(_ThemeProbe));
      final initialBuilds = probe.builds;
      for (var tick = 1; tick <= 12; tick++) {
        frame.value = tick;
        await tester.pump();
      }
      expect(probe.builds, initialBuilds);
      for (var tick = 0; tick < 12; tick++) {
        source.notifyUnchanged();
        await tester.pump();
      }
      expect(probe.builds, initialBuilds);
      source.setFontChoice('inter');
      await tester.pump();
      expect(probe.fontChoice, 'inter');
      expect(probe.builds, initialBuilds + 1);
      source.setTheme(ThemeType.dark);
      await tester.pump();
      expect(probe.palette, same(source.themeData));
      expect(probe.builds, initialBuilds + 2);
    },
  );

  testWidgets(
    'resuming during a theme transition syncs once and keeps later animation frames',
    (tester) async {
      final source = ThemeProvider(vsync: tester);
      final visible = ValueNotifier(false);
      addTearDown(source.dispose);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: source,
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: const _ThemeProbe(),
              builder: (context, active, child) =>
                  ThemeUpdateScope(active: active, child: child!),
            ),
          ),
        ),
      );
      final probe = tester.state<_ThemeProbeState>(find.byType(_ThemeProbe));
      final hiddenBuilds = probe.builds;
      source.setTheme(ThemeType.dark);
      source.setFontChoice('inter');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(probe.builds, hiddenBuilds);
      expect(probe.fontChoice, 'system');
      visible.value = true;
      await tester.pump();
      expect(tester.state(find.byType(_ThemeProbe)), same(probe));
      expect(probe.palette, same(source.themeData));
      expect(probe.palette.lightProgress, closeTo(.5, .001));
      expect(probe.fontChoice, 'inter');
      expect(probe.builds, hiddenBuilds + 1);
      final resumedBuilds = probe.builds;
      final resumedPalette = probe.palette;
      await tester.pump(const Duration(milliseconds: 30));
      expect(probe.builds, greaterThan(resumedBuilds));
      expect(probe.palette.primary, isNot(resumedPalette.primary));
      expect(probe.palette, same(source.themeData));
      await tester.pumpAndSettle();
      expect(probe.palette.lightProgress, 0);
      final settledBuilds = probe.builds;
      for (var tick = 1; tick <= 12; tick++) {
        visible.value = false;
        await tester.pump();
        visible.value = true;
        await tester.pump();
      }
      expect(probe.builds, settledBuilds);
    },
  );

  testWidgets(
    'visible and hidden scopes follow replacement theme provider instances',
    (tester) async {
      final initial = ThemeProvider();
      final replacement = ThemeProvider();
      final hiddenReplacement = ThemeProvider();
      final source = ValueNotifier(initial);
      final visible = ValueNotifier(true);
      addTearDown(initial.dispose);
      addTearDown(replacement.dispose);
      addTearDown(hiddenReplacement.dispose);
      addTearDown(source.dispose);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeProvider>(
          valueListenable: source,
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: const _ThemeProbe(),
              builder: (context, active, child) =>
                  ThemeUpdateScope(active: active, child: child!),
            ),
          ),
          builder: (context, provider, child) =>
              ChangeNotifierProvider.value(value: provider, child: child),
        ),
      );
      final probe = tester.state<_ThemeProbeState>(find.byType(_ThemeProbe));
      expect(probe.source, same(initial));
      source.value = replacement;
      await tester.pump();
      expect(probe.source, same(replacement));
      visible.value = false;
      await tester.pump();
      final hiddenBuilds = probe.builds;
      source.value = hiddenReplacement;
      await tester.pump();
      replacement.setFontChoice('inter');
      hiddenReplacement.setFontChoice('roboto');
      await tester.pump();
      expect(probe.builds, hiddenBuilds);
      expect(probe.source, same(replacement));
      visible.value = true;
      await tester.pump();
      expect(probe.source, same(hiddenReplacement));
      expect(probe.fontChoice, 'roboto');
      final resumedBuilds = probe.builds;
      replacement.setTheme(ThemeType.dark);
      await tester.pump();
      expect(probe.builds, resumedBuilds);
      final context = tester.element(find.byType(_ThemeProbe));
      context.read<ThemeProvider>().setTheme(ThemeType.dark);
      await tester.pump();
      expect(hiddenReplacement.currentTheme, ThemeType.dark);
      expect(probe.palette, same(hiddenReplacement.themeData));
    },
  );

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
