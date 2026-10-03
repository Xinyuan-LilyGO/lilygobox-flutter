/*
 * @Description: 验证关闭窗口前完成保存、保存失败可重试及系统关闭事件不重复执行。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 21:12:12
 * @LastEditTime: 2026-10-03 21:12:12
 * @License: GPL 3.0
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/window/provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return false;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
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

      final closing = provider.close();
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
      await provider.close();
      expect(calls, isEmpty);
      canSave = true;
      await provider.close();
      expect(calls.map((call) => call.method), ['setPreventClose', 'close']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
