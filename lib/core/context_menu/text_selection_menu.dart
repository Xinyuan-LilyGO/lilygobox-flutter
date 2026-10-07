/*
 * @Description: 让文本编辑和选中文字复用应用右键菜单，保留系统剪贴板及选择行为。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 00:00:00
 * @LastEditTime: 2026-10-07 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../theme/provider.dart';
import '../widgets/popup_menu_transition.dart';
import 'right_click_menu.dart';

class AppTextSelectionMenu {
  /// 直接作为 contextMenuBuilder 传入，避免页面刷新时新建闭包使 Flutter 关闭并重开菜单。
  static Widget build(BuildContext context, EditableTextState editableText) =>
      Consumer<ThemeProvider>(
        // 配色在浮层内订阅，切换主题只更新内容，不替换文本框的菜单回调。
        builder: (context, provider, _) =>
            _buildForTheme(context, editableText, provider.themeData),
      );

  // 可用操作和剪贴板逻辑由 Flutter 提供，等待状态就绪再显示。
  static Widget _buildForTheme(
    BuildContext context,
    EditableTextState editableText,
    AppTheme theme,
  ) => ValueListenableBuilder<ClipboardStatus>(
    valueListenable: editableText.clipboardStatus,
    builder: (context, status, _) {
      // 剪贴板异步查询完成后一次显示菜单，避免粘贴项补入导致高度和位置跳变。
      if (!editableText.widget.readOnly && status == ClipboardStatus.unknown) {
        return const SizedBox.shrink();
      }
      return _buildPanel(context, editableText, theme);
    },
  );

  // 使用 Flutter 的锚点布局和操作回调，菜单内容统一复用应用样式。
  static Widget _buildPanel(
    BuildContext context,
    EditableTextState editableText,
    AppTheme theme,
  ) {
    final buttons = editableText.contextMenuButtonItems;
    if (buttons.isEmpty) return const SizedBox.shrink();
    final top = MediaQuery.paddingOf(context).top + 8;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top, 8, 8),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor:
              editableText.contextMenuAnchors.primaryAnchor - Offset(8, top),
        ),
        child: PopupMenuTransition(
          // 使用文本选择层的同一份 150ms 进度，避免两层淡入相乘。
          animation: context
              .findAncestorWidgetOfExactType<FadeTransition>()
              ?.opacity,
          fade: false,
          child: RightClickMenuBuilder.buildMenuPanel(
            theme: theme,
            menuItems: [
              for (final button in buttons)
                RightClickMenuItem(
                  label: AdaptiveTextSelectionToolbar.getButtonLabel(
                    context,
                    button,
                  ),
                  icon: switch (button.type) {
                    ContextMenuButtonType.cut => Symbols.content_cut,
                    ContextMenuButtonType.copy => Symbols.content_copy,
                    ContextMenuButtonType.paste => Symbols.content_paste,
                    ContextMenuButtonType.selectAll => Symbols.select_all,
                    ContextMenuButtonType.delete => Symbols.delete_rounded,
                    _ => null,
                  },
                  isEnabled: button.onPressed != null,
                  onTap: button.onPressed,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
