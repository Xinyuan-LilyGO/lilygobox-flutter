import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection_layer.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final routes = {
    for (final id in ['first', 'second'])
      id: TaskTopologyConnection.preview(
        const Offset(10, 10),
        const Offset(200, 100),
      ),
  };
  Widget layer(Set<String> selected, {bool reducedMotion = false}) =>
      MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 200,
            child: TaskTopologyConnectionLayer(
              routes: routes,
              selectedEdges: selected,
              activeEdges: const {},
              lineColor: const Color(0xff777777),
              accentColor: const Color(0xff8066dd),
              scale: 1,
            ),
          ),
        ),
      );
  TaskTopologyConnectionsPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('topology-connections-paint')),
              )
              .painter!
          as TaskTopologyConnectionsPainter;

  testWidgets(
    'selection and deselection animate without rebuilding the layer',
    (tester) async {
      await tester.pumpWidget(layer({}));
      await tester.pumpWidget(layer({'first'}));
      final before = painter(tester);
      expect(before.selection('first'), 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(before.selection('first'), greaterThan(0));
      expect(before.selection('first'), lessThan(1));
      expect(painter(tester), same(before));
      expect(before.selection('second'), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(before.selection('first'), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(layer({}));
      final deselect = painter(tester);
      expect(deselect.selection('first'), 1);
      await tester.pump(const Duration(milliseconds: 80));
      expect(deselect.selection('first'), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(deselect.selection('first'), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'rapid reversal and multi-selection continue from current values',
    (tester) async {
      await tester.pumpWidget(layer({}));
      await tester.pumpWidget(layer({'first', 'second'}));
      await tester.pump(const Duration(milliseconds: 70));
      final middle = painter(tester).selection('first');
      expect(painter(tester).selection('second'), middle);
      await tester.pumpWidget(layer({'second'}));
      expect(painter(tester).selection('first'), middle);
      expect(painter(tester).selection('second'), middle);
      await tester.pump(const Duration(milliseconds: 80));
      expect(painter(tester).selection('first'), lessThan(middle));
      expect(painter(tester).selection('second'), greaterThan(middle));
      await tester.pump(const Duration(milliseconds: 100));
      expect(painter(tester).selection('first'), 0);
      expect(painter(tester).selection('second'), 1);
      await tester.pumpWidget(layer({'first', 'second'}));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('reduced motion immediately applies final selection state', (
    tester,
  ) async {
    await tester.pumpWidget(layer({}, reducedMotion: true));
    await tester.pumpWidget(layer({'first', 'second'}, reducedMotion: true));
    expect(painter(tester).selection('first'), 1);
    expect(painter(tester).selection('second'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(layer({}, reducedMotion: true));
    expect(painter(tester).selection('first'), 0);
    expect(painter(tester).selection('second'), 0);
  });
}
