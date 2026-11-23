/*
 * @Description: 提供带展开收起动画、选中状态和悬停渐变的设置下拉框。
 */

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../context_menu/right_click_menu.dart';
import '../../theme/definition.dart';
import '../../theme/material_palette.dart';
import '../app_scroll_behavior.dart';
import '../menu_item_surface.dart';
import '../popup_menu_surface.dart';
import '../popup_menu_transition.dart';
import '../popup_scroll_dismiss.dart';

class SettingSelect<T> extends StatefulWidget {
  const SettingSelect({
    super.key,
    required this.theme,
    required this.value,
    required this.items,
    required this.onChanged,
    this.surfaceColor,
    this.dropdownTapRegionGroupId,
    this.triggerBuilder,
    this.dropdownWidth,
  });

  final AppTheme theme;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// 所在页面或弹窗的实际背景；默认是设置内容区的第二层背景。
  final Color? surfaceColor;

  /// 嵌在菜单中时共享其点击区域，选中下拉项不会关闭外层菜单。
  final Object? dropdownTapRegionGroupId;

  /// 使用按钮等自定义入口直接打开同一套选择菜单。
  final Widget Function(BuildContext context, VoidCallback? onPressed)?
  triggerBuilder;

  /// 自定义入口较窄时，为选项面板提供独立宽度。
  final double? dropdownWidth;

  @override
  State<SettingSelect<T>> createState() => _SettingSelectState<T>();
}

class _SettingSelectState<T> extends State<SettingSelect<T>>
    with SingleTickerProviderStateMixin {
  static const _dropdownAnimationDuration = PopupMenuTransition.duration;

  bool _expanded = false;
  bool _isRemoving = false;
  bool _disposed = false;
  OverlayEntry? _overlayEntry;
  late final AnimationController _dropdownController;
  late final _scrollDismiss = PopupScrollDismiss(onScroll: _removeDropdown);

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
    _scrollDismiss.detach();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _expanded = false;
    _isRemoving = false;
    _dropdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.triggerBuilder case final builder?) {
      return builder(
        context,
        widget.onChanged == null ? null : _toggleDropdown,
      );
    }
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );
    final optionHeight = 32.0;

    final surfaceColor = widget.surfaceColor ?? widget.theme.secondary;
    final controlBackground = widget.theme.selectControlColorForSurface(
      surfaceColor,
    );
    return MenuItemSurface(
      theme: widget.theme,
      onPressed: widget.onChanged == null ? null : _toggleDropdown,
      backgroundColor: controlBackground,
      surfaceColor: controlBackground,
      hoverColor: widget.theme.hoverColorForBackground(controlBackground),
      borderRadius: BorderRadius.circular(4),
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

    final trigger = context.findRenderObject();
    final overlayState = Overlay.of(context);
    final overlay = overlayState.context.findRenderObject();
    if (trigger is! RenderBox || overlay is! RenderBox) return;
    _expanded = true;
    _isRemoving = false;
    _overlayEntry = OverlayEntry(
      builder: (_) => _buildDropdownOverlay(trigger, overlay),
    );
    overlayState.insert(_overlayEntry!);
    _scrollDismiss.attach(context);
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
    _scrollDismiss.detach();

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

  Widget _buildDropdownOverlay(
    RenderBox trigger,
    RenderBox overlay,
  ) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (!trigger.attached || !trigger.hasSize || !overlay.attached) {
          return const SizedBox.shrink();
        }
        final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
        final width = (widget.dropdownWidth ?? trigger.size.width).clamp(
          0.0,
          constraints.maxWidth,
        );
        final left = origin.dx.clamp(0.0, constraints.maxWidth - width);
        final inset = math.min(
          PopupMenuSurface.verticalInset,
          constraints.maxHeight / 2,
        );
        final bottomEdge = constraints.maxHeight - inset;
        const gap = 3.0;
        final below = (origin.dy + trigger.size.height + gap).clamp(
          inset,
          bottomEdge,
        );
        final above = (origin.dy - gap).clamp(inset, bottomEdge);
        final available = bottomEdge - below;
        final naturalHeight = 6.0 + widget.items.length * _optionExtent;
        final desired = math.min(naturalHeight, PopupMenuSurface.listMaxHeight);
        final opensUp = desired > available && above - inset > available;
        final height = math.min(desired, opensUp ? above - inset : available);
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
              left: left,
              top: opensUp ? above - height : below,
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                child: TapRegion(
                  groupId: widget.dropdownTapRegionGroupId,
                  child: PopupMenuTransition(
                    animation: _dropdownController,
                    child: _SettingSelectDropdown<T>(
                      theme: widget.theme,
                      value: widget.value,
                      items: widget.items,
                      height: height,
                      maxOffset: naturalHeight - height,
                      onSelected: (value) {
                        if (_isRemoving) return;
                        widget.onChanged?.call(value);
                        _removeDropdown();
                      },
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

const _optionExtent = 32.0;

class _SettingSelectDropdown<T> extends StatefulWidget {
  const _SettingSelectDropdown({
    required this.theme,
    required this.value,
    required this.items,
    required this.onSelected,
    required this.height,
    required this.maxOffset,
  });

  final AppTheme theme;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onSelected;
  final double height;
  final double maxOffset;

  @override
  State<_SettingSelectDropdown<T>> createState() =>
      _SettingSelectDropdownState<T>();
}

class _SettingSelectDropdownState<T> extends State<_SettingSelectDropdown<T>> {
  late final _scroll = ScrollController(
    keepScrollOffset: false,
    initialScrollOffset:
        (widget.items.indexWhere((item) => item.value == widget.value) *
                    _optionExtent +
                19 -
                widget.height / 2)
            .clamp(0.0, widget.maxOffset),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final overflows = widget.maxOffset > 0;
    final list = ScrollConfiguration(
      behavior: const AppScrollBehavior(scrollbars: false),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(5, 5, overflows ? 25 : 5, 1),
        itemExtent: _optionExtent,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RightClickMenuBuilder.buildMenuItem(
              theme: theme,
              menuWidth: double.infinity,
              itemColor: theme.popupSurfaceColor,
              selectedColor: theme.primaryTextHoverColor,
              selectedForegroundColor: theme.type == ThemeType.light
                  ? Colors.black
                  : null,
              hoverColor: theme.basePrimary,
              item: RightClickMenuItem(
                label: '',
                labelWidget: item.child,
                isSelected: item.value == widget.value,
                isEnabled: item.enabled,
                onTap: () => widget.onSelected(item.value),
              ),
            ),
          );
        },
      ),
    );
    return PopupMenuSurface(
      theme: theme,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(4),
      child: overflows
          ? Scrollbar(controller: _scroll, interactive: true, child: list)
          : list,
    );
  }
}
