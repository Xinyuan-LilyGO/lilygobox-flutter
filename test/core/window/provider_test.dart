/*
 * @Description: 验证关闭隐藏到托盘、恢复窗口、退出前保存及托盘不可用时的回退。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 21:12:12
 * @LastEditTime: 2026-10-04 00:20:00
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/window/provider.dart';
import 'package:lilygobox/core/window/tray.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <MethodCall>[];
  final trayCalls = <MethodCall>[];
  var trayAvailable = true;
  var minimized = false;

  setUp(() {
    calls.clear();
    trayCalls.clear();
    trayAvailable = true;
    minimized = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'isMinimized' ? minimized : false;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowTray.channel,
      (call) async {
        trayCalls.add(call);
        return trayAvailable;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      WindowTray.channel,
      null,
    );
  });

  testWidgets(
    'save completes before normal close and repeated close is ignored',
    (tester) async {
      final saved = Completer<bool>();
      var saveCalls = 0;
      final provider = WindowProvider(
        beforeClose: () {
          saveCalls++;
          return saved.future;
        },
      );
      addTearDown(provider.dispose);
      await tester.pump();
      calls.clear();

      final closing = provider.exit();
      provider.onWindowClose();
      await tester.pump();
      expect(calls, isEmpty);
      saved.complete(true);
      await closing;
      expect(calls.map((call) => call.method), ['setPreventClose', 'close']);
      expect(calls.first.arguments, {'isPreventClose': false});
      provider.onWindowClose();
      await tester.pump();
      expect(saveCalls, 1);
      expect(calls, hasLength(2));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'failed save keeps the window open and permits retry',
    (tester) async {
      var canSave = false;
      final provider = WindowProvider(beforeClose: () async => canSave);
      addTearDown(provider.dispose);
      await tester.pump();
      calls.clear();
      await provider.exit();
      expect(calls.map((call) => call.method), [
        'isMinimized',
        'show',
        'focus',
      ]);
      calls.clear();
      canSave = true;
      await provider.exit();
      expect(calls.map((call) => call.method), ['setPreventClose', 'close']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'close and system close hide without saving or terminating',
    (tester) async {
      var saves = 0;
      final provider = WindowProvider(
        beforeClose: () async {
          saves++;
          return true;
        },
      );
      addTearDown(provider.dispose);
      await tester.pump();
      calls.clear();
      await provider.close();
      provider.onWindowClose();
      await tester.pump();
      expect(trayCalls.map((call) => call.method), ['hide', 'hide']);
      expect(calls, isEmpty);
      expect(saves, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'unavailable tray minimizes instead of losing the window',
    (tester) async {
      trayAvailable = false;
      final provider = WindowProvider();
      addTearDown(provider.dispose);
      await tester.pump();
      calls.clear();
      await provider.close();
      expect(calls.map((call) => call.method), ['minimize']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'tray actions restore minimized window and exit after saving',
    (tester) async {
      var saves = 0;
      final provider = WindowProvider(
        beforeClose: () async {
          saves++;
          return true;
        },
      );
      addTearDown(provider.dispose);
      await tester.pump();
      calls.clear();
      minimized = true;
      Future<void> nativeEvent(String event) async {
        final complete = Completer<void>();
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          'lilygobox/tray',
          const StandardMethodCodec().encodeMethodCall(MethodCall(event)),
          (_) => complete.complete(),
        );
        await complete.future;
      }

      await nativeEvent('show');
      expect(calls.map((call) => call.method), [
        'isMinimized',
        'restore',
        'show',
        'focus',
      ]);
      calls.clear();
      await nativeEvent('exit');
      expect(saves, 1);
      expect(calls.map((call) => call.method), ['setPreventClose', 'close']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
