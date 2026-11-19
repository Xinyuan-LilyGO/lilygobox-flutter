import 'dart:math' as math;
import 'dart:ui' as ui;

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

  testWidgets('batch drawing separates selected strokes and active sockets', (
    tester,
  ) async {
    const normalColor = Color(0xff777777);
    const selectedColor = Color(0xff8066dd);
    final routes = {
      for (var row = 0; row < 72; row++)
        '$row': TaskTopologyConnection.preview(
          Offset(10, row * 4),
          Offset(180, row * 4),
        ),
    };
    const bounds = Rect.fromLTWH(0, 0, 200, 280);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TaskTopologyConnectionLayer(
            routes: routes,
            bounds: bounds,
            selectedEdges: const {'65', '66'},
            activeEdges: const {'66'},
            lineColor: normalColor,
            accentColor: selectedColor,
            scale: .5,
          ),
        ),
      ),
    );
    final canvas = TestRecordingCanvas();
    painter(tester).paint(canvas, bounds.size);
    final calls = canvas.invocations.map((record) => record.invocation);
    final strokes = calls.where((call) => call.memberName == #drawPath);
    final socketCalls = calls.where(
      (call) => call.memberName == #drawRawPoints,
    );
    Iterable<List<dynamic>> arguments(
      Iterable<Invocation> source,
      Color color,
    ) => source
        .map((call) => call.positionalArguments)
        .where(
          (args) => (args.last as Paint).color.toARGB32() == color.toARGB32(),
        );
    final selected = arguments(strokes, selectedColor).single;
    expect(
      (selected.first as Path).getBounds(),
      routes['65']!.path.getBounds(),
    );
    expect((selected.last as Paint).strokeWidth, 4);
    final normal = arguments(strokes, normalColor);
    expect(normal.length, lessThan(10));
    expect(
      normal.expand((args) => (args.first as Path).computeMetrics()),
      hasLength(69),
    );
    expect(arguments(socketCalls, selectedColor).single[1], [
      10,
      260,
      180,
      260,
      10,
      264,
      180,
      264,
    ]);
    expect(
      arguments(
        socketCalls,
        normalColor,
      ).expand((args) => args[1] as List<double>),
      hasLength(68 * 4),
    );
  });

  testWidgets(
    'dense Windows curves keep joins, sockets and gaps at large canvas coordinates',
    (tester) async {
      const origin = Offset(32000000.25, 24000000.75);
      final bounds = origin & const Size(220, 134);
      final curve = TaskTopologyConnection.preview(
        origin + const Offset(11, 10),
        origin + const Offset(190, 82),
      );
      final dense = {
        'curve': curve,
        'active': TaskTopologyConnection.preview(
          origin + const Offset(10, 110),
          origin + const Offset(185, 110),
        ),
        for (var index = 0; index < 64; index++)
          '$index': TaskTopologyConnection.preview(
            origin + Offset(800.0 + index, 20),
            origin + const Offset(900, 80),
          ),
      };
      const zoom = .7;
      const ratio = 1.25;
      const physical = zoom * ratio;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: ratio),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TaskTopologyConnectionLayer(
              routes: dense,
              selectedEdges: const {'curve'},
              activeEdges: const {'active'},
              bounds: bounds,
              lineColor: const Color(0xff667788),
              accentColor: const Color(0xffdd682a),
              scale: zoom,
            ),
          ),
        ),
      );
      final ink = painter(tester);
      final recording = TestRecordingCanvas();
      ink.paint(recording, bounds.size);
      if (!ui.ImageFilter.isShaderFilterSupported) {
        final strokes = recording.invocations
            .map((call) => call.invocation)
            .where(
              (call) =>
                  call.memberName == #drawRawPoints &&
                  call.positionalArguments.first == ui.PointMode.lines,
            );
        final vertices = strokes.single.positionalArguments[1] as List<double>;
        expect(vertices.take(2), [11, 10]);
        expect(vertices.skip(vertices.length - 2), [190, 82]);
      }
      final recorder = ui.PictureRecorder();
      ink.paint(Canvas(recorder)..scale(physical), bounds.size);
      final picture = recorder.endRecording();
      final width = (bounds.width * physical).ceil();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(
          width,
          (bounds.height * physical).ceil(),
        );
        final result = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return result;
      }))!;
      picture.dispose();
      int alpha(int column, int row) =>
          bytes.getUint8((row * width + column) * 4 + 3);
      for (final point in curve.clippedPolyline(bounds, .3 / physical)!) {
        final local = (point - origin) * physical;
        var coverage = 0;
        for (
          var row = local.dy.floor() - 1;
          row <= local.dy.floor() + 1;
          row++
        ) {
          for (
            var column = local.dx.floor() - 1;
            column <= local.dx.floor() + 1;
            column++
          ) {
            coverage = math.max(coverage, alpha(column, row));
          }
        }
        expect(coverage, greaterThan(175), reason: 'joint at $local');
      }
      expect(alpha((10 * physical).floor(), (110 * physical).floor()), 255);
      expect(alpha((80 * physical).floor(), (110 * physical).floor()), 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
