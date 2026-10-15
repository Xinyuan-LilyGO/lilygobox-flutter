/*
 * @Description: 统一设备连接帮助入口，桌面显示侧边面板，窄屏显示底部面板。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 18:00:00
 * @LastEditTime: 2026-10-07 18:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/provider.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import 'device_menu_actions.dart';

class DeviceHelpMenu extends StatefulWidget {
  const DeviceHelpMenu({super.key, this.deviceId});

  final String? deviceId;

  @override
  State<DeviceHelpMenu> createState() => _DeviceHelpMenuState();
}

class _DeviceHelpMenuState extends State<DeviceHelpMenu> {
  final _menu = RightClickMenuController();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      controller: _menu,
      theme: theme,
      alignmentOffset: const Offset(0, 4),
      menuItems: [
        if (widget.deviceId case final id?)
          deviceConnectionMenuItem(context, id, _menu.close),
        RightClickMenuItem(
          key: const ValueKey('open-device-help'),
          label: context.l10n.deviceConnectionHelp,
          icon: Symbols.help,
          showDivider: widget.deviceId != null,
          onTap: () {
            _menu.close();
            showDeviceConnectionHelp(context);
          },
        ),
        if (widget.deviceId case final id?)
          RightClickMenuItem(
            label: context.l10n.deleteDevice,
            icon: Symbols.delete_rounded,
            onTap: () {
              _menu.close();
              deleteDeviceFromDetail(context, id);
            },
          ),
      ],
      child: AppTooltip(
        message: context.l10n.moreActions,
        verticalOffset: 16,
        child: Semantics(
          label: context.l10n.moreActions,
          button: true,
          child: TitleBarIconButton(
            key: const ValueKey('device-help-menu'),
            theme: theme,
            backgroundColor: theme.primary,
            isFocused: true,
            icon: Symbols.more_horiz,
            size: 28,
            iconSize: 20,
            onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
          ),
        ),
      ),
    );
  }
}

/// 展示按需帮助；复用内容区 Navigator，遮罩不会覆盖系统标题栏。
Future<void> showDeviceConnectionHelp(BuildContext context) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: .24),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _ConnectionHelpPanel(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final curve = animation.drive(
              CurveTween(curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: narrow ? const Offset(0, .12) : const Offset(.12, 0),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              ),
            );
          },
        );
      },
    );

class _ConnectionHelpPanel extends StatelessWidget {
  const _ConnectionHelpPanel();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final l10n = context.l10n;
    final sections = [
      (l10n.deviceHelpPreparation, l10n.deviceHelpPreparationDescription),
      (l10n.deviceHelpNetwork, l10n.deviceHelpNetworkDescription),
      (l10n.deviceHelpApproval, l10n.deviceHelpApprovalDescription),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context),
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(narrow ? 12 : 16),
                child: Align(
                  alignment: narrow
                      ? Alignment.bottomCenter
                      : Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: narrow ? 560 : 400),
                    child: FractionallySizedBox(
                      heightFactor: narrow ? .8 : 1,
                      child: Material(
                        key: const ValueKey('device-help-panel'),
                        color: theme.primary,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                22,
                                20,
                                16,
                                16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.deviceConnectionHelp,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: theme.textColorPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  AppTooltip(
                                    message: l10n.closeHelp,
                                    verticalOffset: 16,
                                    child: Semantics(
                                      label: l10n.closeHelp,
                                      button: true,
                                      child: TitleBarIconButton(
                                        key: const ValueKey(
                                          'close-device-help',
                                        ),
                                        theme: theme,
                                        surfaceColor: theme.primary,
                                        isFocused: true,
                                        icon: Symbols.close,
                                        size: 28,
                                        iconSize: 18,
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  6,
                                  22,
                                  24,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < sections.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(height: 24),
                                      Text(
                                        sections[i].$1,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: theme.textColorPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        sections[i].$2,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          color: theme.textColorTertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
