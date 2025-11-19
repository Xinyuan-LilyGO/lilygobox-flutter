/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-18 14:00:00
 * @LastEditTime: 2025-11-19 09:13:55
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 右键菜单项
class RightClickMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isEnabled;

  const RightClickMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.isEnabled = true,
  });
}

/// 右键菜单控制器
class RightClickMenuController {
  final MenuController _menuController = MenuController();
  bool _isEnabled = true;

  void enable() => _isEnabled = true;
  void disable() => _isEnabled = false;
  bool get isEnabled => _isEnabled;

  void open({required Offset position}) {
    if (_isEnabled) {
      _menuController.open(position: position);
    }
  }

  void close() {
    _menuController.close();
  }

  bool get isOpen => _menuController.isOpen;
}

/// 右键菜单构建器
class RightClickMenuBuilder {
  /// 构建右键菜单锚点
  static Widget buildMenuAnchor({
    required BuildContext context,
    required RightClickMenuController controller,
    required List<RightClickMenuItem> menuItems,
    required dynamic theme,
    required Widget child,
    required VoidCallback onSecondaryTapDown,
  }) {
    const double menuWidth = 150; // 设置菜单宽度

    return MenuAnchor(
      controller: controller._menuController,
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(3),
        shadowColor: WidgetStateProperty.all(Colors.black),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: WidgetStateProperty.all(EdgeInsets.zero), // 移除内边距，使用自定义
      ),
      menuChildren: [
        // 使用 Container 包裹整个菜单，设置固定宽度和圆角
        Container(
          width: menuWidth,
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: menuItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == menuItems.length - 1;

              return _buildCustomMenuItem(
                item: item,
                theme: theme,
                menuWidth: menuWidth,
                isLast: isLast,
              );
            }).toList(),
          ),
        ),
      ],
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          onSecondaryTapDown();
          // 调整菜单位置，让菜单更贴近鼠标
          final adjustedPosition = Offset(
            details.localPosition.dx,
            details.localPosition.dy - 8, // 向上偏移
          );
          controller.open(position: adjustedPosition);
        },
        child: child,
      ),
    );
  }

  /// 构建自定义菜单项
  static Widget _buildCustomMenuItem({
    required RightClickMenuItem item,
    required dynamic theme,
    required double menuWidth,
    required bool isLast,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: theme.primaryTextHoverColor,
        onTap: item.isEnabled ? item.onTap : null,
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              )
            : BorderRadius.zero,
        child: Container(
          width: menuWidth,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 16,
                  color: item.isEnabled
                      ? theme.textColorSecondary
                      : theme.textColorTertiary,
                  fill: 1,
                  grade: 200,
                  opticalSize: 20,
                  weight: 300,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: item.isEnabled
                        ? theme.textColorSecondary
                        : theme.textColorTertiary,
                    fontWeight: item.isEnabled
                        ? FontWeight.normal
                        : FontWeight.w300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 专门用于 T-Glasses-P4 标题的右键菜单
class TGlassesP4RightClickMenu {
  /// 获取 T-Glasses-P4 标题的右键菜单项
  static List<RightClickMenuItem> getMenuItems({
    required VoidCallback onRename,
    required VoidCallback onRefresh,
    required VoidCallback onProperties,
  }) {
    return [
      RightClickMenuItem(
        label: "重命名",
        icon: Symbols.edit_rounded,
        onTap: onRename,
      ),
      RightClickMenuItem(
        label: "刷新",
        icon: Symbols.refresh_rounded,
        onTap: onRefresh,
      ),
      RightClickMenuItem(
        label: "属性",
        icon: Symbols.info_rounded,
        onTap: onProperties,
      ),
    ];
  }
}
