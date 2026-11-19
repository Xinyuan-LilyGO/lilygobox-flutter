import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_node_layer.dart';
import 'package:material_ui/material_ui.dart';

class _CountingIndex extends TaskCanvasSpatialIndex {
  int queries = 0;

  @override
  Set<String> intersecting(Rect area) {
    queries++;
    return super.intersecting(area);
  }
}

void main() {
  testWidgets(
    'partial drags retain both overlap stacks and reuse their viewport queries',
    (tester) async {
      const viewport = Size(800, 600);
      final transform = TransformationController();
      final geometry = ValueNotifier(0);
      final drag = TaskCanvasDragPreview();
      addTearDown(transform.dispose);
      addTearDown(geometry.dispose);
      addTearDown(drag.dispose);
      final index = _CountingIndex();
      final layers = <String, int>{};
      final ids = [
        for (final group in ['fixed', 'moving'])
          for (var level = 0; level < 3; level++) '$group-$level',
        'incoming-moving',
        'offscreen-fixed',
      ];
      for (final (rank, id) in ids.indexed) {
        layers[id] = rank;
        index.update(
          id,
          Rect.fromLTWH(
            switch (id) {
              'incoming-moving' => -270,
              'offscreen-fixed' => 970,
              _ => 100,
            },
            110,
            50,
            40,
          ),
        );
      }
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TaskTopologyNodeLayer(
            index: index,
            transform: transform,
            viewport: viewport,
            geometry: geometry,
            drag: drag,
            layers: layers,
            pinnedIds: () => const [],
            nodeBuilder: (id) =>
                Positioned.fromRect(rect: index[id]!, child: Text(id)),
          ),
        ),
      );
      expect(find.text('fixed-2'), findsNothing);
      drag.starts = {
        for (final id in ids.where((id) => id.contains('moving')))
          id: index[id]!.topLeft,
      };
      drag.move(const Offset(10, 0));
      await tester.pump();
      for (final group in ['fixed', 'moving']) {
        expect(find.text('$group-0'), findsNothing);
        for (final level in [1, 2]) {
          expect(find.text('$group-$level'), findsOneWidget);
        }
      }
      final initialQueries = index.queries;
      for (final delta in [25.0, 50.0, 78.0, 0.0]) {
        drag.move(Offset(delta, 0));
        await tester.pump();
        expect(index.queries, initialQueries);
        expect(find.text('fixed-2'), findsOneWidget);
        expect(find.text('moving-2'), findsOneWidget);
      }
      expect(find.text('incoming-moving'), findsNothing);
      drag.move(const Offset(330, 0));
      await tester.pump();
      expect(index.queries, greaterThan(initialQueries));
      expect(find.text('incoming-moving'), findsOneWidget);
      expect(find.text('offscreen-fixed'), findsNothing);
      transform.value = Matrix4.translationValues(-280, 0, 0);
      await tester.pump();
      expect(find.text('offscreen-fixed'), findsOneWidget);
      transform.value = Matrix4.identity();
      drag.move(Offset.zero);
      drag.reset();
      await tester.pump();
      expect(find.text('fixed-2'), findsNothing);
      expect(find.text('moving-2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '4000 cards keep viewport, overlap and drag ownership through pan and zoom',
    (tester) async {
      const viewport = Size(2555, 1507);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transform = TransformationController();
      final geometry = ValueNotifier(0);
      addTearDown(transform.dispose);
      addTearDown(geometry.dispose);
      final index = TaskCanvasSpatialIndex();
      final layers = <String, int>{};
      for (var number = 0; number < 4000; number++) {
        final id = '$number';
        layers[id] = number;
        index.update(
          id,
          Rect.fromLTWH(
            number < 1000 ? 0 : (number % 80) * 480.0,
            number < 1000 ? 0 : (number ~/ 80) * 300.0,
            252,
            144,
          ),
        );
      }
      var pinned = <String>{};
      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TaskTopologyNodeLayer(
            index: index,
            transform: transform,
            viewport: viewport,
            geometry: geometry,
            layers: layers,
            pinnedIds: () => pinned,
            nodeBuilder: (id) {
              builds++;
              return Positioned.fromRect(
                key: ValueKey(id),
                rect: index[id]!,
                child: Text(id),
              );
            },
          ),
        ),
      );
      expect(find.byType(Text), findsNWidgets(2));
      expect(find.byKey(const ValueKey('999')), findsOneWidget);
      transform.value = Matrix4.translationValues(-25, 0, 0);
      await tester.pump();
      expect(builds, 2);
      pinned = {'999'};
      transform.value = Matrix4.translationValues(-400, -1800, 0)
        ..scaleByDouble(.25, .25, 1, 1);
      await tester.pump();
      expect(find.byKey(const ValueKey('999')), findsOneWidget);
      expect(find.byType(Text).evaluate().length, inInclusiveRange(100, 600));
      final overlapping = index['999']!;
      index.update('999', overlapping.shift(const Offset(20000, 20000)));
      pinned = {};
      geometry.value++;
      await tester.pump();
      expect(find.byKey(const ValueKey('999')), findsNothing);
      transform.value = Matrix4.identity();
      await tester.pump();
      expect(find.byKey(const ValueKey('998')), findsOneWidget);
      expect(find.byKey(const ValueKey('997')), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  test('large routes and negative coordinates track moves and removal', () {
    final index = TaskCanvasSpatialIndex();
    const edge = Rect.fromLTWH(-100000, -100000, 200000, 200000);
    const area = Rect.fromLTWH(-100, -100, 50, 25);
    expect(index.update('edge', edge), isTrue);
    expect(index.update('edge', edge), isFalse);
    index.update('node', area);
    expect(index.intersecting(area), {'edge', 'node'});
    expect(index.containsPoint(area.center), isTrue);
    index.update('node', area.shift(const Offset(1000, 1000)));
    expect(index.intersecting(area), {'edge'});
    index.remove('edge');
    expect(index.intersecting(area), isEmpty);
    expect(index.containsPoint(area.center), isFalse);
  });
}
