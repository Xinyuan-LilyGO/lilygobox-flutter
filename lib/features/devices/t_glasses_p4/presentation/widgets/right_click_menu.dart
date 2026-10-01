/*
 * @Description: 构建 T-Glasses-P4 标题右键菜单的设备设置和删除入口。
 * @Author: LILYGO_L
 * @Date: 2026-05-16 10:50:23
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../../core/context_menu/right_click_menu.dart';
import '../../../../../core/l10n/language_provider.dart';

/// 专门用于 T-Glasses-P4 标题的右键菜单
class TGlassesP4RightClickMenu {
  /// 获取 T-Glasses-P4 标题的右键菜单项
  static List<RightClickMenuItem> getMenuItems({
    required BuildContext context,
    required VoidCallback onDeviceSettings,
    required VoidCallback onDelete,
  }) {
    return [
      RightClickMenuItem(
        label: context.l10n.deviceSettings,
        icon: Symbols.settings_rounded,
        onTap: onDeviceSettings,
        showDivider: true, // 在此项后显示分割线
      ),
      RightClickMenuItem(
        label: context.l10n.delete,
        icon: Symbols.delete_rounded,
        onTap: onDelete,
      ),
    ];
  }
}
