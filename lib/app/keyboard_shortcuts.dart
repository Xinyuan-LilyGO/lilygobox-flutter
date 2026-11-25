/*
 * @Description: 提供跨页面共用的应用级键盘快捷键。
 */

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Map<ShortcutActivator, Intent> get appKeyboardShortcuts => {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
      const RedoTextIntent(SelectionChangedCause.keyboard),
};
