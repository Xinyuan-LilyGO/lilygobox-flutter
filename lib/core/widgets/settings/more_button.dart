/*
 * @Description: 提供设置项更多操作入口及重置菜单，管理菜单动画和生命周期。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 17:16:37
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../context_menu/right_click_menu.dart';
import '../../theme/definition.dart';
import '../app_tooltip.dart';
import '../menu_item_surface.dart';
import '../popup_menu_transition.dart';

class SettingMoreButton extends StatefulWidget {
  const SettingMoreButton({
    super.key,
    required this.theme,
    required this.onReset,
  });

  final AppTheme theme;
  final VoidCallback? onReset;

  @override
  State<SettingMoreButton> createState() => _SettingMoreButtonState();
}

class _SettingMoreButtonState extends State<SettingMoreButton>
    with SingleTickerProviderStateMixin {
  static const _menuAnimationDuration = PopupMenuTransition.duration;
  static const double _buttonSize = 32.0;
  static const double _menuWidth = 132.0;

  bool _isRemoving = false;
  bool _disposed = false;
  OverlayEntry? _overlayEntry;
  Offset _menuPosition = Offset.zero;
  late final AnimationController _menuController;

  @override
  void initState() {
    super.initState();
    _menuController = AnimationController(
      vsync: this,
      duration: _menuAnimationDuration,
      reverseDuration: _menuAnimationDuration,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isRemoving = false;
    _menuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: AppLocalizations.of(context).moreActions,
      child: MenuItemSurface.control(
        theme: widget.theme,
        onPressed: _toggleMenu,
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Icon(
            Icons.more_horiz_rounded,
            color: widget.theme.textColorTertiary,
            size: 18.0,
          ),
        ),
      ),
    );
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeMenu();
      return;
    }

    final renderBox = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (renderBox is! RenderBox || overlay is! RenderBox) {
      return;
    }

    final position = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    _menuPosition = Offset(
      position.dx + renderBox.size.width - _menuWidth,
      position.dy + _buttonSize + 3.0,
    );
    _isRemoving = false;
    _overlayEntry = OverlayEntry(builder: _buildMenuOverlay);
    Overlay.of(context).insert(_overlayEntry!);
    if (MediaQuery.disableAnimationsOf(context)) {
      _menuController.value = 1;
    } else {
      _menuController.forward(from: 0.0);
    }
  }

  void _removeMenu({bool animated = true}) {
    if (_isRemoving || _disposed) {
      return;
    }

    _isRemoving = true;

    void completeRemoval() {
      if (_disposed) {
        return;
      }

      _overlayEntry?.remove();
      _overlayEntry = null;
      _isRemoving = false;
    }

    if (!animated || MediaQuery.disableAnimationsOf(context)) {
      completeRemoval();
      return;
    }

    _menuController.reverse().whenComplete(completeRemoval);
  }

  Widget _buildMenuOverlay(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: _menuPosition.dx,
            top: _menuPosition.dy,
            width: _menuWidth,
            child: PopupMenuTransition(
              animation: _menuController,
              child: RightClickMenuBuilder.buildMenuPanel(
                theme: widget.theme,
                width: _menuWidth,
                menuItems: [
                  RightClickMenuItem(
                    label: AppLocalizations.of(context).resetThisSetting,
                    isEnabled: widget.onReset != null,
                    onTap: () {
                      if (_isRemoving) return;
                      widget.onReset?.call();
                      _removeMenu();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
