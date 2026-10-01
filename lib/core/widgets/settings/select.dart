/*
 * @Description: 提供带展开收起动画、选中状态和悬停渐变的设置下拉框。
 * @Author: LILYGO_L
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../theme/definition.dart';
import '../menu_item_surface.dart';
import 'decoration.dart';

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
  static const Duration _dropdownAnimationDuration = Duration(
    milliseconds: 150,
  );

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
    _dropdownController.forward(from: 0.0);
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

    if (!animated || !_dropdownController.isAnimating && !_expanded) {
      completeRemoval();
      return;
    }

    _dropdownController.reverse().whenComplete(completeRemoval);
  }

  Widget _buildDropdownOverlay(BuildContext context) {
    const optionHeight = 32.0;
    final dropdownHeight = widget.items.length * optionHeight + 2.0;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _dropdownController,
        builder: (context, child) {
          final animationValue = Curves.easeInOut.transform(
            _dropdownController.value,
          );

          return Stack(
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
                top: _dropdownPosition.dy + optionHeight + 3.0,
                width: _targetSize.width,
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: SizedBox(
                      height: dropdownHeight * animationValue,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: dropdownHeight,
                        maxHeight: dropdownHeight,
                        child: SizedBox(
                          width: _targetSize.width,
                          height: dropdownHeight,
                          child: _SettingSelectDropdown<T>(
                            theme: widget.theme,
                            value: widget.value,
                            items: widget.items,
                            onSelected: (value) {
                              widget.onChanged?.call(value);
                              _removeDropdown();
                            },
                            itemTextBuilder: _selectItemText,
                          ),
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
    required this.itemTextBuilder,
  });

  final AppTheme theme;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onSelected;
  final Widget Function(Widget child) itemTextBuilder;

  @override
  Widget build(BuildContext context) {
    const optionHeight = 32.0;
    final dropdownHeight = items.length * optionHeight + 2.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4.0),
      child: Container(
        height: dropdownHeight,
        decoration: settingsControlDecoration(theme, opaque: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = item.value == value;

            return MenuItemSurface(
              theme: theme,
              isSelected: isSelected,
              // 下拉框允许点击当前值收起列表，导航菜单仍禁止重复选中。
              disableWhenSelected: false,
              onPressed: item.enabled ? () => onSelected(item.value) : null,
              borderRadius: _itemBorderRadius(index, items.length),
              child: Container(
                height: optionHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Row(
                  children: [
                    Expanded(child: itemTextBuilder(item.child)),
                    if (isSelected)
                      Icon(
                        Icons.check,
                        size: 16.0,
                        color: theme.textColorPrimary,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  BorderRadius _itemBorderRadius(int index, int count) {
    if (count <= 1) {
      return BorderRadius.circular(4.0);
    }

    if (index == 0) {
      return const BorderRadius.only(
        topLeft: Radius.circular(4.0),
        topRight: Radius.circular(4.0),
      );
    }

    if (index == count - 1) {
      return const BorderRadius.only(
        bottomLeft: Radius.circular(4.0),
        bottomRight: Radius.circular(4.0),
      );
    }

    return BorderRadius.zero;
  }
}
