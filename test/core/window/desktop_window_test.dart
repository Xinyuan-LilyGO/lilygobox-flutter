import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/window/desktop_window.dart';
import 'package:window_manager/window_manager.dart';

class _Window implements Window {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DesktopWindowBinding', () {
    test('keeps the runner window for subsequent window controls', () async {
      final runnerWindow = _Window();
      var reads = 0;
      final wrappedHandles = <int>[];
      final binding = DesktopWindowBinding(
        readNativeHandle: () async {
          reads++;
          return 42;
        },
        wrapNativeHandle: (handle) {
          wrappedHandles.add(handle);
          return runnerWindow;
        },
      );

      expect(binding.window, isNull);
      expect(await binding.initialize(), same(runnerWindow));
      expect(binding.window, same(runnerWindow));
      expect(await binding.initialize(), same(runnerWindow));
      expect(reads, 1);
      expect(wrappedHandles, [42]);
    });

    test('concurrent initialization shares one runner lookup', () async {
      final nativeHandle = Completer<int?>();
      final runnerWindow = _Window();
      var reads = 0;
      var wraps = 0;
      final binding = DesktopWindowBinding(
        readNativeHandle: () {
          reads++;
          return nativeHandle.future;
        },
        wrapNativeHandle: (_) {
          wraps++;
          return runnerWindow;
        },
      );

      final first = binding.initialize();
      final second = binding.initialize();
      expect(binding.window, isNull);
      nativeHandle.complete(42);

      expect(
        await Future.wait([first, second]),
        everyElement(same(runnerWindow)),
      );
      expect(reads, 1);
      expect(wraps, 1);
    });

    for (final invalidHandle in <int?>[null, 0]) {
      test('rejects unavailable native handle $invalidHandle', () async {
        var wraps = 0;
        final binding = DesktopWindowBinding(
          readNativeHandle: () async => invalidHandle,
          wrapNativeHandle: (_) {
            wraps++;
            return _Window();
          },
        );

        await expectLater(binding.initialize(), throwsStateError);
        expect(binding.window, isNull);
        expect(wraps, 0);
      });
    }

    test('does not publish a window when native wrapping fails', () async {
      final binding = DesktopWindowBinding(
        readNativeHandle: () async => 42,
        wrapNativeHandle: (_) => null,
      );

      await expectLater(binding.initialize(), throwsStateError);
      expect(binding.window, isNull);
    });

    test('can initialize again after a failed runner lookup', () async {
      var reads = 0;
      final runnerWindow = _Window();
      final binding = DesktopWindowBinding(
        readNativeHandle: () async => ++reads == 1 ? null : 42,
        wrapNativeHandle: (_) => runnerWindow,
      );

      await expectLater(binding.initialize(), throwsStateError);
      expect(await binding.initialize(), same(runnerWindow));
      expect(binding.window, same(runnerWindow));
      expect(reads, 2);
    });

    test('propagates runner errors and permits another attempt', () async {
      var reads = 0;
      final runnerWindow = _Window();
      final unavailableRunner = StateError('runner channel unavailable');
      final binding = DesktopWindowBinding(
        readNativeHandle: () async {
          if (++reads == 1) throw unavailableRunner;
          return 42;
        },
        wrapNativeHandle: (_) => runnerWindow,
      );

      await expectLater(binding.initialize(), throwsA(same(unavailableRunner)));
      expect(binding.window, isNull);
      expect(await binding.initialize(), same(runnerWindow));
      expect(reads, 2);
    });
  });
}
