/*
 * @Description: 定义共用弹出菜单样式，支持右键定位和锚点上方展开。
 */

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/definition.dart';
import '../theme/material_palette.dart';
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
  final List<RightClickMenuItem> children;

  const RightClickMenuItem({
    this.key,
    required this.label,
    this.labelWidget,
    this.icon,
    this.onTap,
    this.isEnabled = true,
    this.showDivider = false, // 默认不显示分割线
    this.isSelected = false,
    this.children = const [],
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

class _ContextMenuGesture extends StatelessWidget {
  const _ContextMenuGesture({
    required this.exclusive,
    required this.onSecondaryTapUp,
    required this.child,
  });

  final bool exclusive;
  final GestureTapUpCallback? onSecondaryTapUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!exclusive || onSecondaryTapUp == null) {
      return GestureDetector(onSecondaryTapUp: onSecondaryTapUp, child: child);
    }
    return RawGestureDetector(
      gestures: {
        _ExclusiveSecondaryTapRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _ExclusiveSecondaryTapRecognizer
            >(_ExclusiveSecondaryTapRecognizer.new, (recognizer) {
              recognizer.onSecondaryTapDown = (_) {
                ContextMenuController.removeAny();
              };
              recognizer.onSecondaryTapUp = onSecondaryTapUp;
            }),
      },
      child: child,
    );
  }
}

class _ExclusiveSecondaryTapRecognizer extends TapGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 右键菜单构建器
class RightClickMenuBuilder {
  static const _defaultWidth = 150.0;
  static const _menuPadding = 5.0;
  static const _itemPadding = 6.0;
  static const _iconSize = 16.0;
  static const _iconGap = 4.0;
  static const _edgeInset = 8.0;
  static const _submenuGap = 8.0;

  static TextStyle _labelStyle(RightClickMenuItem item) => TextStyle(
    fontSize: 13,
    fontWeight: item.isEnabled ? FontWeight.normal : FontWeight.w300,
  );

  static double _fittedWidth(
    BuildContext context,
    Iterable<RightClickMenuItem> items,
    double minWidth,
  ) {
    final textStyle = Theme.of(context).textTheme.bodyMedium!;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    var width = minWidth;
    for (final item in items) {
      painter.text = TextSpan(
        text: item.label,
        style: textStyle.merge(_labelStyle(item)),
      );
      painter.layout();
      final itemWidth =
          painter.width.ceilToDouble() +
          2 * (_menuPadding + _itemPadding) +
          (item.icon != null ? _iconSize + _iconGap : 0) +
          (item.isSelected || item.children.isNotEmpty
              ? _iconGap + _iconSize
              : 0) +
          2;
      if (itemWidth > width) width = itemWidth;
    }
    painter.dispose();
    return width;
  }

  static double _submenuWidth(
    BuildContext context,
    Iterable<RightClickMenuItem> items,
    double parentWidth,
    double availableWidth,
  ) => _fittedWidth(context, items, _defaultWidth).clamp(
    0.0,
    (availableWidth - parentWidth - _submenuGap - 2 * _edgeInset).clamp(
      0.0,
      double.infinity,
    ),
  );

  static const _panelStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    elevation: WidgetStatePropertyAll(0),
    shadowColor: WidgetStatePropertyAll(Colors.black),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
  );

  /// 构建右键菜单锚点
  static Widget buildMenuAnchor({
    required BuildContext context,
    required RightClickMenuController controller,
    List<RightClickMenuItem> menuItems = const [],
    List<RightClickMenuItem> Function()? menuItemsBuilder,
    required AppTheme theme,
    required Widget child,
    VoidCallback? onSecondaryTap,
    bool exclusiveSecondaryTap = false,
    ValueChanged<PointerEvent>? onMenuPointerEvent,
    Object? menuTapRegionGroupId,
    bool openAbove = false,
    Offset alignmentOffset = Offset.zero,
    double menuWidth = _defaultWidth,
    bool fitWidthToItems = false,
    bool fitHeightToWindow = false,
  }) {
    // 高度与下方菜单项、间距和分隔线保持一致，向上展开时留出 8 像素间隙。
    double heightFor(List<RightClickMenuItem> items) =>
        _menuPadding * 2 +
        items.length * 28 +
        items
            .take(items.isNotEmpty ? items.length - 1 : 0)
            .fold<double>(
              0,
              (height, item) => height + (item.showDivider ? 9 : 4),
            );

    // 菜单超出窗口时，MenuAnchor 会自行添加滚动视图。
    // 为滚动条留出空间，避免遮挡菜单项的点击区域和文字。
    final windowHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = fitHeightToWindow
        ? (windowHeight - 2 * _edgeInset).clamp(0.0, double.infinity)
        : (windowHeight - 48).clamp(0.0, 640.0);
    double gutterFor(double height) => height > maxHeight ? 20 : 0;
    double visibleHeight(double height) => height.clamp(0.0, maxHeight);
    double panelWidthFor(
      BuildContext context,
      List<RightClickMenuItem> items,
      double gutter,
      double availableWidth,
    ) {
      final width =
          (fitWidthToItems
              ? _fittedWidth(context, items, menuWidth)
              : menuWidth) +
          gutter;
      final hasSubmenu = items.any((item) => item.children.isNotEmpty);
      if (!fitWidthToItems && !hasSubmenu) return width;
      final available = (availableWidth - 2 * _edgeInset).clamp(
        0.0,
        double.infinity,
      );
      final limit = hasSubmenu && available >= 2 * _defaultWidth + _submenuGap
          ? available - _defaultWidth - _submenuGap
          : available;
      return width.clamp(0.0, limit);
    }

    return MenuAnchor(
      controller: controller._menuController,
      clipBehavior: Clip.none,
      alignmentOffset: openAbove
          ? Offset(
                  0,
                  -visibleHeight(
                        heightFor(menuItemsBuilder?.call() ?? menuItems),
                      ) -
                      8,
                ) +
                alignmentOffset
          : alignmentOffset,
      style: _panelStyle.copyWith(
        maximumSize: WidgetStatePropertyAll(Size(double.infinity, maxHeight)),
        alignment: openAbove ? AlignmentDirectional.topStart : null,
      ),
      menuChildren: [
        TapRegion(
          enabled: menuTapRegionGroupId != null,
          groupId: menuTapRegionGroupId,
          child: ValueListenableBuilder<int>(
            valueListenable: controller._openRevision,
            builder: (context, revision, child) => PopupMenuTransition(
              key: ValueKey(revision),
              alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
              // 覆盖层不在原锚点的指针路径中；允许画布接收从菜单上开始的
              // 原始拖动序列，普通菜单不传此回调时保持原有行为。
              child: onMenuPointerEvent == null
                  ? child!
                  : Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: onMenuPointerEvent,
                      onPointerDown: onMenuPointerEvent,
                      onPointerMove: onMenuPointerEvent,
                      onPointerUp: onMenuPointerEvent,
                      onPointerCancel: onMenuPointerEvent,
                      child: child!,
                    ),
            ),
            child: Builder(
              builder: (context) {
                final items = menuItemsBuilder?.call() ?? menuItems;
                final gutter = gutterFor(heightFor(items));
                return buildMenuPanel(
                  menuItems: items,
                  theme: theme,
                  width: panelWidthFor(
                    context,
                    items,
                    gutter,
                    MediaQuery.sizeOf(context).width,
                  ),
                  trailingInset: gutter,
                );
              },
            ),
          ),
        ),
      ],
      child: Builder(
        builder: (anchorContext) => Listener(
          behavior: HitTestBehavior.opaque,
          // 锚点属于 MenuAnchor 的内部区域，系统不会把点击图片当作外部点击。
          // 左键按下也应立即关闭菜单；右键松手仍由下方手势重新打开。
          onPointerDown: onSecondaryTap == null
              ? null
              : (event) {
                  if (event.buttons &
                          (kPrimaryMouseButton | kSecondaryMouseButton) !=
                      0) {
                    controller.close();
                  }
                },
          child: _ContextMenuGesture(
            exclusive: exclusiveSecondaryTap,
            // 遵循桌面上下文菜单的松手触发方式，按住右键时不提前覆盖原控件。
            onSecondaryTapUp: onSecondaryTap == null
                ? null
                : (details) {
                    onSecondaryTap();
                    // 菜单按覆盖层像素定位，不能把缩放画布内的局部坐标直接相加。
                    final anchorBox =
                        anchorContext.findRenderObject()! as RenderBox;
                    final overlayBox =
                        Overlay.of(anchorContext).context.findRenderObject()!
                            as RenderBox;
                    final anchorOrigin = overlayBox.globalToLocal(
                      anchorBox.localToGlobal(Offset.zero),
                    );
                    final pointerPosition = overlayBox.globalToLocal(
                      details.globalPosition,
                    );
                    var menuOrigin = pointerPosition - const Offset(0, 8);
                    if (!openAbove) {
                      final items = menuItemsBuilder?.call() ?? menuItems;
                      final contentHeight = heightFor(items);
                      final menuHeight = visibleHeight(contentHeight);
                      final panelWidth = panelWidthFor(
                        anchorContext,
                        items,
                        gutterFor(contentHeight),
                        overlayBox.size.width,
                      );
                      // Flutter 溢出时会相对整张锚点卡片翻转，长卡片会让菜单
                      // 跳到远离鼠标的位置。先在覆盖层内围绕鼠标翻转并限位，
                      // 再转回锚点偏移，避免触发框架的二次翻转。
                      if (menuOrigin.dy + menuHeight >
                          overlayBox.size.height - _edgeInset) {
                        menuOrigin = Offset(
                          menuOrigin.dx,
                          pointerPosition.dy + _edgeInset - menuHeight,
                        );
                      }
                      if (menuOrigin.dx + panelWidth >
                          overlayBox.size.width - _edgeInset) {
                        menuOrigin = Offset(
                          pointerPosition.dx - panelWidth,
                          menuOrigin.dy,
                        );
                      }
                      final maxX =
                          (overlayBox.size.width - panelWidth - _edgeInset)
                              .clamp(_edgeInset, double.infinity);
                      final maxY =
                          (overlayBox.size.height - menuHeight - _edgeInset)
                              .clamp(_edgeInset, double.infinity);
                      var left = menuOrigin.dx.clamp(_edgeInset, maxX);
                      final submenuItems = items.expand(
                        (item) => item.children,
                      );
                      if (submenuItems.isNotEmpty) {
                        final submenuWidth = _submenuWidth(
                          anchorContext,
                          submenuItems,
                          panelWidth,
                          overlayBox.size.width,
                        );
                        final rightLimit = maxX - _submenuGap - submenuWidth;
                        final leftLimit =
                            _edgeInset + _submenuGap + submenuWidth;
                        if (rightLimit >= _edgeInset &&
                            left > rightLimit &&
                            left < leftLimit) {
                          left = left - rightLimit <= leftLimit - left
                              ? rightLimit
                              : leftLimit;
                        }
                      }
                      menuOrigin = Offset(
                        left,
                        menuOrigin.dy.clamp(_edgeInset, maxY),
                      );
                    }
                    // 向上展开的工具栏菜单沿用锚点定位，避免鼠标位置覆盖上方偏移。
                    controller.open(
                      position: openAbove ? null : menuOrigin - anchorOrigin,
                    );
                  },
            child: child,
          ),
        ),
      ),
    );
  }

  /// 页面弹层与桌面托盘窗口复用同一份菜单内容、图标和交互动画。
  static Widget buildMenuPanel({
    Key? key,
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    double width = _defaultWidth,
    double trailingInset = 0,
    List<BoxShadow>? shadows,
    Color? surfaceColor,
    Color? itemColor,
    Color? selectedColor,
    Color? selectedForegroundColor,
    Color? hoverColor,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(8)),
  }) => MouseRegion(
    // 覆盖菜单留白处，避免穿透后沿用底层输入框的文字光标。
    cursor: SystemMouseCursors.basic,
    child: SizedBox(
      width: width,
      child: PopupMenuSurface(
        key: key,
        theme: theme,
        shadows: shadows,
        backgroundColor: surfaceColor,
        borderRadius: borderRadius,
        child: Padding(
          padding: EdgeInsetsDirectional.only(end: trailingInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMenuItemsWithDividers(
              menuItems: menuItems,
              theme: theme,
              panelWidth: width,
              menuWidth: width - 2 * _menuPadding - trailingInset,
              itemColor: itemColor,
              selectedColor: selectedColor,
              selectedForegroundColor: selectedForegroundColor,
              hoverColor: hoverColor,
            ),
          ),
        ),
      ),
    ),
  );

  // 构建带分割线的菜单项列表。
  static List<Widget> _buildMenuItemsWithDividers({
    required List<RightClickMenuItem> menuItems,
    required AppTheme theme,
    required double panelWidth,
    required double menuWidth,
    Color? itemColor,
    Color? selectedColor,
    Color? selectedForegroundColor,
    Color? hoverColor,
  }) {
    List<Widget> widgets = [];
    final hasSubmenu = menuItems.any((item) => item.children.isNotEmpty);

    for (int i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      final isLast = i == menuItems.length - 1;
      final action = buildMenuItem(
        item: item,
        theme: theme,
        menuWidth: menuWidth,
        itemColor: itemColor,
        selectedColor: selectedColor,
        selectedForegroundColor: selectedForegroundColor,
        hoverColor: hoverColor,
      );

      // 添加菜单项
      widgets.add(
        // 悬停渐变与波纹只重绘当前项，避免快速切换时反复重绘整块浮层和阴影。
        RepaintBoundary(
          child: item.children.isNotEmpty
              ? _RightClickSubmenu(
                  key: item.key,
                  item: item,
                  theme: theme,
                  rowWidth: menuWidth,
                  parentWidth: panelWidth,
                  hoverColor: hoverColor,
                )
              : hasSubmenu
              ? Builder(
                  builder: (context) => MouseRegion(
                    onHover: (_) =>
                        MenuController.maybeOf(context)?.closeChildren(),
                    child: action,
                  ),
                )
              : action,
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
      decoration: BoxDecoration(color: theme.materialColors.outlineVariant),
    );
  }

  // 构建自定义菜单项。
  static Widget buildMenuItem({
    required RightClickMenuItem item,
    required AppTheme theme,
    required double menuWidth,
    Color? itemColor,
    Color? selectedColor,
    Color? selectedForegroundColor,
    Color? hoverColor,
  }) {
    return MenuItemSurface(
      key: item.key,
      theme: theme,
      isSelected: item.isSelected,
      disableWhenSelected: false,
      backgroundColor: itemColor ?? PopupMenuSurface.backgroundColorFor(theme),
      surfaceColor: itemColor ?? PopupMenuSurface.backgroundColorFor(theme),
      selectedColor: selectedColor ?? theme.secondaryTextSelectedColor,
      hoverColor: hoverColor ?? theme.basePrimary,
      foregroundColor: item.isSelected
          ? selectedForegroundColor ?? theme.materialColors.onPrimary
          : item.isEnabled
          ? theme.textColorSecondary
          : theme.textColorTertiary,
      hoverForegroundColor: theme.materialColors.onPrimary,
      onPressed: item.isEnabled ? item.onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: menuWidth,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: _itemPadding),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                size: _iconSize,
                fill: 1,
                grade: 200,
                opticalSize: 20,
                weight: 300,
              ),
              const SizedBox(width: _iconGap),
            ],
            Expanded(
              child: DefaultTextStyle.merge(
                style: _labelStyle(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: item.labelWidget ?? Text(item.label),
              ),
            ),
            if (item.isSelected) ...[
              const SizedBox(width: _iconGap),
              const Icon(Icons.check, size: _iconSize),
            ],
          ],
        ),
      ),
    );
  }
}

class _RightClickSubmenu extends StatefulWidget {
  const _RightClickSubmenu({
    super.key,
    required this.item,
    required this.theme,
    required this.rowWidth,
    required this.parentWidth,
    this.hoverColor,
  });

  final RightClickMenuItem item;
  final AppTheme theme;
  final double rowWidth;
  final double parentWidth;
  final Color? hoverColor;

  @override
  State<_RightClickSubmenu> createState() => _RightClickSubmenuState();
}

class _RightClickSubmenuState extends State<_RightClickSubmenu> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = widget.theme;
    bool highlighted(Set<WidgetState> states) =>
        _open || states.contains(WidgetState.hovered);
    final foreground = WidgetStateProperty.resolveWith(
      (states) => highlighted(states)
          ? theme.materialColors.onPrimary
          : theme.textColorSecondary,
    );
    return SizedBox(
      width: widget.rowWidth,
      height: 28,
      child: SubmenuButton(
        hoverOpenDelay: const Duration(milliseconds: 120),
        onOpen: () => setState(() => _open = true),
        onClose: () => setState(() => _open = false),
        clipBehavior: Clip.none,
        alignmentOffset: Offset(
          RightClickMenuBuilder._submenuGap +
              (widget.parentWidth - widget.rowWidth) / 2,
          -RightClickMenuBuilder._menuPadding,
        ),
        menuStyle: RightClickMenuBuilder._panelStyle,
        style: ButtonStyle(
          backgroundBuilder: (_, _, child) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _open ? () {} : null,
            child: child,
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: RightClickMenuBuilder._itemPadding,
            ),
          ),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: AlignmentDirectional.centerStart,
          textStyle: WidgetStatePropertyAll(
            RightClickMenuBuilder._labelStyle(item),
          ),
          foregroundColor: foreground,
          iconColor: foreground,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? null
                : Colors.transparent,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => highlighted(states)
                ? widget.hoverColor ?? theme.basePrimary
                : Colors.transparent,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        leadingIcon: item.icon == null
            ? null
            : Icon(
                item.icon,
                size: RightClickMenuBuilder._iconSize,
                fill: 1,
                grade: 200,
                opticalSize: 20,
                weight: 300,
              ),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(Icons.chevron_right, size: RightClickMenuBuilder._iconSize),
        ),
        menuChildren: [
          PopupMenuTransition(
            child: RightClickMenuBuilder.buildMenuPanel(
              menuItems: item.children,
              theme: theme,
              width: RightClickMenuBuilder._submenuWidth(
                context,
                item.children,
                widget.parentWidth,
                MediaQuery.sizeOf(context).width,
              ),
            ),
          ),
        ],
        child:
            item.labelWidget ??
            Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
