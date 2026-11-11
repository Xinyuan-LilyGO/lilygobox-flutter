/*
 * @Description: 提供主页 AI 权限入口及自定义批准展开面板。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-11 21:22:31
 */

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../domain/permissions.dart';
import '../../state/provider.dart';

/// 权限按会话配置，批准一次只放行当前工具调用。
class AssistantPermissionsButton extends StatefulWidget {
  const AssistantPermissionsButton({
    super.key,
    required this.theme,
    required this.assistant,
    this.compact = false,
  });
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final bool compact;

  @override
  State<AssistantPermissionsButton> createState() =>
      _AssistantPermissionsButtonState();
}

class _AssistantPermissionsButtonState
    extends State<AssistantPermissionsButton> {
  final _menu = MenuController();
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final assistant = widget.assistant;
    final compact = widget.compact;

    final label = assistant.permissions.mode == AiApprovalMode.onRequest
        ? context.l10n.aiPermissionRequest
        : context.l10n.aiPermissionCustom;
    final modeIcon = assistant.permissions.mode == AiApprovalMode.onRequest
        ? Symbols.front_hand_rounded
        : Symbols.tune_rounded;
    final available = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = math
        .min(math.max(0, available.width - 64), 320 * math.max(1, textScale))
        .toDouble();
    return MenuAnchor(
      controller: _menu,
      clipBehavior: Clip.none,
      crossAxisUnconstrained: true,
      alignmentOffset: const Offset(0, -8),
      style: const MenuStyle(
        alignment: AlignmentDirectional.topStart,
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      onOpen: () => setState(() => _revision++),
      onClose: () {
        if (mounted) setState(() {});
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: PopupMenuTransition(
            key: ValueKey(_revision),
            alignment: Alignment.bottomLeft,
            child: PopupMenuSurface(
              theme: theme,
              borderRadius: BorderRadius.circular(8),
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
              child: SizedBox(
                width: width,
                child: _PermissionsPanel(
                  key: ValueKey(_revision),
                  theme: theme,
                  assistant: assistant,
                  menuController: _menu,
                  maxHeight: (available.height - 100).clamp(0.0, 480.0),
                  onClose: _menu.close,
                ),
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => AppTooltip(
        message: '${context.l10n.aiPermissions} · $label',
        child: MenuItemSurface(
          key: const ValueKey('ai-permissions-button'),
          theme: theme,
          borderRadius: BorderRadius.circular(8),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(modeIcon, size: 16, color: theme.textColorSecondary),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorSecondary,
                    ),
                  ),
                  AnimatedRotation(
                    turns: controller.isOpen ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : PopupMenuTransition.duration,
                    child: Icon(
                      Symbols.expand_more_rounded,
                      size: 14,
                      color: theme.textColorSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 模式选择和自定义配置共用同一个菜单，避免独立浮层被判定为外部点击。
class _PermissionsPanel extends StatefulWidget {
  const _PermissionsPanel({
    super.key,
    required this.theme,
    required this.assistant,
    required this.menuController,
    required this.maxHeight,
    required this.onClose,
  });
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final MenuController menuController;
  final double maxHeight;
  final VoidCallback onClose;

  @override
  State<_PermissionsPanel> createState() => _PermissionsPanelState();
}

class _PermissionsPanelState extends State<_PermissionsPanel> {
  final _scroll = ScrollController();
  bool _custom = false;
  bool _picking = false;

  void _update({
    AiApprovalMode? mode,
    bool? network,
    AiFileAccess? files,
    List<String>? folders,
  }) {
    final current = widget.assistant.permissions;
    widget.assistant.setPermissions(
      AiPermissions(
        mode: mode ?? current.mode,
        network: network ?? current.network,
        files: files ?? current.files,
        folders: folders ?? current.folders,
      ),
    );
  }

  void _showCustom() {
    _update(mode: AiApprovalMode.custom);
    setState(() => _custom = true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _addFolder() async {
    setState(() => _picking = true);
    try {
      final folder = await getDirectoryPath();
      if (mounted &&
          folder != null &&
          !widget.assistant.permissions.folders.contains(folder)) {
        _update(folders: [...widget.assistant.permissions.folders, folder]);
      }
    } catch (_) {
      if (mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiPermissionFolderFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _option({
    required Key key,
    required IconData icon,
    required String title,
    String? description,
    required bool selected,
    required VoidCallback onPressed,
    bool next = false,
  }) {
    final theme = widget.theme;
    final background = theme.popupSurfaceColor;
    return MenuItemSurface(
      key: key,
      theme: theme,
      isSelected: selected,
      disableWhenSelected: false,
      backgroundColor: background,
      selectedColor: theme.primaryTextHoverColor,
      hoverColor: theme.basePrimary,
      foregroundColor: selected
          ? theme.type == ThemeType.light
                ? Colors.black
                : theme.materialColors.onPrimary
          : theme.textColorSecondary,
      hoverForegroundColor: theme.materialColors.onPrimary,
      borderRadius: BorderRadius.circular(6),
      onPressed: onPressed,
      child: Builder(
        builder: (context) {
          final foreground = DefaultTextStyle.of(context).style.color;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: description == null ? 13 : 12,
                            color: foreground,
                            height: 1.4,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 11,
                              color: foreground,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 17,
                    child: selected
                        ? const Icon(Symbols.check_rounded, size: 17)
                        : null,
                  ),
                  if (description != null) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 16,
                      child: next
                          ? const Icon(Symbols.chevron_right_rounded, size: 16)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      title,
      style: TextStyle(fontSize: 12, color: widget.theme.textColorSecondary),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.assistant,
    builder: (context, _) {
      final theme = widget.theme;
      final l10n = context.l10n;
      final permissions = widget.assistant.permissions;
      final descriptionStyle = TextStyle(
        fontSize: 11,
        color: theme.textColorTertiary,
        height: 1.4,
      );
      return ConstrainedBox(
        key: const ValueKey('ai-permissions-panel'),
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: PopupMenuPageTransition(
          child: Column(
            key: ValueKey(_custom),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (_custom) ...[
                      AppTooltip(
                        message: l10n.back,
                        child: TitleBarIconButton(
                          key: const ValueKey('ai-permissions-back'),
                          theme: theme,
                          isFocused: true,
                          icon: Symbols.arrow_back_rounded,
                          size: 26,
                          iconSize: 16,
                          backgroundColor: theme.popupSurfaceColor,
                          onPressed: () {
                            setState(() => _custom = false);
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _custom ? l10n.aiPermissionCustom : l10n.aiPermissions,
                        key: const ValueKey('ai-permissions-heading'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textColorPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_custom) ...[
                        _option(
                          key: const ValueKey('ai-permission-mode-request'),
                          icon: Symbols.front_hand_rounded,
                          title: l10n.aiPermissionRequest,
                          description: l10n.aiPermissionRequestSummary,
                          selected:
                              permissions.mode == AiApprovalMode.onRequest,
                          onPressed: () {
                            _update(mode: AiApprovalMode.onRequest);
                            widget.onClose();
                          },
                        ),
                        const SizedBox(height: 8),
                        _option(
                          key: const ValueKey('ai-permission-mode-custom'),
                          icon: Symbols.tune_rounded,
                          title: l10n.aiPermissionCustom,
                          description: l10n.aiPermissionCustomSummary,
                          selected: permissions.mode == AiApprovalMode.custom,
                          onPressed: _showCustom,
                          next: true,
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.aiPermissionNetwork,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textColorSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 44,
                              height: 28,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: Switch(
                                  key: const ValueKey('ai-permission-network'),
                                  value: permissions.network,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  activeTrackColor: theme.basePrimary,
                                  inactiveTrackColor: theme
                                      .selectControlColorForSurface(
                                        theme.popupSurfaceColor,
                                      ),
                                  activeThumbColor:
                                      theme.materialColors.onPrimary,
                                  inactiveThumbColor:
                                      theme.materialColors.onPrimary,
                                  trackOutlineColor:
                                      const WidgetStatePropertyAll(
                                        Colors.transparent,
                                      ),
                                  onChanged: (value) => _update(network: value),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _section(l10n.aiPermissionFiles),
                        SettingSelect<AiFileAccess>(
                          key: const ValueKey('ai-permission-files'),
                          theme: theme,
                          surfaceColor: theme.popupSurfaceColor,
                          dropdownTapRegionGroupId: widget.menuController,
                          value: permissions.files,
                          items: [
                            DropdownMenuItem(
                              value: AiFileAccess.none,
                              child: Text(l10n.aiPermissionNone),
                            ),
                            DropdownMenuItem(
                              value: AiFileAccess.readOnly,
                              child: Text(l10n.aiPermissionReadOnly),
                            ),
                            DropdownMenuItem(
                              value: AiFileAccess.readWrite,
                              child: Text(l10n.aiPermissionReadWrite),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) _update(files: value);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 4),
                          child: Text(
                            l10n.aiPermissionFolders,
                            key: const ValueKey('ai-permission-folders-label'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorSecondary,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                permissions.folders.isEmpty
                                    ? l10n.aiPermissionNoFolders
                                    : l10n.aiPermissionFoldersHelp,
                                key: const ValueKey(
                                  'ai-permission-folders-help',
                                ),
                                style: descriptionStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppActionButton(
                              key: const ValueKey('ai-permission-add-folder'),
                              theme: theme,
                              label: l10n.aiPermissionAddFolder,
                              icon: Symbols.add_rounded,
                              iconSize: 16,
                              iconSpacing: 6,
                              surfaceColor: theme.popupSurfaceColor,
                              backgroundColor: Color.lerp(
                                theme.popupSurfaceColor,
                                theme.textColorPrimary,
                                .06,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              onPressed: _picking ? null : _addFolder,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final folder in permissions.folders)
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Icon(
                                  Symbols.folder_rounded,
                                  size: 16,
                                  color: theme.textColorSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppTooltip(
                                    message: folder,
                                    child: Text(
                                      folder,
                                      overflow: TextOverflow.ellipsis,
                                      style: descriptionStyle,
                                    ),
                                  ),
                                ),
                                AppTooltip(
                                  message: l10n.aiPermissionRemoveFolder,
                                  child: TitleBarIconButton(
                                    onPressed: () => _update(
                                      folders: permissions.folders
                                          .where((item) => item != folder)
                                          .toList(),
                                    ),
                                    isFocused: true,
                                    theme: theme,
                                    icon: Symbols.close_rounded,
                                    backgroundColor: theme.popupSurfaceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            l10n.aiPermissionSessionHelp,
                            style: descriptionStyle,
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
      );
    },
  );
}
