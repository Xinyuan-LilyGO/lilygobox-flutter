import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/state/agent_workspace_provider.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/agent_transfer_layer.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/task_topology_connection.dart';

void main() {
  const edge = AiTaskConnection(
    id: 'wire',
    fromId: 'a',
    toId: 'b',
    isHierarchy: true,
  );
  final route = TaskTopologyConnection.between(
    const Rect.fromLTWH(0, 70, 40, 60),
    const Rect.fromLTWH(260, 70, 40, 60),
  );
  test(
    'packets paint in the actual sender direction including simultaneous replies',
    () async {
      final transform = TransformationController();
      addTearDown(transform.dispose);
      final metric = route.path.computeMetrics().single;
      for (final directions in [
        [true],
        [false],
        [true, false],
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final now = DateTime.now();
        AgentTransferPainter(
          transfers: [
            for (var i = 0; i < directions.length; i++)
              AiAgentTransfer(
                i,
                directions[i] ? 'a' : 'b',
                directions[i] ? 'b' : 'a',
                now.subtract(const Duration(milliseconds: 350)),
              ),
          ],
          connections: [edge],
          routes: {'wire': route},
          transform: transform,
          color: const Color(0xff8855dd),
          clock: const AlwaysStoppedAnimation(.25),
          reducedMotion: false,
        ).paint(canvas, const Size(300, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 200);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final forward in [true, false]) {
          final point = metric
              .getTangentForOffset(metric.length * (forward ? .25 : .75))!
              .position;
          final alpha = bytes.getUint8(
            (point.dy.floor() * 300 + point.dx.floor()) * 4 + 3,
          );
          expect(alpha, directions.contains(forward) ? 255 : lessThan(200));
        }
        image.dispose();
        picture.dispose();
      }
    },
  );
  testWidgets(
    'transport ticks only its paint and becomes idle after the burst',
    (tester) async {
      final transfers = ValueNotifier<List<AiAgentTransfer>>(const []);
      final transform = TransformationController();
      addTearDown(transfers.dispose);
      addTearDown(transform.dispose);
      Widget app({bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: SizedBox(
            width: 300,
            height: 200,
            child: AgentTransferLayer(
              transfers: transfers,
              connections: [edge],
              routes: {'wire': route},
              transform: transform,
              color: Colors.purple,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      transfers.value = [AiAgentTransfer(1, 'a', 'b', DateTime.now())];
      await tester.pump();
      final finder = find.byKey(const ValueKey('topology-transfer-paint'));
      final before = tester.widget<CustomPaint>(finder);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<CustomPaint>(finder), same(before));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      transfers.value = const [];
      await tester.pumpAndSettle();
      expect(
        (tester.widget<CustomPaint>(finder).painter! as AgentTransferPainter)
            .transfers,
        isEmpty,
      );
      await tester.pumpWidget(app(reduced: true));
      transfers.value = [AiAgentTransfer(2, 'b', 'a', DateTime.now())];
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        (tester.widget<CustomPaint>(finder).painter! as AgentTransferPainter)
            .reducedMotion,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
