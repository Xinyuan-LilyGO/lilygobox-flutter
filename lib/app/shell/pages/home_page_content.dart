/*
 * @Description: 展示主页设备卡片、名称搜索、默认空状态与悬浮添加入口。
 * @Author: LILYGO_L
 * @Date: 2025-11-07 11:23:45
 * @LastEditTime: 2026-10-06 14:24:23
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/context_menu/text_selection_menu.dart';
import '../../../core/l10n/language_provider.dart';
import '../../../core/theme/provider.dart';
import '../../../core/widgets/action_button.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../features/devices/presentation/widgets/home_device_card.dart';
import '../../../features/devices/state/lan_connection.dart';
import '../../../features/devices/state/manager_provider.dart';
import '../../navigation/provider.dart';
import '../state/provider.dart';
import '../widgets/home_device_illustration.dart';

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  final _search = TextEditingController();
  final Set<String> _deletingDevices = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _addDevice() =>
      context.read<AppNavigationProvider>().setPage(AppPage.addDevice);

  void _openDevice(String id) {
    final index = context.read<DeviceManagerProvider>().addedDevices.indexOf(
      id,
    );
    if (index < 0) return;
    context.read<AppShellProvider>().updateSelectedIndex(index + 1);
    context.read<AppNavigationProvider>().goHome();
  }

  Future<void> _deleteDevice(String id) async {
    if (!_deletingDevices.add(id)) return;
    final manager = context.read<DeviceManagerProvider>();
    final session = context.read<LanConnection?>();
    final shell = context.read<AppShellProvider>();
    final l10n = context.l10n;
    setState(() {});
    bool deleted = false;
    bool attempted = false;
    try {
      final confirmed = await showAppConfirmation(
        context: context,
        theme: context.read<ThemeProvider>().themeData,
        actionKey: 'delete-device',
        title: l10n.deleteDeviceConfirmTitle,
        description: l10n.deleteDeviceConfirmDescription(
          manager.displayName(id),
        ),
        confirmLabel: l10n.delete,
      );
      // 取消或关闭弹窗时不触碰连接和凭据；页面退出后也不继续删除。
      if (!confirmed || !mounted || !manager.addedDevices.contains(id)) return;
      attempted = true;
      final saved = manager.lanDevice(id);
      final cleared = saved == null || await session?.forgetDevice(id) == true;
      if (cleared) {
        // 按设备标识保留其他页面的选择，避免删除前面的卡片后索引指向错设备。
        final selectedIndex = shell.selectedIndex;
        final before = manager.addedDevices;
        final selectedId = selectedIndex > 0 && selectedIndex <= before.length
            ? before[selectedIndex - 1]
            : null;
        deleted = await manager.removeDeviceAndSave(id);
        if (mounted && shell.selectedIndex == selectedIndex) {
          shell.updateSelectedIndex(
            selectedId == null
                ? 0
                : manager.addedDevices.indexOf(selectedId) + 1,
          );
        }
      }
    } catch (_) {
      deleted = false;
    } finally {
      _deletingDevices.remove(id);
      if (mounted) {
        setState(() {});
        if (attempted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deleted ? l10n.deleteDeviceSucceeded : l10n.deleteDeviceFailed,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().themeData;
    final devices = context.watch<DeviceManagerProvider>();
    final session = context.watch<LanConnection?>();
    final hasDevices = devices.addedDevices.isNotEmpty;
    final l10n = context.l10n;
    bool isConnected(String id) =>
        session?.device?.id == id && session?.connected == true;
    final query = _search.text.trim().toLowerCase();
    final visible = devices.addedDevices.where((id) {
      final matches =
          '${devices.displayName(id)} ${devices.lanDevice(id)?.model ?? id} $id ${devices.lanDevice(id)?.macAddress ?? ''}'
              .toLowerCase()
              .contains(query);
      return matches;
    }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
      child: ColoredBox(
        color: theme.secondary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = constraints.maxWidth < 520 ? 20.0 : 32.0;
            return Stack(
              children: [
                CustomScrollView(
                  key: const PageStorageKey('home-devices-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 24, inset, 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.home,
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                color: theme.textColorPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.homeDevicesSubtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.textColorTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!hasDevices)
                      SliverToBoxAdapter(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0, constraints.maxHeight - 90),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(inset, 24, inset, 110),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 380,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HomeDeviceIllustration(theme: theme),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.homeDevicesEmpty,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: theme.textColorPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.homeDevicesEmptyDescription,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                        color: theme.textColorTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 26),
                                    AppActionButton(
                                      theme: theme,
                                      label: l10n.addDevice,
                                      icon: Symbols.add_rounded,
                                      primary: true,
                                      onPressed: _addDevice,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: TextField(
                                  contextMenuBuilder:
                                      AppTextSelectionMenu.build,
                                  controller: _search,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textColorPrimary,
                                  ),
                                  cursorColor: theme.basePrimary,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: l10n.homeDeviceSearch,
                                    hintStyle: TextStyle(
                                      color: theme.textColorTertiary,
                                    ),
                                    filled: true,
                                    fillColor: theme.primary,
                                    hoverColor: Colors.transparent,
                                    prefixIcon: Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 6,
                                        top: 6,
                                        bottom: 6,
                                      ),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Icon(
                                          Symbols.search,
                                          size: 18,
                                          color: theme.textColorSecondary,
                                        ),
                                      ),
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 36,
                                    ),
                                    suffixIconConstraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    suffixIcon: _search.text.isEmpty
                                        ? null
                                        : Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: IconButton(
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 24,
                                                    height: 24,
                                                  ),
                                              padding: const EdgeInsets.all(4),
                                              style: IconButton.styleFrom(
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: const CircleBorder(),
                                              ),
                                              tooltip: l10n.homeClearSearch,
                                              onPressed: () =>
                                                  setState(_search.clear),
                                              icon: Icon(
                                                Symbols.close,
                                                size: 14,
                                                color: theme.textColorSecondary,
                                              ),
                                            ),
                                          ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide(
                                        color: theme.basePrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(inset, 28, inset, 104),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.homeDevicesNoResults,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.textColorSecondary,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  AppActionButton(
                                    theme: theme,
                                    label: l10n.homeClearSearch,
                                    onPressed: () => setState(_search.clear),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(inset, 0, inset, 104),
                          sliver: SliverToBoxAdapter(
                            child: LayoutBuilder(
                              builder: (context, grid) {
                                final scale =
                                    MediaQuery.textScalerOf(context).scale(14) /
                                    14;
                                // 固定卡片宽度，侧栏拖动只触发换行；窄屏时才收窄。
                                final cardWidth = math.min(
                                  280.0 * math.max(1.0, scale),
                                  grid.maxWidth,
                                );
                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    for (final id in visible)
                                      SizedBox(
                                        key: ValueKey(
                                          'home-device-container-$id',
                                        ),
                                        width: cardWidth,
                                        child: HomeDeviceCard(
                                          key: ValueKey('home-device-$id'),
                                          name: devices.displayName(id),
                                          model:
                                              devices.lanDevice(id)?.model ??
                                              id,
                                          connected: isConnected(id),
                                          macAddress: devices
                                              .lanDevice(id)
                                              ?.macAddress,
                                          usesWifi:
                                              devices.lanDevice(id) != null,
                                          connecting:
                                              session?.device?.id == id &&
                                              session?.busy == true,
                                          onPressed: () => _openDevice(id),
                                          onDelete:
                                              _deletingDevices.contains(id)
                                              ? null
                                              : () => unawaited(
                                                  _deleteDevice(id),
                                                ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                if (hasDevices)
                  Positioned(
                    right: inset,
                    bottom: 24,
                    child: SafeArea(
                      top: false,
                      left: false,
                      child: AppTooltip(
                        message: l10n.addDevice,
                        child: Semantics(
                          label: l10n.addDevice,
                          child: SizedBox(
                            key: const ValueKey('home-add-device'),
                            width: 48,
                            height: 48,
                            child: AppActionButton(
                              theme: theme,
                              label: '',
                              icon: Symbols.add_rounded,
                              iconSize: 26,
                              primary: true,
                              padding: EdgeInsets.zero,
                              borderRadius: BorderRadius.circular(24),
                              onPressed: _addDevice,
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
      ),
    );
  }
}
