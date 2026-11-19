import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';

String motionPackagePath() =>
    Platform.environment['LILYGOBOX_MOTION_PACKAGE'] ??
    File('artifacts/test-data/lilygobox-long-chat-10000.7z').absolute.path;

Finder motionCanvasCards() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('topology-node-');
});

Future<void> waitForMotionCards(WidgetTester tester) async {
  final cards = motionCanvasCards();
  final waiting = Stopwatch()..start();
  do {
    await tester.binding.endOfFrame;
  } while (cards.evaluate().isEmpty && waiting.elapsed.inSeconds < 15);
  expect(cards, findsAtLeastNWidgets(1));
}

Future<void> setMotionWindowMaximized(
  WidgetTester tester,
  bool maximized,
) async {
  const channel = MethodChannel('lilygobox/window_layout');
  final handle = (await channel.invokeMethod<int>('getWindowHandle'))!;
  final user32 = ffi.DynamicLibrary.open('user32.dll');
  final isVisible = user32
      .lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
        'IsWindowVisible',
      );
  final isMaximized = user32
      .lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
        'IsZoomed',
      );
  Future<void> waitForWindow(bool Function() ready) async {
    final timeout = Stopwatch()..start();
    while (!ready() && timeout.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  await waitForWindow(() => isVisible(handle) != 0);
  bool matchesState() => (isMaximized(handle) != 0) == maximized;
  if (!matchesState()) {
    await channel.invokeMethod<void>('toggleMaximize');
  }
  await waitForWindow(matchesState);
  await tester.pumpAndSettle();
}

Future<void> seedMotionCanvas(AgentStorage storage, int count) {
  final date = DateTime.utc(2020).toIso8601String();
  return storage.saveWorkflow({
    'version': 1,
    'connections': [],
    'sessions': [
      for (var index = 0; index < count; index++)
        {
          'id': '1000-$index',
          'kind': index % 8 == 0 ? 'primary' : 'permanent',
          'parentId': index % 8 == 0 ? null : '1000-${index - 1}',
          'title': '画布压力测试 $index',
          'task': 'Local fixture',
          'createdAt': date,
          'conversation': {
            'serviceId': '',
            'model': '',
            'messages': [],
            'history': [],
          },
        },
    ],
    'canvas': {
      for (var index = 0; index < count; index++)
        '1000-$index': index % 16 == 1
            ? [440, 280]
            : [(index % 60) * 480, (index ~/ 60) * 300],
    },
  });
}
