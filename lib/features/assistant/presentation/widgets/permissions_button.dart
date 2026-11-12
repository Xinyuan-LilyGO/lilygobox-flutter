/*
 * @Description: 提供主页 AI 权限入口及自定义批准展开面板。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 16:26:54
 * @LastEditTime: 2026-11-12 14:23:39
 */

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
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
              padding: const EdgeInsets.fromLTRB(8, 8, 6, 12),
              child: SizedBox(
                width: width + 4,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    modeIcon,
                    size: 16,
                    fill: modeIcon == Symbols.front_hand_rounded ? 0 : 1,
                    color: theme.textColorSecondary,
                  ),
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
  final _foldersScroll = ScrollController();
  bool _custom = false;
  bool _picking = false;

  void _update({
    AiApprovalMode? mode,
    bool? network,
    AiFileAccess? files,
    List<String>? folders,
    Map<String, AiFileAccess>? folderAccess,
  }) {
    final current = widget.assistant.permissions;
    widget.assistant.setPermissions(
      AiPermissions(
        mode: mode ?? current.mode,
        network: network ?? current.network,
        files: files ?? current.files,
        folders: folders ?? current.folders,
        folderAccess: folderAccess ?? current.folderAccess,
      ),
    );
  }

  String _fileAccessLabel(AiFileAccess access) => switch (access) {
    AiFileAccess.none => context.l10n.aiPermissionNone,
    AiFileAccess.readOnly => context.l10n.aiPermissionReadOnly,
    AiFileAccess.readWrite => context.l10n.aiPermissionReadWrite,
  };

  // 颜色表示自动授权范围，绿、黄、红依次对应请求批准、只读和读写。
  Color _fileAccessColor(AiFileAccess access) {
    final appTheme = widget.theme;
    return switch (access) {
      AiFileAccess.none => appTheme.adaptiveColor(
        dark: Colors.green.shade400,
        light: Colors.green.shade700,
      ),
      AiFileAccess.readOnly => appTheme.adaptiveColor(
        dark: Colors.amber.shade500,
        light: Colors.amber.shade600,
      ),
      AiFileAccess.readWrite => appTheme.materialColors.error,
    };
  }

  String _folderName(String folder) {
    final segments = Uri.file(
      folder,
      windows: defaultTargetPlatform == TargetPlatform.windows,
    ).pathSegments.where((part) => part.isNotEmpty);
    return segments.isEmpty ? folder : segments.last;
  }

  List<DropdownMenuItem<AiFileAccess>> _fileAccessItems() => [
    for (final access in AiFileAccess.values)
      DropdownMenuItem(
        value: access,
        child: Row(
          children: [
            Icon(
              Symbols.shield_rounded,
              size: 16,
              fill: 1,
              color: _fileAccessColor(access),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(_fileAccessLabel(access))),
          ],
        ),
      ),
  ];

  void _showCustom() {
    _update(mode: AiApprovalMode.custom);
    setState(() => _custom = true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _addFolder() async {
    setState(() => _picking = true);
    try {
      final selected = await getDirectoryPaths();
      if (!mounted) return;
      final folders = [...widget.assistant.permissions.folders];
      final known = folders
          .map(
            (folder) => defaultTargetPlatform == TargetPlatform.windows
                ? folder.replaceAll('\\', '/').toLowerCase()
                : folder,
          )
          .toSet();
      for (final folder in selected.whereType<String>()) {
        final key = defaultTargetPlatform == TargetPlatform.windows
            ? folder.replaceAll('\\', '/').toLowerCase()
            : folder;
        if (folder.isNotEmpty && known.add(key)) folders.add(folder);
      }
      if (folders.length != widget.assistant.permissions.folders.length) {
        _update(folders: folders);
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
    _foldersScroll.dispose();
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
          final foreground =
              DefaultTextStyle.of(context).style.color ??
              theme.textColorSecondary;
          final normal = theme.textColorSecondary;
          final highlighted = theme.materialColors.onPrimary;
          double distance(Color a, Color b) =>
              math.pow(a.r - b.r, 2).toDouble() +
              math.pow(a.g - b.g, 2).toDouble() +
              math.pow(a.b - b.b, 2).toDouble();
          // 沿用公共菜单的前景渐变进度，让二级说明同步切换浅色。
          final total = distance(normal, highlighted);
          final progress = total == 0
              ? 0.0
              : math.sqrt(distance(normal, foreground) / total).clamp(0.0, 1.0);
          final descriptionColor = Color.lerp(
            theme.textColorTertiary,
            highlighted,
            progress,
          );
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    fill: icon == Symbols.front_hand_rounded ? 0 : 1,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 12, color: foreground),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 11,
                              color: descriptionColor,
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
                  if (next) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 17,
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

  Widget _section(String title, {String? description}) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: widget.theme.textColorSecondary,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: widget.theme.textColorTertiary,
            ),
          ),
        ],
      ],
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
                padding: EdgeInsets.only(left: _custom ? 0 : 4, bottom: 8),
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
                  padding: const EdgeInsets.only(left: 4, right: 6),
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
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l10n.aiPermissionNetworkHelp,
                            style: descriptionStyle,
                          ),
                        ),
                        _section(
                          l10n.aiPermissionFiles,
                          description: l10n.aiPermissionDefaultFoldersHelp,
                        ),
                        SettingSelect<AiFileAccess>(
                          key: const ValueKey('ai-permission-files'),
                          theme: theme,
                          surfaceColor: theme.popupSurfaceColor,
                          dropdownTapRegionGroupId: widget.menuController,
                          value: permissions.files,
                          items: _fileAccessItems(),
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
                                horizontal: 8,
                                vertical: 7,
                              ),
                              onPressed: _picking ? null : _addFolder,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (permissions.folders.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 144),
                            child: ScrollConfiguration(
                              behavior: const AppScrollBehavior(
                                scrollbars: false,
                              ),
                              child: Scrollbar(
                                key: const ValueKey(
                                  'ai-permission-folders-scrollbar',
                                ),
                                controller: _foldersScroll,
                                notificationPredicate: (notification) =>
                                    notification.depth == 0,
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'ai-permission-folders-scroll',
                                  ),
                                  controller: _foldersScroll,
                                  primary: false,
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 20,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final folder in permissions.folders)
                                        Padding(
                                          padding: EdgeInsets.zero,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Symbols.folder_rounded,
                                                    size: 16,
                                                    fill: 1,
                                                    color: theme
                                                        .textColorSecondary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: AppTooltip(
                                                      message: folder,
                                                      child: Text(
                                                        _folderName(folder),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: descriptionStyle,
                                                      ),
                                                    ),
                                                  ),
                                                  SettingSelect<AiFileAccess>(
                                                    key: ValueKey(
                                                      'ai-permission-folder-select-$folder',
                                                    ),
                                                    theme: theme,
                                                    surfaceColor:
                                                        theme.popupSurfaceColor,
                                                    dropdownTapRegionGroupId:
                                                        widget.menuController,
                                                    dropdownWidth:
                                                        240 *
                                                        MediaQuery.textScalerOf(
                                                          context,
                                                        ).scale(1),
                                                    value: permissions
                                                        .accessForFolder(
                                                          folder,
                                                        ),
                                                    items: _fileAccessItems(),
                                                    onChanged: (value) {
                                                      if (value == null) {
                                                        return;
                                                      }
                                                      _update(
                                                        folderAccess: {
                                                          ...widget
                                                              .assistant
                                                              .permissions
                                                              .folderAccess,
                                                          folder: value,
                                                        },
                                                      );
                                                    },
                                                    triggerBuilder: (context, onPressed) => AppTooltip(
                                                      message: _fileAccessLabel(
                                                        permissions
                                                            .accessForFolder(
                                                              folder,
                                                            ),
                                                      ),
                                                      child: TitleBarIconButton(
                                                        key: ValueKey(
                                                          'ai-permission-folder-access-$folder',
                                                        ),
                                                        size: 22,
                                                        onPressed: onPressed,
                                                        isFocused: true,
                                                        theme: theme,
                                                        icon: Symbols
                                                            .shield_rounded,
                                                        iconColor:
                                                            _fileAccessColor(
                                                              permissions
                                                                  .accessForFolder(
                                                                    folder,
                                                                  ),
                                                            ),
                                                        backgroundColor: theme
                                                            .popupSurfaceColor,
                                                      ),
                                                    ),
                                                  ),
                                                  AppTooltip(
                                                    message: l10n
                                                        .aiPermissionRemoveFolder,
                                                    child: TitleBarIconButton(
                                                      size: 22,
                                                      onPressed: () => _update(
                                                        folders: permissions
                                                            .folders
                                                            .where(
                                                              (item) =>
                                                                  item !=
                                                                  folder,
                                                            )
                                                            .toList(),
                                                      ),
                                                      isFocused: true,
                                                      theme: theme,
                                                      icon:
                                                          Symbols.close_rounded,
                                                      backgroundColor: theme
                                                          .popupSurfaceColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
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
