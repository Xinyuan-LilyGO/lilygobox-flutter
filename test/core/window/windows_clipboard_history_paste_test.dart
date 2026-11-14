/*
 * @Description: 验证 Windows 剪贴板历史的异常按键序列会被正确归一化。
 */

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/window/windows_clipboard_history_paste.dart';

void main() {
  testWidgets('installs after asynchronous keyboard initialization', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final dispatcher = ui.PlatformDispatcher.instance;
    final original = dispatcher.onKeyData;
    addTearDown(() {
      dispatcher.onKeyData = original;
      debugDefaultTargetPlatformOverride = null;
    });

    // At startup ServicesBinding has not registered its callback yet.
    dispatcher.onKeyData = null;
    installWindowsClipboardHistoryPasteFix();
    debugDefaultTargetPlatformOverride = null;
    final forwarded = <ui.KeyData>[];
    dispatcher.onKeyData = (data) {
      forwarded.add(data);
      return false;
    };
    tester.binding.scheduleFrame();
    await tester.pump();

    for (final event in [
      _event(ui.KeyEventType.down, control, synthesized: false),
      _event(ui.KeyEventType.up, control, synthesized: true),
      _event(ui.KeyEventType.down, v, synthesized: false),
      _event(ui.KeyEventType.up, v, synthesized: false),
      _event(ui.KeyEventType.down, control, synthesized: true),
      _event(ui.KeyEventType.up, control, synthesized: true),
    ]) {
      dispatcher.onKeyData!(event);
    }

    expect(
      forwarded.map((event) => (event.type, event.physical, event.logical)),
      [
        (ui.KeyEventType.down, controlPhysical, control),
        (ui.KeyEventType.down, vPhysical, v),
        (ui.KeyEventType.up, vPhysical, v),
        (ui.KeyEventType.up, controlPhysical, control),
      ],
    );
  });

  test('forwards the normalized sequence through the key data handler', () {
    final fix = WindowsClipboardHistoryKeyDataFix();
    final forwarded = <ui.KeyData>[];
    bool forward(ui.KeyData data) {
      forwarded.add(data);
      return false;
    }

    for (final event in [
      _event(ui.KeyEventType.down, control, synthesized: false),
      _event(ui.KeyEventType.up, control, synthesized: true),
      _event(ui.KeyEventType.down, v, synthesized: false),
      _event(ui.KeyEventType.up, v, synthesized: false),
      _event(ui.KeyEventType.down, control, synthesized: true),
      _event(ui.KeyEventType.up, control, synthesized: true),
    ]) {
      fix.handle(event, forward);
    }

    expect(
      forwarded.map((event) => (event.type, event.physical, event.logical)),
      [
        (ui.KeyEventType.down, controlPhysical, control),
        (ui.KeyEventType.down, vPhysical, v),
        (ui.KeyEventType.up, vPhysical, v),
        (ui.KeyEventType.up, controlPhysical, control),
      ],
    );
  });

  test('releases a rewritten key when an abnormal sequence is interrupted', () {
    final fix = WindowsClipboardHistoryKeyDataFix();
    final forwarded = <ui.KeyData>[];
    bool forward(ui.KeyData data) {
      forwarded.add(data);
      return false;
    }

    fix.handle(
      _event(ui.KeyEventType.down, control, synthesized: false),
      forward,
    );
    final regular = _event(ui.KeyEventType.down, 0x61, physical: 0x00070004);
    fix.handle(regular, forward);

    expect(forwarded, hasLength(3));
    expect(forwarded[1].type, ui.KeyEventType.up);
    expect(forwarded[1].physical, controlPhysical);
    expect(forwarded[2], same(regular));
  });

  test('rewrites the Windows clipboard history Ctrl+V event sequence', () {
    final fix = WindowsClipboardHistoryKeyDataFix();
    final received = [
      _event(ui.KeyEventType.down, control, synthesized: false),
      _event(ui.KeyEventType.up, control, synthesized: true),
      _event(ui.KeyEventType.down, v, synthesized: false),
      _event(ui.KeyEventType.up, v, synthesized: false),
      _event(ui.KeyEventType.down, control, synthesized: true),
      _event(ui.KeyEventType.up, control, synthesized: true),
    ];

    final forwarded = [
      for (final event in received)
        if (fix.rewrite(event) case final rewritten?) rewritten,
    ];

    expect(
      forwarded.map((event) => (event.type, event.physical, event.logical)),
      [
        (ui.KeyEventType.down, controlPhysical, control),
        (ui.KeyEventType.down, vPhysical, v),
        (ui.KeyEventType.up, vPhysical, v),
        (ui.KeyEventType.up, controlPhysical, control),
      ],
    );
    expect(forwarded.every((event) => !event.synthesized), isTrue);
  });

  test('rewrites the legacy sequence while preserving empty probes', () {
    final fix = WindowsClipboardHistoryKeyDataFix();
    final received = [
      _event(ui.KeyEventType.down, control, synthesized: false),
      _event(ui.KeyEventType.down, 0, physical: 0),
      _event(ui.KeyEventType.up, control, synthesized: false),
      _event(ui.KeyEventType.down, control, synthesized: true),
      _event(ui.KeyEventType.up, control, synthesized: true),
    ];
    final forwarded = [
      for (final event in received)
        if (fix.rewrite(event) case final rewritten?) rewritten,
    ];
    expect(
      forwarded.map((event) => (event.type, event.physical, event.logical)),
      [
        (ui.KeyEventType.down, controlPhysical, control),
        (ui.KeyEventType.down, 0, 0),
        (ui.KeyEventType.down, vPhysical, v),
        (ui.KeyEventType.up, vPhysical, v),
        (ui.KeyEventType.up, controlPhysical, control),
      ],
    );
  });

  test('preserves empty transit probes between clipboard history events', () {
    final fix = WindowsClipboardHistoryKeyDataFix();
    fix.rewrite(_event(ui.KeyEventType.down, control, synthesized: false));
    final probe = _event(ui.KeyEventType.down, 0, physical: 0);

    expect(fix.rewrite(probe), same(probe));
    expect(
      fix.rewrite(_event(ui.KeyEventType.up, control, synthesized: true)),
      isNull,
    );
    expect(
      fix
          .rewrite(_event(ui.KeyEventType.down, v, synthesized: false))
          ?.physical,
      vPhysical,
    );
  });

  test(
    'passes regular keyboard events through and resets a partial sequence',
    () {
      final fix = WindowsClipboardHistoryKeyDataFix();
      final regular = _event(ui.KeyEventType.down, 0x61, physical: 0x00070004);

      fix.rewrite(_event(ui.KeyEventType.down, control, synthesized: false));
      expect(fix.rewrite(regular), same(regular));
      expect(
        fix
            .rewrite(_event(ui.KeyEventType.up, control, synthesized: true))
            ?.physical,
        invalidPhysical,
      );
    },
  );
}

const invalidPhysical = 0x1600000000;
const controlPhysical = 0x000700e0;
const vPhysical = 0x00070019;
const control = 0x200000100;
const v = 0x76;

ui.KeyData _event(
  ui.KeyEventType type,
  int logical, {
  int physical = invalidPhysical,
  bool synthesized = true,
}) => ui.KeyData(
  timeStamp: Duration.zero,
  type: type,
  physical: physical,
  logical: logical,
  character: null,
  synthesized: synthesized,
);
