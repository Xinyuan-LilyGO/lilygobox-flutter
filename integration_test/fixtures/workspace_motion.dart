import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/agent_package.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';

String motionPackagePath() =>
    Platform.environment['LILYGOBOX_MOTION_PACKAGE'] ??
    File('artifacts/lilygobox-long-chat-10000.tar.zst').absolute.path;

typedef MotionMouse = ({
  void Function() wheel,
  void Function() middleDown,
  void Function(Offset delta) middleMove,
  void Function() middleUp,
  void Function(Offset target) hover,
  void Function() escape,
});

Future<int> _nativeFlutterView(ffi.DynamicLibrary user) async {
  const channel = MethodChannel('lilygobox/window_layout');
  final owner = (await channel.invokeMethod<int>('getWindowHandle'))!;
  final child = user
      .lookupFunction<
        ffi.IntPtr Function(ffi.IntPtr, ffi.Uint32),
        int Function(int, int)
      >('GetWindow')(owner, 5);
  expect(child, isNot(0));
  return child;
}

int Function(int, int, int, int) _postWindowMessage(ffi.DynamicLibrary user) =>
    user.lookupFunction<
      ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.UintPtr, ffi.IntPtr),
      int Function(int, int, int, int)
    >('PostMessageW');

Future<void> requestNativeAccessibility() async {
  final user = ffi.DynamicLibrary.open('user32.dll');
  final child = await _nativeFlutterView(user);
  const getObject = 0x003d;
  const clientObjectId = -4;
  expect(
    _postWindowMessage(user)(child, getObject, 0, clientObjectId),
    isNot(0),
  );
}

Future<void> withNativeMotionMouse(
  WidgetTester tester,
  Offset target,
  Future<void> Function(MotionMouse mouse) measure, {
  bool positionSystemCursor = false,
}) async {
  final user = ffi.DynamicLibrary.open('user32.dll');
  final child = await _nativeFlutterView(user);
  final getCursor = user
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Int32>),
        int Function(ffi.Pointer<ffi.Int32>)
      >('GetCursorPos');
  final setCursor = user
      .lookupFunction<
        ffi.Int32 Function(ffi.Int32, ffi.Int32),
        int Function(int, int)
      >('SetCursorPos');
  final toScreen = user
      .lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<ffi.Int32>),
        int Function(int, ffi.Pointer<ffi.Int32>)
      >('ClientToScreen');
  final post = _postWindowMessage(user);
  final original = calloc<ffi.Int32>(2);
  final point = calloc<ffi.Int32>(2);
  final previous = tester.binding.shouldPropagateDevicePointerEvents;
  try {
    final ratio = tester.view.devicePixelRatio;
    var clientX = point[0] = (target.dx * ratio).round();
    var clientY = point[1] = (target.dy * ratio).round();
    int packed(int x, int y) => ((y & 0xffff) << 16) | (x & 0xffff);
    void send(int message, int state, int coordinates) {
      expect(post(child, message, state, coordinates), isNot(0));
    }

    const wmMouseWheel = 0x020a;
    const wmMiddleDown = 0x0207;
    const wmMouseMove = 0x0200;
    const wmMiddleUp = 0x0208;
    const middleButton = 0x0010;
    var held = false;
    void moveSystemCursor() {
      expect(positionSystemCursor, isTrue);
      point[0] = clientX;
      point[1] = clientY;
      expect(toScreen(child, point), isNot(0));
      expect(setCursor(point[0], point[1]), isNot(0));
    }

    void middleUp() {
      send(wmMiddleUp, 0, packed(clientX, clientY));
      held = false;
    }

    try {
      tester.binding.shouldPropagateDevicePointerEvents = true;
      if (positionSystemCursor) {
        expect(getCursor(original), isNot(0));
        expect(toScreen(child, point), isNot(0));
        expect(setCursor(point[0], point[1]), isNot(0));
      }
      await tester.binding.endOfFrame;
      await measure((
        wheel: () {
          expect(positionSystemCursor, isTrue);
          send(wmMouseWheel, 120 << 16, packed(point[0], point[1]));
        },
        middleDown: () {
          send(wmMiddleDown, middleButton, packed(clientX, clientY));
          held = true;
        },
        middleMove: (delta) {
          clientX += (delta.dx * ratio).round();
          clientY += (delta.dy * ratio).round();
          moveSystemCursor();
          send(wmMouseMove, middleButton, packed(clientX, clientY));
        },
        middleUp: middleUp,
        hover: (target) {
          clientX = (target.dx * ratio).round();
          clientY = (target.dy * ratio).round();
          moveSystemCursor();
          send(wmMouseMove, 0, packed(clientX, clientY));
        },
        escape: () => send(0x0100, 0x1b, 0),
      ));
    } finally {
      if (held) {
        middleUp();
        await tester.binding.endOfFrame;
      }
      tester.binding.shouldPropagateDevicePointerEvents = previous;
      if (positionSystemCursor) setCursor(original[0], original[1]);
    }
  } finally {
    calloc.free(point);
    calloc.free(original);
  }
}

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

Future<Map<String, int>> seedMotionCanvas(
  AgentStorage storage,
  int count, {
  bool fullHistory = false,
  int recycleCount = 0,
  int recycledMessages = 0,
}) async {
  final date = DateTime.utc(2020).toIso8601String();
  var conversation = <String, dynamic>{
    'serviceId': '',
    'model': '',
    'messages': [],
    'history': [],
  };
  if (fullHistory) {
    final package = await AgentPackage.read(motionPackagePath());
    conversation = Map<String, dynamic>.from(
      (package['workflow']['sessions'] as List).single['conversation'] as Map,
    );
    expect(conversation['messages'], hasLength(10000));
  }
  if (recycledMessages < 0 ||
      recycledMessages > (conversation['messages'] as List).length) {
    throw ArgumentError.value(recycledMessages, 'recycledMessages');
  }
  final recycleConversation = {
    ...conversation,
    'messages': (conversation['messages'] as List)
        .take(recycledMessages)
        .toList(),
    'history': (conversation['history'] as List)
        .take(recycledMessages)
        .toList(),
  };
  await storage.saveWorkflow({
    'version': 1,
    'connections': [],
    'recycleRetentionDays': 0,
    'recycleBin': [
      for (var index = 0; index < recycleCount; index++)
        {
          'record': {
            'id': '2000-$index',
            'kind': 'primary',
            'title': 'Recycled $index',
            'task': '',
            'createdAt': date,
            'conversation': recycleConversation,
          },
          'deletedAt': date,
        },
    ],
    'sessions': [
      for (var index = 0; index < count; index++)
        {
          'id': '1000-$index',
          'kind': index % 8 == 0 ? 'primary' : 'permanent',
          'parentId': index % 8 == 0 ? null : '1000-${index - 1}',
          'title': '画布压力测试 $index',
          'task': 'Local fixture',
          'createdAt': date,
          'conversation': conversation,
        },
    ],
    'canvas': {
      for (var index = 0; index < count; index++)
        '1000-$index': index % 16 == 1
            ? [440, 280]
            : [(index % 60) * 480, (index ~/ 60) * 300],
    },
  });
  return {
    'recycled_agents': recycleCount,
    'messages_per_recycled_agent': recycledMessages,
    'recycled_conversation_json_utf8_bytes_each': utf8
        .encode(jsonEncode(recycleConversation))
        .length,
  };
}
