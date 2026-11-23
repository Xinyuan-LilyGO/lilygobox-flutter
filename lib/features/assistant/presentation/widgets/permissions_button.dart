/*
 * @Description: 提供主页 AI 权限入口及自定义批准展开面板。
 */

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_option.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/settings/compact_switch.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../settings/presentation/widgets/content_layout.dart';
import '../../domain/permissions.dart';
import '../../state/provider.dart';
import 'model_selector.dart';
import 'permission_labels.dart';

/// 权限按会话配置，批准一次只放行当前工具调用。
class AssistantPermissionsButton extends StatefulWidget {
  const AssistantPermissionsButton({
    super.key,
    required this.theme,
    required this.assistant,
    this.compact = false,
    this.fieldSurfaceColor,
  });
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final bool compact;

  static const compactWidth = 28.0;
  static const labelChromeWidth = 18.0;

  static String labelFor(AppLocalizations l10n, AiApprovalMode mode) =>
      switch (mode) {
        AiApprovalMode.onRequest => l10n.aiPermissionRequest,
        AiApprovalMode.automatic => l10n.aiPermissionAutomatic,
        AiApprovalMode.custom => l10n.aiPermissionCustom,
      };

  /// 创建等标准弹窗中使用紧凑字段按钮，下方左对齐展开。
  final Color? fieldSurfaceColor;

  @override
  State<AssistantPermissionsButton> createState() =>
      _AssistantPermissionsButtonState();
}

class _AssistantPermissionsButtonState
    extends State<AssistantPermissionsButton> {
  final _menu = MenuController();
  int _revision = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.assistant,
    builder: (context, _) => _buildButton(context),
  );

  Widget _buildButton(BuildContext context) {
    final theme = widget.theme;
    final assistant = widget.assistant;
    final compact = widget.compact;
    final field = widget.fieldSurfaceColor != null;
    final fieldColor = field
        ? theme.selectControlColorForSurface(widget.fieldSurfaceColor!)
        : null;

    final l10n = context.l10n;
    final mode = assistant.permissions.mode;
    final label = AssistantPermissionsButton.labelFor(l10n, mode);
    final (modeIcon, initialPage) = switch (mode) {
      AiApprovalMode.onRequest => (
        Symbols.front_hand_rounded,
        _PermissionsPage.modes,
      ),
      AiApprovalMode.automatic => (
        Symbols.verified_user_rounded,
        _PermissionsPage.automatic,
      ),
      AiApprovalMode.custom => (Symbols.tune_rounded, _PermissionsPage.custom),
    };
    return RawMenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _revision++),
      onClose: () {
        if (mounted) setState(() {});
      },
      overlayBuilder: (context, info) =>
          _buildPanel(context, info, initialPage, field: field),
      builder: (context, controller, _) => AppTooltip(
        message: '${context.l10n.aiPermissions} · $label',
        child: MenuItemSurface(
          key: const ValueKey('ai-permissions-button'),
          theme: theme,
          borderRadius: BorderRadius.circular(field ? 4 : 8),
          backgroundColor: fieldColor,
          surfaceColor: fieldColor,
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
                      key: const ValueKey('ai-permissions-button-arrow'),
                      turns: field
                          ? (controller.isOpen ? 0 : -.25)
                          : (controller.isOpen ? .5 : 0),
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

  Widget _buildPanel(
    BuildContext context,
    RawMenuOverlayInfo info,
    _PermissionsPage initialPage, {
    required bool field,
  }) {
    const inset = PopupMenuSurface.verticalInset;
    final gap = field ? PopupMenuSurface.fieldAnchorGap : 8.0;
    const preferredHeight = 240.0;
    final bounds =
        (const EdgeInsets.all(inset) +
                MediaQuery.paddingOf(context) +
                MediaQuery.viewInsetsOf(context))
            .deflateRect(Offset.zero & info.overlaySize);
    if (bounds.isEmpty) return const SizedBox.shrink();

    final anchor = info.anchorRect;
    final aboveEdge = (anchor.top - gap).clamp(bounds.top, bounds.bottom);
    final belowEdge = (anchor.bottom + gap).clamp(bounds.top, bounds.bottom);
    final above = aboveEdge - bounds.top;
    final below = bounds.bottom - belowEdge;
    final opensAbove = field
        ? below < preferredHeight && above > below
        : above >= preferredHeight || above >= below;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final contentWidth = (info.overlaySize.width - 64)
        .clamp(0.0, 320 * math.max(1.0, textScale))
        .toDouble();
    final width = math.min(bounds.width, contentWidth + 4);
    final left = (anchor.left + (field ? 0 : inset)).clamp(
      bounds.left,
      bounds.right - width,
    );
    return Positioned(
      left: left,
      width: width,
      top: opensAbove ? null : belowEdge,
      bottom: opensAbove ? info.overlaySize.height - aboveEdge : null,
      child: TapRegion(
        groupId: info.tapRegionGroupId,
        onTapOutside: (_) => _menu.close(),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) _menu.close();
            return KeyEventResult.handled;
          },
          child: Material(
            type: MaterialType.transparency,
            child: PopupMenuTransition(
              key: ValueKey(_revision),
              alignment: opensAbove ? Alignment.bottomLeft : Alignment.topLeft,
              child: PopupMenuSurface(
                key: const ValueKey('ai-permissions-menu-surface'),
                theme: widget.theme,
                padding: EdgeInsets.zero,
                child: _PermissionsPanel(
                  initialPage: initialPage,
                  theme: widget.theme,
                  assistant: widget.assistant,
                  tapRegionGroupId: info.tapRegionGroupId,
                  maxHeight: math.min(480.0, opensAbove ? above : below),
                  onClose: _menu.close,
                ),
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
    required this.initialPage,
    required this.theme,
    required this.assistant,
    required this.tapRegionGroupId,
    required this.maxHeight,
    required this.onClose,
  });
  final _PermissionsPage initialPage;
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final Object tapRegionGroupId;
  final double maxHeight;
  final VoidCallback onClose;

  @override
  State<_PermissionsPanel> createState() => _PermissionsPanelState();
}

enum _PermissionsPage { modes, automatic, custom }

class _PermissionsPanelState extends State<_PermissionsPanel> {
  final _scroll = ScrollController();
  final _foldersScroll = ScrollController();
  late _PermissionsPage _page = widget.initialPage;
  bool get _subpage => _page != _PermissionsPage.modes;
  bool _picking = false;

  void _update({
    AiApprovalMode? mode,
    bool? network,
    bool? execution,
    bool? commandNoApproval,
    bool? fullFiles,
    AiFileAccess? files,
    List<String>? folders,
    Map<String, AiFileAccess>? folderAccess,
  }) {
    final current = widget.assistant.permissions;
    widget.assistant.setPermissions(
      current.copyWith(
        mode: mode,
        network: network,
        execution: execution,
        commandNoApproval: commandNoApproval,
        fullFiles: fullFiles,
        files: files,
        folders: folders,
        folderAccess: folderAccess,
      ),
    );
  }

  String _fileAccessLabel(AiFileAccess access) => switch (access) {
    AiFileAccess.none => context.l10n.aiPermissionNone,
    AiFileAccess.readOnly => context.l10n.aiPermissionReadOnly,
    AiFileAccess.readWrite => context.l10n.aiPermissionReadWrite,
  };

  // 绿、橙、红依次表示请求批准、只读和读写。
  Color _fileAccessColor(AiFileAccess access) {
    final appTheme = widget.theme;
    return switch (access) {
      AiFileAccess.none => appTheme.adaptiveColor(
        dark: Colors.green.shade400,
        light: Colors.green.shade700,
      ),
      AiFileAccess.readOnly => appTheme.permissionWarningColor,
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

  void _showPage(_PermissionsPage page) {
    if (page == _PermissionsPage.automatic) {
      _update(mode: AiApprovalMode.automatic);
    }
    if (page == _PermissionsPage.custom) _update(mode: AiApprovalMode.custom);
    setState(() => _page = page);
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
    required String description,
    required bool selected,
    required VoidCallback onPressed,
    bool next = false,
  }) => buildPopupMenuOption(
    key: key,
    theme: widget.theme,
    leading: Icon(
      icon,
      size: 16,
      fill: icon == Symbols.front_hand_rounded ? 0 : 1,
    ),
    title: title,
    description: description,
    selected: selected,
    onPressed: onPressed,
    next: next,
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(title, style: AppDialogStyle.fieldTitleStyle(widget.theme)),
  );

  Future<void> _confirmSensitivePermission({required bool commands}) async {
    // 提示框可能关闭菜单，确认后通过预先捕获的 provider 更新当前权限。
    final assistant = widget.assistant;
    final theme = widget.theme;
    final l10n = context.l10n;
    final navigator = Navigator.of(context, rootNavigator: true);
    final actionKey = commands ? 'command-no-approval' : 'full-files';
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      builder: (dialogContext) => AppDialog(
        theme: theme,
        title: commands
            ? l10n.aiPermissionCommandNoApprovalWarningTitle
            : l10n.aiPermissionFullFilesWarningTitle,
        titleLeading: Icon(
          Symbols.warning_rounded,
          fill: 1,
          size: 22,
          color: theme.permissionWarningColor,
        ),
        constraints: const BoxConstraints(maxWidth: 480),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commands
                    ? l10n.aiPermissionCommandNoApprovalWarningDescription
                    : l10n.aiPermissionFullFilesWarningDescription,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textColorSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.aiPermissionWarningFooter,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: theme.textColorTertiary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppActionButton.dialog(
            key: ValueKey('cancel-enable-$actionKey'),
            theme: theme,
            label: l10n.settingsCancel,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppActionButton.dialog(
            key: ValueKey('confirm-enable-$actionKey'),
            theme: theme,
            label: l10n.aiPermissionWarningConfirm,
            primary: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !navigator.mounted) return;
    assistant.setPermissions(
      assistant.permissions.copyWith(
        commandNoApproval: commands ? true : null,
        fullFiles: commands ? null : true,
      ),
    );
  }

  Widget _permissionToggle({
    required String title,
    required String description,
    required String key,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool warning = false,
    double top = 16,
  }) {
    final theme = widget.theme;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppDialogStyle.fieldTitleStyle(theme).copyWith(
                      color: warning
                          ? theme.permissionWarningColor
                          : theme.textColorSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CompactSettingSwitch(
                  controlKey: ValueKey(key),
                  theme: theme,
                  surface: theme.popupSurfaceColor,
                  value: value,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: warning
                  ? theme.permissionWarningColor
                  : theme.textColorTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _capabilitySwitch(
    AiPermissionCategory category,
    AiPermissions permissions,
  ) => _permissionToggle(
    title: aiPermissionCategoryLabel(context.l10n, category),
    description: aiPermissionCategoryHelp(context.l10n, category),
    key: switch (category) {
      AiPermissionCategory.network => 'ai-permission-network',
      AiPermissionCategory.fullFiles => 'ai-permission-full-files',
      _ => 'ai-permission-${category.name}',
    },
    value: switch (category) {
      AiPermissionCategory.execution => permissions.execution,
      AiPermissionCategory.fullFiles => permissions.fullFiles,
      AiPermissionCategory.network => permissions.network,
    },
    warning: category == AiPermissionCategory.fullFiles,
    top: category == AiPermissionCategory.execution ? 0 : 16,
    onChanged: (enabled) {
      switch (category) {
        case AiPermissionCategory.execution:
          _update(execution: enabled);
        case AiPermissionCategory.fullFiles:
          if (enabled) {
            _confirmSensitivePermission(commands: false);
          } else {
            _update(fullFiles: false);
          }
        case AiPermissionCategory.network:
          _update(network: enabled);
      }
    },
  );

  Widget _commandNoApprovalSwitch(AiPermissions permissions) =>
      _permissionToggle(
        title: context.l10n.aiPermissionCommandNoApproval,
        description: context.l10n.aiPermissionCommandNoApprovalHelp,
        key: 'ai-permission-command-no-approval',
        value: permissions.commandNoApproval,
        warning: true,
        onChanged: (enabled) {
          if (enabled) {
            _confirmSensitivePermission(commands: true);
          } else {
            _update(commandNoApproval: false);
          }
        },
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.assistant,
    builder: (context, _) {
      final theme = widget.theme;
      final l10n = context.l10n;
      final permissions = widget.assistant.permissions;
      final approvalModel = widget.assistant.auxiliaryModels.approval;
      final descriptionStyle = TextStyle(
        fontSize: 11,
        color: theme.textColorTertiary,
        height: 1.4,
      );
      return ConstrainedBox(
        key: const ValueKey('ai-permissions-panel'),
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: PopupMenuPageTransition(
          child: Padding(
            key: ValueKey(_page),
            padding: _subpage
                ? const EdgeInsets.fromLTRB(8, 8, 4, 12)
                : const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      if (_subpage) ...[
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
                            onPressed: () => _showPage(_PermissionsPage.modes),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          switch (_page) {
                            _PermissionsPage.modes => l10n.aiPermissions,
                            _PermissionsPage.automatic =>
                              l10n.aiPermissionAutomatic,
                            _PermissionsPage.custom => l10n.aiPermissionCustom,
                          },
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
                  child: ScrollbarTheme(
                    data: ScrollbarTheme.of(context).copyWith(
                      crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset - 4,
                    ),
                    child: Scrollbar(
                      key: const ValueKey('ai-permissions-scrollbar'),
                      controller: _scroll,
                      notificationPredicate: (notification) =>
                          notification.depth == 0,
                      child: ScrollConfiguration(
                        behavior: const AppScrollBehavior(scrollbars: false),
                        child: SingleChildScrollView(
                          key: const ValueKey('ai-permissions-scroll'),
                          controller: _scroll,
                          padding: _subpage
                              ? const EdgeInsets.only(
                                  left: 4,
                                  right: popupMenuOptionsTrailingInset - 4,
                                )
                              : const EdgeInsets.only(
                                  right: popupMenuOptionsTrailingInset - 4,
                                ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_page == _PermissionsPage.modes) ...[
                                _option(
                                  key: const ValueKey(
                                    'ai-permission-mode-request',
                                  ),
                                  icon: Symbols.front_hand_rounded,
                                  title: l10n.aiPermissionRequest,
                                  description: l10n.aiPermissionRequestSummary,
                                  selected:
                                      permissions.mode ==
                                      AiApprovalMode.onRequest,
                                  onPressed: () {
                                    _update(mode: AiApprovalMode.onRequest);
                                    widget.onClose();
                                  },
                                ),
                                const SizedBox(height: popupMenuOptionSpacing),
                                _option(
                                  key: const ValueKey(
                                    'ai-permission-mode-automatic',
                                  ),
                                  icon: Symbols.verified_user_rounded,
                                  title: l10n.aiPermissionAutomatic,
                                  description:
                                      l10n.aiPermissionAutomaticSummary,
                                  selected:
                                      permissions.mode ==
                                      AiApprovalMode.automatic,
                                  onPressed: () =>
                                      _showPage(_PermissionsPage.automatic),
                                  next: true,
                                ),
                                const SizedBox(height: popupMenuOptionSpacing),
                                _option(
                                  key: const ValueKey(
                                    'ai-permission-mode-custom',
                                  ),
                                  icon: Symbols.tune_rounded,
                                  title: l10n.aiPermissionCustom,
                                  description: l10n.aiPermissionCustomSummary,
                                  selected:
                                      permissions.mode == AiApprovalMode.custom,
                                  onPressed: () =>
                                      _showPage(_PermissionsPage.custom),
                                  next: true,
                                ),
                              ] else if (_page ==
                                  _PermissionsPage.automatic) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: SettingsField(
                                    theme: theme,
                                    title: l10n.aiPermissionApprovalModel,
                                    description:
                                        l10n.aiPermissionApprovalModelHelp,
                                    trailing: Flexible(
                                      flex: 2,
                                      child: ModelSelector(
                                        key: const ValueKey(
                                          'ai-approval-model-select',
                                        ),
                                        theme: theme,
                                        assistant: widget.assistant,
                                        auxiliarySelection: approvalModel,
                                        wrapLabel: true,
                                        fieldSurfaceColor:
                                            theme.popupSurfaceColor,
                                        onAuxiliarySelected: widget
                                            .assistant
                                            .selectApprovalModel,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                for (final category
                                    in AiPermissionCategory.values) ...[
                                  _capabilitySwitch(category, permissions),
                                  if (category ==
                                          AiPermissionCategory.execution &&
                                      permissions.execution)
                                    _commandNoApprovalSwitch(permissions),
                                ],
                                if (!permissions.fullFiles) ...[
                                  _section(l10n.aiPermissionFiles),
                                  SettingSelect<AiFileAccess>(
                                    key: const ValueKey('ai-permission-files'),
                                    theme: theme,
                                    surfaceColor: theme.popupSurfaceColor,
                                    dropdownTapRegionGroupId:
                                        widget.tapRegionGroupId,
                                    value: permissions.files,
                                    items: _fileAccessItems(),
                                    onChanged: (value) {
                                      if (value != null) _update(files: value);
                                    },
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l10n.aiPermissionFolders,
                                            key: const ValueKey(
                                              'ai-permission-folders-label',
                                            ),
                                            style:
                                                AppDialogStyle.fieldTitleStyle(
                                                  theme,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        AppActionButton(
                                          key: const ValueKey(
                                            'ai-permission-add-folder',
                                          ),
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
                                          onPressed: _picking
                                              ? null
                                              : _addFolder,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    permissions.folders.isEmpty
                                        ? l10n.aiPermissionNoFolders
                                        : l10n.aiPermissionFoldersHelp,
                                    key: const ValueKey(
                                      'ai-permission-folders-help',
                                    ),
                                    style: descriptionStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  if (permissions.folders.isNotEmpty)
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 144,
                                      ),
                                      child: ScrollConfiguration(
                                        behavior: const AppScrollBehavior(
                                          scrollbars: false,
                                        ),
                                        child: ScrollbarTheme(
                                          data: ScrollbarTheme.of(context)
                                              .copyWith(
                                                crossAxisMargin:
                                                    AppScrollBehavior
                                                        .scrollbarEdgeInset,
                                              ),
                                          child: Scrollbar(
                                            key: const ValueKey(
                                              'ai-permission-folders-scrollbar',
                                            ),
                                            controller: _foldersScroll,
                                            notificationPredicate: (
                                              notification,
                                            ) => notification.depth == 0,
                                            child: SingleChildScrollView(
                                              key: const ValueKey(
                                                'ai-permission-folders-scroll',
                                              ),
                                              controller: _foldersScroll,
                                              primary: false,
                                              padding:
                                                  const EdgeInsetsDirectional.only(
                                                    end: 20,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (final folder
                                                      in permissions.folders)
                                                    Padding(
                                                      padding: EdgeInsets.zero,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Symbols
                                                                    .folder_rounded,
                                                                size: 16,
                                                                fill: 1,
                                                                color: theme
                                                                    .textColorSecondary,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Expanded(
                                                                child: AppTooltip(
                                                                  message:
                                                                      folder,
                                                                  child: Text(
                                                                    _folderName(
                                                                      folder,
                                                                    ),
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style:
                                                                        descriptionStyle,
                                                                  ),
                                                                ),
                                                              ),
                                                              SettingSelect<
                                                                AiFileAccess
                                                              >(
                                                                key: ValueKey(
                                                                  'ai-permission-folder-select-$folder',
                                                                ),
                                                                theme: theme,
                                                                surfaceColor: theme
                                                                    .popupSurfaceColor,
                                                                dropdownTapRegionGroupId:
                                                                    widget
                                                                        .tapRegionGroupId,
                                                                dropdownWidth:
                                                                    240 *
                                                                    MediaQuery.textScalerOf(
                                                                      context,
                                                                    ).scale(1),
                                                                value: permissions
                                                                    .accessForFolder(
                                                                      folder,
                                                                    ),
                                                                items:
                                                                    _fileAccessItems(),
                                                                onChanged: (value) {
                                                                  if (value ==
                                                                      null) {
                                                                    return;
                                                                  }
                                                                  _update(
                                                                    folderAccess: {
                                                                      ...widget
                                                                          .assistant
                                                                          .permissions
                                                                          .folderAccess,
                                                                      folder:
                                                                          value,
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
                                                                    onPressed:
                                                                        onPressed,
                                                                    isFocused:
                                                                        true,
                                                                    theme:
                                                                        theme,
                                                                    icon: Symbols
                                                                        .shield_rounded,
                                                                    iconColor: _fileAccessColor(
                                                                      permissions
                                                                          .accessForFolder(
                                                                            folder,
                                                                          ),
                                                                    ),
                                                                    backgroundColor:
                                                                        theme
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
                                                                          (
                                                                            item,
                                                                          ) =>
                                                                              item !=
                                                                              folder,
                                                                        )
                                                                        .toList(),
                                                                  ),
                                                                  isFocused:
                                                                      true,
                                                                  theme: theme,
                                                                  icon: Symbols
                                                                      .close_rounded,
                                                                  backgroundColor:
                                                                      theme
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
                                    ),
                                ],
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
