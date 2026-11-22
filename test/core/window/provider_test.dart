import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/core/window/tray.dart';
import 'package:window_manager/window_manager.dart';

class _Request implements EventRequest {
  bool cancelled = false;
  @override
  bool cancel() {
    cancelled = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Window implements Window {
  final calls = <String>[];
  FutureOr<void> Function(WindowEvent)? listener;
  bool minimized = false;
  bool maximized = false;
  @override
  bool get isFocused => true;
  @override
  bool get isMaximized => maximized;
  @override
  bool get isMinimized => minimized;
  @override
  int addListener(FutureOr<void> Function(WindowEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(int id) {
    listener = null;
    return true;
  }

  @override
  bool close() {
    calls.add('close');
    return true;
  }

  @override
  void show() => calls.add('show');
  @override
  void focus() => calls.add('focus');
  @override
  void restore() {
    calls.add('restore');
    minimized = false;
  }

  @override
  void minimize() => calls.add('minimize');
  @override
  void maximize() {
    calls.add('maximize');
    maximized = true;
  }

  @override
  void unmaximize() {
    calls.add('unmaximize');
    maximized = false;
  }

  _Request requestClose() {
    final request = _Request();
    listener?.call(WindowCloseRequestedEvent(windowId: 1, request: request));
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Window window;
  final trayCalls = <String>[];
  var trayAvailable = true;
  setUp(() {
    window = _Window();
    trayCalls.clear();
    trayAvailable = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowTray.channel,
      (call) async {
        trayCalls.add(call.method);
        return trayAvailable;
      },
    );
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowTray.channel,
      null,
    ),
  );
  testWidgets(
    'maximize toggles native state before asynchronous events arrive',
    (tester) async {
      final provider = WindowProvider(window: window);
      await provider.handleMaximizeRestore();
      await provider.handleMaximizeRestore();
      expect(window.calls, ['maximize', 'unmaximize']);
      // A system snap/maximize may precede delivery of its Dart event as well.
      window.maximized = true;
      await provider.handleMaximizeRestore();
      expect(window.calls.last, 'unmaximize');
      provider.dispose();
      await provider.handleMaximizeRestore();
      expect(window.calls, ['maximize', 'unmaximize', 'unmaximize']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets('taskbar restore retains the actual maximized state', (
    tester,
  ) async {
    final provider = WindowProvider(window: window);
    addTearDown(provider.dispose);
    window.maximized = true;
    await window.listener!(WindowMaximizedEvent(windowId: 1));
    expect(provider.isMaximized, isTrue);
    // 任务栏从最小化恢复到最大化也会发送 restored，不能据此切回普通外框。
    await window.listener!(WindowRestoredEvent(windowId: 1));
    expect(provider.isMaximized, isTrue);
    expect(window.calls, isEmpty);
    window.maximized = false;
    await window.listener!(WindowRestoredEvent(windowId: 1));
    expect(provider.isMaximized, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('native activation wins over a stale initial focus query', (
    tester,
  ) async {
    const channel = MethodChannel('lilygobox/window_focus');
    final initial = Completer<bool>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => initial.future,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final provider = WindowProvider(window: window);
    addTearDown(provider.dispose);
    await tester.pump();
    Future<void> activate(bool value) async {
      final done = Completer<void>();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('focusChanged', value),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    await activate(true);
    initial.complete(false);
    await tester.pump();
    expect(provider.isFocused, isTrue);
    await window.listener!(WindowBlurredEvent(windowId: 1));
    expect(provider.isFocused, isTrue);
    await activate(false);
    expect(provider.isFocused, isFalse);
    await activate(true);
    expect(provider.isFocused, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('saving blocks system close until the save finishes', (
    tester,
  ) async {
    final saved = Completer<bool>();
    var saves = 0;
    final provider = WindowProvider(
      window: window,
      beforeClose: () {
        saves++;
        return saved.future;
      },
    );
    addTearDown(provider.dispose);
    final closing = provider.exit();
    expect(window.requestClose().cancelled, isTrue);
    expect(window.calls, isEmpty);
    saved.complete(true);
    await closing;
    expect(window.calls, ['close']);
    expect(saves, 1);
    expect(window.requestClose().cancelled, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('failed saving retains window and allows retry', (tester) async {
    var success = false;
    var prepared = false;
    Future<void> prepare() async => prepared = true;
    final provider = WindowProvider(
      window: window,
      beforeClose: () async => success,
    );
    addTearDown(provider.dispose);
    expect(await provider.exit(beforeNativeClose: prepare), isFalse);
    expect(prepared, isFalse);
    expect(window.calls, ['show', 'focus']);
    window.calls.clear();
    success = true;
    expect(await provider.exit(beforeNativeClose: prepare), isTrue);
    expect(prepared, isTrue);
    expect(window.calls, ['close']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('installer preparation must finish before native close', (
    tester,
  ) async {
    final ready = Completer<void>();
    final provider = WindowProvider(window: window);
    addTearDown(provider.dispose);

    final closing = provider.exit(beforeNativeClose: () => ready.future);
    expect(window.calls, isEmpty);
    expect(window.requestClose().cancelled, isTrue);

    final failed = expectLater(closing, throwsStateError);
    ready.completeError(StateError('Installer is not ready'));
    await failed;
    expect(window.calls, ['show', 'focus']);
    expect(window.requestClose().cancelled, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('ordinary close hides without saving and failed tray minimizes', (
    tester,
  ) async {
    var saves = 0;
    final provider = WindowProvider(
      window: window,
      beforeClose: () async {
        saves++;
        return true;
      },
    );
    addTearDown(provider.dispose);
    expect(window.requestClose().cancelled, isTrue);
    await tester.pump();
    expect(trayCalls, ['hide']);
    expect(saves, 0);
    expect(window.calls, isEmpty);
    trayAvailable = false;
    await provider.close();
    expect(window.calls, ['minimize']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('tray restores minimized windows and saves on exit', (
    tester,
  ) async {
    var saves = 0;
    final provider = WindowProvider(
      window: window,
      beforeClose: () async {
        saves++;
        return true;
      },
    );
    addTearDown(provider.dispose);
    Future<void> event(String name) async {
      final done = Completer<void>();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        WindowTray.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(name)),
        (_) => done.complete(),
      );
      await done.future;
    }

    window.minimized = true;
    await event('show');
    expect(window.calls, ['restore', 'show', 'focus']);
    window.calls.clear();
    await event('exit');
    expect(saves, 1);
    expect(window.calls, ['close']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
