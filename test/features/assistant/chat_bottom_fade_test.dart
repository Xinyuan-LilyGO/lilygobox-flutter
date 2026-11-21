import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_bottom_fade.dart';

void main() {
  for (final background in [const Color(0xffeeeeee), const Color(0xff181818)]) {
    for (final height in [128.0, 32.0]) {
      testWidgets('matches mask over $background in a $height tall viewport', (
        tester,
      ) async {
        final boundary = GlobalKey();
        Widget content() => Column(
          children: [
            const Expanded(
              child: ColoredBox(
                color: Color(0xff8764cd),
                child: SizedBox.expand(),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xffe29244).withValues(alpha: .6),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
        Future<Uint8List> capture(bool oldMask) async {
          final child = content();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 96,
                    height: height,
                    child: ColoredBox(
                      color: background,
                      child: oldMask
                          ? ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (bounds) =>
                                  const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xffffffff),
                                      Color(0x00ffffff),
                                    ],
                                  ).createShader(
                                    Rect.fromLTWH(
                                      0,
                                      bounds.height - 64,
                                      bounds.width,
                                      64,
                                    ),
                                  ),
                              child: child,
                            )
                          : ChatBottomFade(
                              backgroundColor: background,
                              child: child,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          return (await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1);
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final bytes = Uint8List.fromList(data!.buffer.asUint8List());
            image.dispose();
            return bytes;
          }))!;
        }

        final previous = await capture(true);
        final current = await capture(false);
        expect(current.length, previous.length);
        var largestDifference = 0;
        for (var i = 0; i < current.length; i++) {
          final difference = (current[i] - previous[i]).abs();
          if (difference > largestDifference) largestDifference = difference;
        }
        // Alpha compositing rounding can differ by one channel value.
        expect(largestDifference, lessThanOrEqualTo(2));
        expect(find.byType(ShaderMask), findsNothing);
      });
    }
  }

  testWidgets(
    'preserves child sizing and passes bottom pointer gestures through',
    (tester) async {
      var downs = 0;
      var moves = 0;
      final childKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ChatBottomFade(
              backgroundColor: const Color(0xffeeeeee),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => downs++,
                onPointerMove: (_) => moves++,
                child: SizedBox(key: childKey, width: 120, height: 80),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ChatBottomFade)), const Size(120, 80));
      final bottom =
          tester.getBottomLeft(find.byKey(childKey)) + const Offset(20, -8);
      final gesture = await tester.startGesture(bottom);
      await gesture.moveBy(const Offset(12, -10));
      await gesture.up();
      expect(downs, 1);
      expect(moves, greaterThan(0));
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.height, 64);
      expect(find.byType(ShaderMask), findsNothing);
    },
  );

  testWidgets('keeps child semantics and can disable the fade', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ChatBottomFade(
            backgroundColor: Color(0xff181818),
            fadeHeight: 0,
            child: Semantics(
              label: 'Conversation',
              child: SizedBox(width: 80, height: 20),
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Conversation'), findsOneWidget);
    semantics.dispose();
    expect(find.byType(Positioned), findsNothing);
    expect(tester.getSize(find.byType(ChatBottomFade)), const Size(80, 20));
  });
  for (final background in [const Color(0xffeeeeee), const Color(0xff181818)]) {
    testWidgets(
      'top and bottom fades are mirrored over $background without intercepting gestures',
      (tester) async {
        final boundary = GlobalKey();
        const foreground = Color(0xff8764cd);
        var downs = 0;
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: background,
                  child: ChatBottomFade(
                    backgroundColor: background,
                    topFadeHeight: 64,
                    child: Semantics(
                      label: 'Chat content',
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => downs++,
                        child: const ColoredBox(
                          color: foreground,
                          child: SizedBox(width: 96, height: 192),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final bytes = (await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
              .toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          return result;
        }))!;
        int channel(int y, int channel) => bytes[(y * 96 + 48) * 4 + channel];
        for (var y = 0; y < 64; y++) {
          for (var c = 0; c < 4; c++) {
            expect(
              (channel(y, c) - channel(191 - y, c)).abs(),
              lessThanOrEqualTo(2),
            );
          }
        }
        expect(channel(96, 0), (foreground.r * 255).round());
        expect(
          (channel(0, 0) - (background.r * 255).round()).abs(),
          lessThanOrEqualTo(2),
        );
        final box = find.byKey(boundary);
        await tester.tapAt(tester.getTopLeft(box) + const Offset(20, 8));
        await tester.tapAt(tester.getBottomLeft(box) + const Offset(20, -8));
        expect(downs, 2);
        expect(find.bySemanticsLabel('Chat content'), findsOneWidget);
        expect(find.byType(ShaderMask), findsNothing);
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'top fade stays visible while scrolling without rebuilding chat content',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 192,
              child: ChatBottomFade(
                backgroundColor: const Color(0xffeeeeee),
                topFadeHeight: 64,
                child: Builder(
                  builder: (context) {
                    builds++;
                    return SingleChildScrollView(
                      controller: scroll,
                      child: const RepaintBoundary(
                        child: ColoredBox(
                          color: Color(0xff8764cd),
                          child: SizedBox(width: 120, height: 600),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-top-fade')), findsOneWidget);
      final initialBuilds = builds;
      scroll.jumpTo(16);
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-top-fade')), findsOneWidget);
      scroll.jumpTo(40);
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-top-fade')), findsOneWidget);
      scroll.jumpTo(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-top-fade')), findsOneWidget);
      expect(builds, initialBuilds);
      expect(scroll.position.maxScrollExtent, 408);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
