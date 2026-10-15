/*
 * @Description: 提供带展开收起动画、选中状态和悬停渐变的设置下拉框。
 * @Author: LILYGO_L
 * @Date: 2026-10-01 15:49:33
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../context_menu/right_click_menu.dart';
import '../../theme/definition.dart';
import '../../theme/material_palette.dart';
import '../menu_item_surface.dart';
import '../popup_menu_transition.dart';

class SettingSelect<T> extends StatefulWidget {
  const SettingSelect({
    super.key,
    required this.theme,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final AppTheme theme;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  State<SettingSelect<T>> createState() => _SettingSelectState<T>();
}

class _SettingSelectState<T> extends State<SettingSelect<T>>
    with SingleTickerProviderStateMixin {
  static const _dropdownAnimationDuration = PopupMenuTransition.duration;

  bool _expanded = false;
  bool _isRemoving = false;
  bool _disposed = false;
  Size _targetSize = Size.zero;
  Offset _dropdownPosition = Offset.zero;
  OverlayEntry? _overlayEntry;
  late final AnimationController _dropdownController;

  @override
  void initState() {
    super.initState();
    _dropdownController = AnimationController(
      vsync: this,
      duration: _dropdownAnimationDuration,
      reverseDuration: _dropdownAnimationDuration,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _expanded = false;
    _isRemoving = false;
    _dropdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );
    final optionHeight = 32.0;

    return MenuItemSurface.control(
      theme: widget.theme,
      onPressed: widget.onChanged == null ? null : _toggleDropdown,
      showBorder: false,
      child: Container(
        height: optionHeight,
        padding: const EdgeInsets.only(left: 10.0, right: 6.0),
        child: Row(
          children: [
            Expanded(child: _selectItemText(selectedItem.child)),
            AnimatedRotation(
              turns: _expanded ? 0.0 : -0.25,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              child: Icon(
                Icons.arrow_drop_down,
                color: widget.theme.textColorSecondary,
                size: 20.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDropdown() {
    if (_expanded) {
      _removeDropdown();
      return;
    }

    final renderBox = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (renderBox is! RenderBox || overlay is! RenderBox) {
      return;
    }

    _targetSize = renderBox.size;
    _dropdownPosition = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    _expanded = true;
    _isRemoving = false;
    _overlayEntry = OverlayEntry(builder: _buildDropdownOverlay);
    Overlay.of(context).insert(_overlayEntry!);
    if (MediaQuery.disableAnimationsOf(context)) {
      _dropdownController.value = 1;
    } else {
      _dropdownController.forward(from: 0.0);
    }
    setState(() {});
  }

  void _removeDropdown({bool updateState = true, bool animated = true}) {
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

      if (updateState && _expanded && mounted) {
        setState(() => _expanded = false);
      } else {
        _expanded = false;
      }
    }

    if (!animated ||
        MediaQuery.disableAnimationsOf(context) ||
        !_dropdownController.isAnimating && !_expanded) {
      completeRemoval();
      return;
    }

    _dropdownController.reverse().whenComplete(completeRemoval);
  }

  Widget _buildDropdownOverlay(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeDropdown,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: _dropdownPosition.dx,
            top: _dropdownPosition.dy + _targetSize.height + 3,
            width: _targetSize.width,
            child: Material(
              color: Colors.transparent,
              child: PopupMenuTransition(
                animation: _dropdownController,
                child: _SettingSelectDropdown<T>(
                  theme: widget.theme,
                  value: widget.value,
                  items: widget.items,
                  width: _targetSize.width,
                  onSelected: (value) {
                    if (_isRemoving) return;
                    widget.onChanged?.call(value);
                    _removeDropdown();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectItemText(Widget child) {
    return DefaultTextStyle(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: widget.theme.textColorPrimary,
        fontSize: 13.0,
        fontWeight: FontWeight.w600,
      ),
      child: child,
    );
  }
}

class _SettingSelectDropdown<T> extends StatelessWidget {
  const _SettingSelectDropdown({
    required this.theme,
    required this.value,
    required this.items,
    required this.onSelected,
    required this.width,
  });

  final AppTheme theme;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onSelected;
  final double width;

  @override
  Widget build(BuildContext context) => RightClickMenuBuilder.buildMenuPanel(
    theme: theme,
    width: width,
    surfaceColor: theme.popupSurfaceColor,
    itemColor: theme.popupSurfaceColor,
    selectedColor: theme.primaryTextHoverColor,
    selectedForegroundColor: theme.type == ThemeType.light
        ? Colors.black
        : null,
    hoverColor: theme.basePrimary,
    borderRadius: BorderRadius.circular(4),
    menuItems: [
      for (final item in items)
        RightClickMenuItem(
          label: '',
          labelWidget: item.child,
          isSelected: item.value == value,
          isEnabled: item.enabled,
          onTap: () => onSelected(item.value),
        ),
    ],
  );
}
