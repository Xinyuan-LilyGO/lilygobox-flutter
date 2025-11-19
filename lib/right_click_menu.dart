/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-18 14:00:00
 * @LastEditTime: 2025-11-19 10:47:38
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
  final bool showDivider; // 是否在该项后显示分割线

  const RightClickMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.isEnabled = true,
    this.showDivider = false, // 默认不显示分割线
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
    const double menuPadding = 5.0; // 菜单内边距

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
        padding: WidgetStateProperty.all(EdgeInsets.zero),
      ),
      menuChildren: [
        // 使用 Container 包裹整个菜单，设置固定宽度和圆角
        Container(
          width: menuWidth,
          padding: EdgeInsets.all(menuPadding), // 添加内边距
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMenuItemsWithDividers(
              menuItems: menuItems,
              theme: theme,
              menuWidth: menuWidth - menuPadding * 2, // 减去内边距后的实际内容宽度
            ),
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

  /// 构建带分割线的菜单项列表
  static List<Widget> _buildMenuItemsWithDividers({
    required List<RightClickMenuItem> menuItems,
    required dynamic theme,
    required double menuWidth,
  }) {
    List<Widget> widgets = [];

    for (int i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      final isLast = i == menuItems.length - 1;

      // 添加菜单项
      widgets.add(
        _buildCustomMenuItem(
          item: item,
          theme: theme,
          menuWidth: menuWidth,
          isLast: isLast && !item.showDivider, // 如果是最后一项且不显示分割线，则应用底部圆角
        ),
      );

      // 如果该项需要显示分割线且不是最后一项，则添加分割线
      if (item.showDivider && !isLast) {
        widgets.add(const SizedBox(height: 4));

        widgets.add(_buildDivider(theme: theme, menuWidth: menuWidth));

        // 在分割线后添加间距
        widgets.add(const SizedBox(height: 4));
      } else if (!isLast) {
        // 在普通菜单项之间添加间距（没有分割线的情况）
        widgets.add(const SizedBox(height: 4));
      }
    }

    return widgets;
  }

  /// 构建分割线
  static Widget _buildDivider({
    required dynamic theme,
    required double menuWidth,
  }) {
    return Container(
      width: menuWidth,
      height: 1,
      decoration: BoxDecoration(color: theme.dividerColor),
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
        hoverColor: theme.sidebarSelectedIconColor,
        onTap: item.isEnabled ? item.onTap : null,
        borderRadius: BorderRadius.circular(5), // 所有项都使用圆角悬停效果
        child: Container(
          width: menuWidth,
          height: 28,
          padding: const EdgeInsets.only(left: 8),
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
                const SizedBox(width: 5),
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
    required VoidCallback onRefresh,
    required VoidCallback onBoardSettings,
    required VoidCallback onDelete,
  }) {
    return [
      RightClickMenuItem(
        label: "刷新",
        icon: Symbols.refresh_rounded,
        onTap: onRefresh,
      ),
      RightClickMenuItem(
        label: "板子设置",
        icon: Symbols.settings_rounded,
        onTap: onBoardSettings,
        showDivider: true, // 在此项后显示分割线
      ),
      RightClickMenuItem(
        label: "删除",
        icon: Symbols.delete_rounded,
        onTap: onDelete,
      ),
    ];
  }
}
