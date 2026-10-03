/*
 * @Description: 提供添加设备页面的调试状态选择菜单与退出预览入口。
 * @Author: LILYGO_L
 * @Date: 2026-10-02 14:19:09
 * @LastEditTime: 2026-10-03 18:10:36
 * @License: GPL 3.0
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../state/discovery_controller.dart';

class DiscoveryPreviewMenu extends StatefulWidget {
  const DiscoveryPreviewMenu({
    super.key,
    required this.theme,
    required this.selectedPhase,
    required this.onSelected,
    required this.compact,
  });

  final AppTheme theme;
  final DiscoveryPhase? selectedPhase;
  final ValueChanged<DiscoveryPhase?> onSelected;
  final bool compact;

  @override
  State<DiscoveryPreviewMenu> createState() => _DiscoveryPreviewMenuState();
}

class _DiscoveryPreviewMenuState extends State<DiscoveryPreviewMenu> {
  final controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final selectedPhase = widget.selectedPhase;
    final onSelected = widget.onSelected;
    final compact = widget.compact;
    if (!kDebugMode) return const SizedBox.shrink();
    final l10n = context.l10n;
    final labels = {
      DiscoveryPhase.searching: l10n.searchingDevices,
      DiscoveryPhase.found: l10n.discoveredDevices,
      DiscoveryPhase.empty: l10n.discoveryEmpty,
      DiscoveryPhase.connecting: l10n.deviceConnecting,
      DiscoveryPhase.connectionFailed: l10n.deviceConnectionFailed,
      DiscoveryPhase.connected: l10n.deviceConnected,
      DiscoveryPhase.failed: l10n.discoveryFailed,
      DiscoveryPhase.unavailable: l10n.discoveryUnavailable,
    };
    final background = PopupMenuSurface.backgroundColorFor(theme);
    Widget item(DiscoveryPhase? phase, String label) => SizedBox(
      width: 240,
      child: MenuItemSurface(
        key: ValueKey('preview-${phase?.name ?? 'exit'}'),
        theme: theme,
        backgroundColor: background,
        hoverColor: theme.adaptiveColor(
          dark: theme.secondaryTextHoverColorAlt,
          light: theme.primaryTextHoverColor,
        ),
        borderRadius: BorderRadius.circular(6),
        onPressed: () {
          controller.close();
          onSelected(phase);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: theme.textColorPrimary),
                ),
              ),
              if (phase != null && phase == selectedPhase) ...[
                const SizedBox(width: 8),
                Icon(
                  Symbols.check_rounded,
                  size: 16,
                  color: theme.baseTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return MenuAnchor(
      controller: controller,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(background),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      menuChildren: [
        for (final entry in labels.entries) item(entry.key, entry.value),
        if (selectedPhase != null) item(null, l10n.exitStatePreview),
      ],
      builder: (context, menu, child) => AppTooltip(
        message: l10n.statePreview,
        child: Semantics(
          label: compact ? l10n.statePreview : null,
          button: true,
          child: AppActionButton(
            key: const ValueKey('discovery-preview-menu'),
            theme: theme,
            label: compact ? '' : l10n.statePreview,
            icon: Symbols.science_rounded,
            iconSize: 16,
            iconSpacing: 6,
            fontSize: 12,
            padding: const EdgeInsets.all(6),
            borderRadius: BorderRadius.circular(8),
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      ),
    );
  }
}
