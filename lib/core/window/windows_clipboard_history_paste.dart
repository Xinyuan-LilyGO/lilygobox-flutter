/*
 * @Description: 修正 Windows 剪贴板历史发送的 Ctrl+V 键盘事件序列。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 18:05:00
 * @LastEditTime: 2026-11-05 18:15:22
 * @License: GPL 3.0
 */

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// 兼容 Flutter Windows runner 对剪贴板历史合成按键的错误映射。
class WindowsClipboardHistoryKeyDataFix {
  static const _invalidPhysical = 0x1600000000;
  static const _controlPhysical = 0x000700e0;
  static const _vPhysical = 0x00070019;
  static const _controlLogical = 0x200000100;
  static const _vLogical = 0x76;

  var _step = 0;
  final _pressed = <int, int>{};

  /// Forwards corrected events and releases keys if an abnormal sequence breaks.
  @visibleForTesting
  bool handle(ui.KeyData data, ui.KeyDataCallback forward) {
    final rewritten = rewrite(data);
    if (rewritten == null) return true;

    final isProbe = data.physical == 0 && data.logical == 0;
    if (!isProbe && identical(rewritten, data) && _pressed.isNotEmpty) {
      for (final entry in _pressed.entries) {
        forward(
          ui.KeyData(
            timeStamp: data.timeStamp,
            type: ui.KeyEventType.up,
            physical: entry.key,
            logical: entry.value,
            character: null,
            synthesized: true,
            deviceType: data.deviceType,
          ),
        );
      }
      _pressed.clear();
    }
    if (!identical(rewritten, data)) {
      if (rewritten.type == ui.KeyEventType.up) {
        _pressed.remove(rewritten.physical);
      } else {
        _pressed[rewritten.physical] = rewritten.logical;
      }
    }
    return forward(rewritten);
  }

  /// 返回应交给 Flutter 的事件；null 表示该事件是异常序列中的冗余事件。
  @visibleForTesting
  ui.KeyData? rewrite(ui.KeyData data) {
    // Flutter 用空事件探测键盘传输模式，必须原样转发且不打断当前序列。
    if (data.physical == 0 && data.logical == 0) return data;
    if (data.physical != _invalidPhysical) {
      _step = 0;
      return data;
    }

    final isControl = data.logical == _controlLogical;
    final isV = data.logical == _vLogical;
    if (_step == 1 &&
        isControl &&
        data.type == ui.KeyEventType.up &&
        !data.synthesized) {
      // 旧版引擎把 V 的按下也映射为 Ctrl 松开。
      _step = 6;
      return _copy(
        data,
        type: ui.KeyEventType.down,
        physical: _vPhysical,
        logical: _vLogical,
      );
    }
    if (_step == 6 &&
        isControl &&
        data.type == ui.KeyEventType.down &&
        data.synthesized) {
      _step = 5;
      return _copy(
        data,
        type: ui.KeyEventType.up,
        physical: _vPhysical,
        logical: _vLogical,
      );
    }
    final rewritten = switch (_step) {
      0
          when isControl &&
              data.type == ui.KeyEventType.down &&
              !data.synthesized =>
        _copy(
          data,
          type: ui.KeyEventType.down,
          physical: _controlPhysical,
          logical: _controlLogical,
        ),
      1 when isControl && data.type == ui.KeyEventType.up && data.synthesized =>
        null,
      2 when isV && data.type == ui.KeyEventType.down => _copy(
        data,
        type: ui.KeyEventType.down,
        physical: _vPhysical,
        logical: _vLogical,
      ),
      3 when isV && data.type == ui.KeyEventType.up => _copy(
        data,
        type: ui.KeyEventType.up,
        physical: _vPhysical,
        logical: _vLogical,
      ),
      4
          when isControl &&
              data.type == ui.KeyEventType.down &&
              data.synthesized =>
        null,
      5 when isControl && data.type == ui.KeyEventType.up && data.synthesized =>
        _copy(
          data,
          type: ui.KeyEventType.up,
          physical: _controlPhysical,
          logical: _controlLogical,
        ),
      _ => _resetAndForward(data),
    };

    if (rewritten == null) {
      if (_step == 5) {
        _step = 0;
      } else if (_step != 0 || isControl && data.type == ui.KeyEventType.up) {
        _step++;
      }
      return null;
    }

    if (_step == 5) {
      _step = 0;
    } else if (rewritten.physical != data.physical) {
      _step++;
    }
    return rewritten;
  }

  ui.KeyData _resetAndForward(ui.KeyData data) {
    _step = 0;
    return data;
  }

  ui.KeyData _copy(
    ui.KeyData data, {
    required ui.KeyEventType type,
    required int physical,
    required int logical,
  }) => ui.KeyData(
    timeStamp: data.timeStamp,
    type: type,
    physical: physical,
    logical: logical,
    character: null,
    synthesized: false,
    deviceType: data.deviceType,
  );
}

/// 首帧后安装，避免被 ServicesBinding 异步初始化的键盘回调覆盖。
void installWindowsClipboardHistoryPasteFix() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final dispatcher = ui.PlatformDispatcher.instance;
    final original = dispatcher.onKeyData;
    if (original == null) return;

    final fix = WindowsClipboardHistoryKeyDataFix();
    dispatcher.onKeyData = (data) => fix.handle(data, original);
  });
}
