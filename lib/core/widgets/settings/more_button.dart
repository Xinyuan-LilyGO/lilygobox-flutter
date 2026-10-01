/*
 * @Description: 提供设置项更多操作入口及重置菜单，管理菜单动画和生命周期。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/definition.dart';
import '../menu_item_surface.dart';

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
  static const Duration _menuAnimationDuration = Duration(milliseconds: 150);
  static const double _buttonSize = 32.0;
  static const double _menuWidth = 132.0;
  static const double _menuHeight = 32.0;

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
    return Tooltip(
      message: '更多操作',
      waitDuration: const Duration(milliseconds: 500),
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
    _menuController.forward(from: 0.0);
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

    if (!animated) {
      completeRemoval();
      return;
    }

    _menuController.reverse().whenComplete(completeRemoval);
  }

  Widget _buildMenuOverlay(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _menuController,
        builder: (context, child) {
          final animationValue = Curves.easeInOut.transform(
            _menuController.value,
          );

          return Stack(
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: SizedBox(
                    height: _menuHeight * animationValue,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: _menuHeight,
                      maxHeight: _menuHeight,
                      child: SizedBox(
                        width: _menuWidth,
                        height: _menuHeight,
                        child: _SettingMoreMenu(
                          theme: widget.theme,
                          onReset: () {
                            widget.onReset?.call();
                            _removeMenu();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingMoreMenu extends StatelessWidget {
  const _SettingMoreMenu({required this.theme, required this.onReset});

  final AppTheme theme;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return MenuItemSurface(
      theme: theme,
      onPressed: onReset,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.28)),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Text(
          AppLocalizations.of(context).resetThisSetting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorPrimary,
            fontSize: 13.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
