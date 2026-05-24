import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class VscodeSettingsPage extends StatelessWidget {
  const VscodeSettingsPage({
    super.key,
    required this.theme,
    required this.title,
    required this.children,
  });

  final AppTheme theme;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(20.0, 28.0, 20.0, 24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Text(
                title,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Divider(
              color: theme.dividerColor.withValues(alpha: 0.28),
              height: 1,
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class VscodeSettingsRow extends StatelessWidget {
  const VscodeSettingsRow({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.control,
    this.modified = false,
    this.showMoreButton = true,
    this.controlWidth = 210.0,
    this.onReset,
  });

  final AppTheme theme;
  final String title;
  final String description;
  final Widget control;
  final bool modified;
  final bool showMoreButton;
  final double controlWidth;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final borderColor = theme.dividerColor.withValues(alpha: 0.24);

    return Container(
      constraints: const BoxConstraints(minHeight: 68.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 2.0,
              color: modified ? theme.dividerColorNormal : Colors.transparent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720.0;
                final controlGroup = _VscodeControlGroup(
                  theme: theme,
                  control: control,
                  controlWidth: controlWidth,
                  showMoreButton: showMoreButton,
                  onReset: onReset,
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VscodeSettingText(
                        theme: theme,
                        title: title,
                        description: description,
                      ),
                      const SizedBox(height: 10.0),
                      controlGroup,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _VscodeSettingText(
                        theme: theme,
                        title: title,
                        description: description,
                      ),
                    ),
                    const SizedBox(width: 30.0),
                    controlGroup,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VscodeSettingTextField extends StatelessWidget {
  const VscodeSettingTextField({
    super.key,
    required this.theme,
    required this.value,
    this.onChanged,
  });

  final AppTheme theme;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32.0,
      child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        cursorColor: theme.dividerColorNormal,
        style: TextStyle(
          color: theme.textColorPrimary,
          fontSize: 13.0,
          fontWeight: FontWeight.w600,
        ),
        decoration: _inputDecoration(theme),
      ),
    );
  }
}

class VscodeSettingReadOnlyField extends StatelessWidget {
  const VscodeSettingReadOnlyField({
    super.key,
    required this.theme,
    required this.value,
  });

  final AppTheme theme;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.0,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.textColorSecondary,
          fontSize: 13.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class VscodeSettingSelect<T> extends StatefulWidget {
  const VscodeSettingSelect({
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
  State<VscodeSettingSelect<T>> createState() => _VscodeSettingSelectState<T>();
}

class _VscodeSettingSelectState<T> extends State<VscodeSettingSelect<T>>
    with SingleTickerProviderStateMixin {
  static const Duration _dropdownAnimationDuration = Duration(
    milliseconds: 150,
  );

  Color? _selectedHoverColor;
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

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _selectedHoverColor = widget.theme.secondaryTextHoverColor;
          });
        },
        onExit: (_) {
          setState(() {
            _selectedHoverColor = null;
          });
        },
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(4.0),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: optionHeight,
            padding: const EdgeInsets.only(left: 10.0, right: 6.0),
            decoration: _controlDecoration(
              widget.theme,
              color: _selectedHoverColor,
            ),
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
    _dropdownPosition = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
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
                          child: _VscodeSelectDropdown<T>(
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

class _VscodeSelectDropdown<T> extends StatefulWidget {
  const _VscodeSelectDropdown({
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
  State<_VscodeSelectDropdown<T>> createState() =>
      _VscodeSelectDropdownState<T>();
}

class _VscodeSelectDropdownState<T> extends State<_VscodeSelectDropdown<T>> {
  final Set<T?> _hoveredValues = <T?>{};

  @override
  Widget build(BuildContext context) {
    const optionHeight = 32.0;
    final dropdownHeight = widget.items.length * optionHeight + 2.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4.0),
      child: Container(
        height: dropdownHeight,
        decoration: _controlDecoration(widget.theme, opaque: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = item.value == widget.value;
            final isHovered = _hoveredValues.contains(item.value);
            final itemColor = isSelected
                ? widget.theme.primaryTextSelectedColor
                : isHovered
                ? widget.theme.primaryTextHoverColor
                : widget.theme.primary;

            return Material(
              color: Colors.transparent,
              child: MouseRegion(
                onEnter: (_) {
                  setState(() => _hoveredValues.add(item.value));
                },
                onExit: (_) {
                  setState(() => _hoveredValues.remove(item.value));
                },
                child: InkWell(
                  onTap: () => widget.onSelected(item.value),
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  child: Container(
                    height: optionHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    decoration: BoxDecoration(
                      color: itemColor,
                      borderRadius: _itemBorderRadius(
                        index,
                        widget.items.length,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: widget.itemTextBuilder(item.child)),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            size: 16.0,
                            color: widget.theme.textColorPrimary,
                          ),
                      ],
                    ),
                  ),
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

class VscodeSettingStepper extends StatelessWidget {
  const VscodeSettingStepper({
    super.key,
    required this.theme,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final AppTheme theme;
  final int value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.0,
      decoration: _controlDecoration(theme),
      child: Row(
        children: [
          _VscodeStepperButton(
            theme: theme,
            icon: Icons.remove_rounded,
            onPressed: onDecrement,
          ),
          Expanded(
            child: Center(
              child: Text(
                '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textColorPrimary,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _VscodeStepperButton(
            theme: theme,
            icon: Icons.add_rounded,
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

class VscodeSettingActionButton extends StatelessWidget {
  const VscodeSettingActionButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
  });

  final AppTheme theme;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4.0),
        hoverColor: theme.secondaryTextHoverColor,
        splashColor: theme.tertiaryTextSplashColor,
        child: Container(
          height: 32.0,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          decoration: _controlDecoration(theme),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textColorPrimary,
              fontSize: 13.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _VscodeSettingText extends StatelessWidget {
  const _VscodeSettingText({
    required this.theme,
    required this.title,
    required this.description,
  });

  final AppTheme theme;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorPrimary,
            fontSize: 15.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.textColorSecondary,
            fontSize: 13.0,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _VscodeControlGroup extends StatelessWidget {
  const _VscodeControlGroup({
    required this.theme,
    required this.control,
    required this.controlWidth,
    required this.showMoreButton,
    required this.onReset,
  });

  final AppTheme theme;
  final Widget control;
  final double controlWidth;
  final bool showMoreButton;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: controlWidth, child: control),
        if (showMoreButton) ...[
          const SizedBox(width: 14.0),
          _VscodeMoreButton(theme: theme, onReset: onReset),
        ],
      ],
    );
  }
}

class _VscodeMoreButton extends StatefulWidget {
  const _VscodeMoreButton({required this.theme, required this.onReset});

  final AppTheme theme;
  final VoidCallback? onReset;

  @override
  State<_VscodeMoreButton> createState() => _VscodeMoreButtonState();
}

class _VscodeMoreButtonState extends State<_VscodeMoreButton>
    with SingleTickerProviderStateMixin {
  static const Duration _menuAnimationDuration = Duration(milliseconds: 150);
  static const double _buttonSize = 32.0;
  static const double _menuWidth = 132.0;
  static const double _menuHeight = 32.0;

  bool _hovered = false;
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
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: _controlDecoration(
              widget.theme,
              color: _hovered ? widget.theme.secondaryTextHoverColor : null,
            ),
            child: InkWell(
              onTap: _toggleMenu,
              borderRadius: BorderRadius.circular(4.0),
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Icon(
                Icons.more_horiz_rounded,
                color: widget.theme.textColorTertiary,
                size: 18.0,
              ),
            ),
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
                        child: _VscodeMoreMenu(
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

class _VscodeMoreMenu extends StatefulWidget {
  const _VscodeMoreMenu({required this.theme, required this.onReset});

  final AppTheme theme;
  final VoidCallback onReset;

  @override
  State<_VscodeMoreMenu> createState() => _VscodeMoreMenuState();
}

class _VscodeMoreMenuState extends State<_VscodeMoreMenu> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: Container(
          decoration: _controlDecoration(widget.theme, opaque: true),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: widget.onReset,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                decoration: BoxDecoration(
                  color: _hovered
                      ? widget.theme.primaryTextHoverColor
                      : widget.theme.primary,
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                AppLocalizations.of(context).resetThisSetting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.theme.textColorPrimary,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _VscodeStepperButton extends StatelessWidget {
  const _VscodeStepperButton({
    required this.theme,
    required this.icon,
    required this.onPressed,
  });

  final AppTheme theme;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: theme.secondaryTextHoverColor,
        splashColor: theme.tertiaryTextSplashColor,
        child: SizedBox(
          width: 32.0,
          height: 32.0,
          child: Icon(icon, color: theme.textColorPrimary, size: 16.0),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(AppTheme theme) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: theme.primary.withValues(alpha: 0.74),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 10.0,
      vertical: 8.0,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide(
        color: theme.dividerColor.withValues(alpha: 0.28),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4.0),
      borderSide: BorderSide(color: theme.dividerColorNormal),
    ),
  );
}

BoxDecoration _controlDecoration(
  AppTheme theme, {
  Color? color,
  bool opaque = false,
}) {
  return BoxDecoration(
    color: color ??
        (opaque ? theme.primary : theme.primary.withValues(alpha: 0.74)),
    borderRadius: BorderRadius.circular(4.0),
    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.28)),
  );
}
