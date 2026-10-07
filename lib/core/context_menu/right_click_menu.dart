/*
 * @Description: 定义共用弹出菜单样式，支持右键定位和锚点上方展开。
 * @Author: LILYGO_L
 * @Date: 2025-11-18 14:00:00
 * @LastEditTime: 2026-10-04 13:01:33
 * @License: GPL 3.0
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/definition.dart';
import '../widgets/menu_item_surface.dart';
import '../widgets/popup_menu_surface.dart';
import '../widgets/popup_menu_transition.dart';

/// 右键菜单项
class RightClickMenuItem {
  final Key? key;
  final String label;
  final Widget? labelWidget;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isEnabled;
  final bool showDivider; // 是否在该项后显示分割线
  final bool isSelected;

  const RightClickMenuItem({
    this.key,
    required this.label,
    this.labelWidget,
    this.icon,
    this.onTap,
    this.isEnabled = true,
    this.showDivider = false, // 默认不显示分割线
    this.isSelected = false,
  });
}

/// 右键菜单控制器
class RightClickMenuController {
  final MenuController _menuController = MenuController();
  final ValueNotifier<int> _openRevision = ValueNotifier(0);
  bool _isEnabled = true;

  void enable() => _isEnabled = true;
  void disable() => _isEnabled = false;
  bool get isEnabled => _isEnabled;

  void open({Offset? position}) {
    if (_isEnabled) {
      // 已打开时 MenuAnchor 只更新位置；显式打开请求也必须重新播放入场动画。
      _openRevision.value++;
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
    VoidCallback? onSecondaryTap,
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
        ValueListenableBuilder<int>(
          valueListenable: controller._openRevision,
          builder: (context, revision, child) => PopupMenuTransition(
            key: ValueKey(revision),
            alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
            child: child!,
          ),
          child: buildMenuPanel(
            menuItems: menuItems,
            theme: theme,
            width: menuWidth,
          ),
        ),
      ],
      child: Listener(
        // 按下时立即移除旧菜单，不等待点击手势确认；松手仍由下方手势打开。
        onPointerDown: onSecondaryTap == null
            ? null
            : (event) {
                if (event.buttons & kSecondaryMouseButton != 0) {
                  controller.close();
                }
              },
        child: GestureDetector(
          // 遵循桌面上下文菜单的松手触发方式，按住右键时不提前覆盖原控件。
          onSecondaryTapUp: onSecondaryTap == null
              ? null
              : (details) {
                  onSecondaryTap();
                  // 调整菜单位置，让菜单更贴近鼠标。
                  final adjustedPosition = Offset(
                    details.localPosition.dx,
                    details.localPosition.dy - 8,
                  );
                  controller.open(position: adjustedPosition);
                },
          child: child,
        ),
      ),
    );
  }

  /// 页面弹层与桌面托盘窗口复用同一份菜单内容、图标和交互动画。
  static Widget buildMenuPanel({
    Key? key,
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    double width = 150,
    List<BoxShadow>? shadows,
  }) => MouseRegion(
    // 覆盖菜单留白处，避免穿透后沿用底层输入框的文字光标。
    cursor: SystemMouseCursors.basic,
    child: SizedBox(
      width: width,
      child: PopupMenuSurface(
        key: key,
        theme: theme,
        shadows: shadows,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildMenuItemsWithDividers(
            menuItems: menuItems,
            theme: theme,
            menuWidth: width - 10,
          ),
        ),
      ),
    ),
  );

  // 构建带分割线的菜单项列表。
  static List<Widget> _buildMenuItemsWithDividers({
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    required double menuWidth,
  }) {
    List<Widget> widgets = [];

    for (int i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      final isLast = i == menuItems.length - 1;

      // 添加菜单项
      widgets.add(
        // 悬停渐变与波纹只重绘当前项，避免快速切换时反复重绘整块浮层和阴影。
        RepaintBoundary(
          child: _buildCustomMenuItem(
            item: item,
            theme: theme,
            menuWidth: menuWidth,
          ),
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
  }) {
    return MenuItemSurface(
      key: item.key,
      theme: theme,
      isSelected: item.isSelected,
      disableWhenSelected: false,
      backgroundColor: PopupMenuSurface.backgroundColorFor(theme),
      hoverColor: theme.basePrimary,
      foregroundColor: item.isEnabled
          ? theme.textColorSecondary
          : theme.textColorTertiary,
      hoverForegroundColor:
          ThemeData.estimateBrightnessForColor(theme.basePrimary) ==
              Brightness.dark
          ? Colors.white
          : const Color(0xFF191919),
      onPressed: item.isEnabled ? item.onTap : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: menuWidth,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                size: 16,
                fill: 1,
                grade: 200,
                opticalSize: 20,
                weight: 300,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: item.isEnabled
                      ? FontWeight.normal
                      : FontWeight.w300,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: item.labelWidget ?? Text(item.label),
              ),
            ),
            if (item.isSelected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
