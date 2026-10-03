/*
 * @Description: 定义共用弹出菜单样式，支持右键定位和锚点上方展开。
 * @Author: LILYGO_L
 * @Date: 2025-11-18 14:00:00
 * @LastEditTime: 2026-10-02 22:01:29
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../theme/definition.dart';
import '../widgets/menu_item_surface.dart';
import '../widgets/popup_menu_surface.dart';

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

  void open({Offset? position}) {
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
    required AppTheme theme,
    required Widget child,
    VoidCallback? onSecondaryTapDown,
    bool openAbove = false,
  }) {
    const double menuWidth = 150; // 设置菜单宽度
    const double menuPadding = 5.0; // 菜单内边距
    // 高度与下方菜单项、间距和分隔线保持一致，向上展开时留出 8 像素间隙。
    final menuHeight =
        menuPadding * 2 +
        menuItems.length * 28 +
        menuItems
            .take(menuItems.isNotEmpty ? menuItems.length - 1 : 0)
            .fold<double>(
              0,
              (height, item) => height + (item.showDivider ? 9 : 4),
            );

    return MenuAnchor(
      controller: controller._menuController,
      clipBehavior: Clip.none,
      alignmentOffset: openAbove ? Offset(0, -menuHeight - 8) : Offset.zero,
      style: MenuStyle(
        alignment: openAbove ? AlignmentDirectional.topStart : null,
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.black),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
      ),
      menuChildren: [
        buildMenuPanel(menuItems: menuItems, theme: theme, width: menuWidth),
      ],
      child: GestureDetector(
        onSecondaryTapDown: onSecondaryTapDown == null
            ? null
            : (details) {
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

  /// 页面弹层与桌面托盘窗口复用同一份菜单内容、图标和交互动画。
  static Widget buildMenuPanel({
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    double width = 150,
    Color? backgroundColor,
  }) => SizedBox(
    width: width,
    child: PopupMenuSurface(
      theme: theme,
      backgroundColor: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildMenuItemsWithDividers(
          menuItems: menuItems,
          theme: theme,
          menuWidth: width - 10,
          backgroundColor: backgroundColor,
        ),
      ),
    ),
  );

  // 构建带分割线的菜单项列表。
  static List<Widget> _buildMenuItemsWithDividers({
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    required double menuWidth,
    Color? backgroundColor,
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
          backgroundColor: backgroundColor,
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

  // 构建分割线。
  static Widget _buildDivider({
    required AppTheme theme,
    required double menuWidth,
  }) {
    return Container(
      width: menuWidth,
      height: 1,
      decoration: BoxDecoration(
        color: theme.dividerColor.withValues(alpha: 0.3),
      ),
    );
  }

  // 构建自定义菜单项。
  static Widget _buildCustomMenuItem({
    required RightClickMenuItem item,
    required AppTheme theme,
    required double menuWidth,
    required bool isLast,
    Color? backgroundColor,
  }) {
    return MenuItemSurface(
      theme: theme,
      backgroundColor:
          backgroundColor ?? PopupMenuSurface.backgroundColorFor(theme),
      hoverColor: theme.adaptiveColor(
        dark: theme.basePrimary,
        light: Color.alphaBlend(
          theme.basePrimary.withValues(alpha: 0.22),
          backgroundColor ?? PopupMenuSurface.backgroundColorFor(theme),
        ),
      ),
      onPressed: item.isEnabled ? item.onTap : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: menuWidth,
        height: 28,
        padding: const EdgeInsets.only(left: 6),
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
              const SizedBox(width: 4),
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
    );
  }
}
