import 'package:flutter/gestures.dart' show kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_option.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/settings/compact_switch.dart';
import '../../../../core/widgets/settings/search_field.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../domain/roleplay_card.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/provider.dart';

const _noRoleplayCardIcon = Symbols.block_rounded;

class RoleplayMenuButton extends StatefulWidget {
  const RoleplayMenuButton({
    super.key,
    required this.theme,
    required this.assistant,
    required this.compact,
    required this.onChooseOpening,
  });

  final AppTheme theme;
  final AiAssistantProvider assistant;
  final bool compact;
  final Future<void> Function(AiRoleplayBinding) onChooseOpening;

  static const labelChromeWidth = 18.0;

  static double compactWidth(AiRoleplayBinding? binding) =>
      binding?.card.avatar == null ? 28 : 30;

  static String labelFor(AppLocalizations l10n, AiRoleplayBinding? binding) =>
      binding?.card.name ?? l10n.aiRoleplayCard;

  @override
  State<RoleplayMenuButton> createState() => _RoleplayMenuButtonState();
}

class _RoleplayMenuButtonState extends State<RoleplayMenuButton> {
  Future<void> _editSettings(
    BuildContext context,
    AiRoleplayBinding binding,
  ) async {
    final assistant = widget.assistant;
    final updated = await showDialog<AiRoleplayBinding>(
      context: context,
      builder: (_) =>
          RoleplayCardOptionsDialog(binding: binding, theme: widget.theme),
    );
    if (mounted && identical(assistant, widget.assistant) && updated != null) {
      assistant.updateRoleplayOptions(binding, updated);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.assistant,
    builder: (context, _) => _buildMenu(context),
  );

  Widget _buildMenu(BuildContext context) {
    final workspaces = context.watch<AiWorkspaceProvider>();
    final l10n = context.l10n;
    final theme = widget.theme;
    final assistant = widget.assistant;
    final binding = assistant.roleplayBinding;
    final enabled = assistant.roleplayEnabled;
    final label = RoleplayMenuButton.labelFor(l10n, binding);
    final status = enabled
        ? l10n.aiRoleplayCardActive
        : l10n.aiRoleplayCardPaused;
    final tooltip = binding == null
        ? l10n.aiRoleplayCard
        : '${l10n.aiRoleplayCard} · $label';
    return RoleplayTemplateMenu(
      theme: theme,
      binding: binding,
      templates: workspaces.roleplayTemplates,
      onSelected: (template) {
        if (template != null) {
          assistant.bindRoleplay(template);
        } else {
          assistant.removeRoleplay();
        }
      },
      onSettings: (binding) => _editSettings(context, binding),
      onChooseOpening: assistant.canChooseRoleplayOpening
          ? widget.onChooseOpening
          : null,
      detailControls: MergeSemantics(
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                l10n.aiRoleplayEnableCard,
                style: AppDialogStyle.fieldTitleStyle(theme),
              ),
            ),
            CompactSettingSwitch(
              controlKey: const ValueKey('roleplay-menu-toggle'),
              theme: theme,
              surface: PopupMenuSurface.backgroundColorFor(theme),
              value: enabled,
              onChanged: assistant.setRoleplayEnabled,
            ),
          ],
        ),
      ),
      triggerBuilder: (context, controller) => AppTooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: binding == null ? tooltip : '$tooltip · $status',
          excludeSemantics: true,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: MenuItemSurface(
            key: const ValueKey('roleplay-chat-menu'),
            theme: theme,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (binding != null && binding.card.avatar != null)
                      RoleplayAvatar(card: binding.card, theme: theme, size: 18)
                    else
                      Icon(
                        binding == null
                            ? _noRoleplayCardIcon
                            : Symbols.badge_rounded,
                        size: 16,
                        fill: binding == null ? 0 : 1,
                        color: theme.textColorSecondary,
                      ),
                    if (!widget.compact) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColorSecondary,
                          ),
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
      ),
    );
  }
}

class RoleplayTemplateMenu extends StatefulWidget {
  const RoleplayTemplateMenu({
    super.key,
    required this.theme,
    required this.binding,
    required this.templates,
    required this.onSelected,
    required this.onSettings,
    this.triggerBuilder,
    this.detailControls,
    this.onChooseOpening,
  });

  final AppTheme theme;
  final AiRoleplayBinding? binding;
  final Iterable<AiRoleplayBinding> templates;
  final ValueChanged<AiRoleplayBinding?>? onSelected;
  final ValueChanged<AiRoleplayBinding> onSettings;
  final Widget Function(BuildContext, MenuController)? triggerBuilder;
  final Widget? detailControls;
  final ValueChanged<AiRoleplayBinding>? onChooseOpening;

  @override
  State<RoleplayTemplateMenu> createState() => _RoleplayTemplateMenuState();
}

class _RoleplayTemplateMenuState extends State<RoleplayTemplateMenu> {
  final _menu = MenuController();
  final _search = TextEditingController();
  bool _showingList = false;
  bool get _inChat => widget.triggerBuilder != null;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.binding?.card;
    return RawMenuAnchor(
      controller: _menu,
      onOpen: () => setState(() {}),
      onClose: () {
        if (mounted) {
          setState(() {
            _showingList = false;
            _search.clear();
          });
        }
      },
      overlayBuilder: _buildPanel,
      builder: (context, controller, _) =>
          widget.triggerBuilder?.call(context, controller) ??
          RoleplayFieldButton(
            theme: widget.theme,
            label: card?.name ?? context.l10n.aiRoleplayNoCard,
            icon: switch (card) {
              null => const Icon(_noRoleplayCardIcon, fill: 0),
              final card when card.avatar != null => RoleplayAvatar(
                card: card,
                theme: widget.theme,
                size: 16,
              ),
              _ => const Icon(Symbols.badge_rounded, fill: 1),
            },
            expanded: controller.isOpen,
            onPressed: widget.onSelected == null
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
          ),
    );
  }

  Widget _buildPanel(BuildContext context, RawMenuOverlayInfo info) {
    const gap = PopupMenuSurface.fieldAnchorGap;
    final bounds =
        (const EdgeInsets.all(PopupMenuSurface.verticalInset) +
                MediaQuery.paddingOf(context) +
                MediaQuery.viewInsetsOf(context))
            .deflateRect(Offset.zero & info.overlaySize);
    if (bounds.isEmpty) return const SizedBox.shrink();

    final anchor = info.anchorRect;
    final aboveEdge = (anchor.top - gap).clamp(bounds.top, bounds.bottom);
    final belowEdge = (anchor.bottom + gap).clamp(bounds.top, bounds.bottom);
    final above = aboveEdge - bounds.top;
    final below = bounds.bottom - belowEdge;
    final binding = widget.binding;
    final detail = _showingList ? null : binding;
    final seen = <String>{};
    final templates = [
      for (final template in [?binding, ...widget.templates])
        if (seen.add(template.sourceCard.templateFingerprint)) template,
    ];
    final preferredHeight = (118.0 + templates.length * 60).clamp(
      _inChat ? 196.0 : 134.0,
      _RoleplayMenuPanel.height,
    );
    final opensAbove = _inChat
        ? above >= preferredHeight || above >= below
        : below < preferredHeight && above > below;
    final width = _RoleplayMenuPanel.preferredWidth.clamp(0.0, bounds.width);
    final maxHeight = (opensAbove ? above : below).clamp(
      0.0,
      _RoleplayMenuPanel.height,
    );
    final minimumHeight = detail == null ? 110.0 : 48.0;
    if (maxHeight < MediaQuery.textScalerOf(context).scale(minimumHeight)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: anchor.left.clamp(bounds.left, bounds.right - width),
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
          child: PopupMenuTransition(
            alignment: opensAbove ? Alignment.bottomLeft : Alignment.topLeft,
            child: _RoleplayMenuPanel(
              key: const ValueKey('roleplay-template-panel'),
              theme: widget.theme,
              width: width,
              maxHeight: maxHeight,
              child: PopupMenuPageTransition(
                child: _buildPage(context, detail, templates, maxHeight),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    AiRoleplayBinding? binding,
    List<AiRoleplayBinding> templates,
    double maxHeight,
  ) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final leadingInset = binding == null ? 8.0 : 12.0;
    final query = _search.text.trim().toLowerCase();
    final results = query.isEmpty
        ? templates
        : templates.where((template) {
            final card = template.sourceCard;
            return card.name.toLowerCase().contains(query) ||
                card.creator.toLowerCase().contains(query);
          }).toList();
    return ConstrainedBox(
      key: ValueKey(binding != null),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              leadingInset,
              8,
              popupMenuOptionsTrailingInset,
              8,
            ),
            child: _header(context, canGoBack: binding != null),
          ),
          if (binding == null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
              child: SettingSearchField(
                fieldKey: const ValueKey('roleplay-template-search'),
                theme: theme,
                controller: _search,
                hintText: l10n.aiSearchRoleplayCards,
                backgroundColor: theme.primary,
                onChanged: (_) => setState(() {}),
                onClear: () => setState(_search.clear),
              ),
            ),
          Flexible(
            child: ScrollbarTheme(
              data: ScrollbarTheme.of(
                context,
              ).copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
              child: CustomScrollView(
                key: ValueKey(query),
                shrinkWrap: true,
                primary: false,
                scrollBehavior: const AppScrollBehavior(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      leadingInset,
                      0,
                      popupMenuOptionsTrailingInset,
                      8,
                    ),
                    sliver: binding != null
                        ? SliverToBoxAdapter(
                            child: _managementPanel(context, binding),
                          )
                        : SliverList.separated(
                            itemCount: results.length + 1,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: popupMenuOptionSpacing),
                            itemBuilder: (context, index) => _option(
                              context,
                              index,
                              index == 0 ? null : results[index - 1],
                            ),
                          ),
                  ),
                  if (binding == null && results.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                        child: Text(
                          query.isEmpty
                              ? l10n.aiNoRoleplayCards
                              : l10n.aiNoMatchingRoleplayCards,
                          style: AppDialogStyle.descriptionStyle(theme),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, {required bool canGoBack}) {
    final l10n = context.l10n;
    final theme = widget.theme;
    return Row(
      spacing: 8,
      children: [
        if (canGoBack)
          AppTooltip(
            message: l10n.back,
            child: TitleBarIconButton(
              key: const ValueKey('roleplay-template-back'),
              theme: theme,
              isFocused: true,
              icon: Symbols.arrow_back_rounded,
              size: 26,
              iconSize: 16,
              backgroundColor: PopupMenuSurface.backgroundColorFor(theme),
              onPressed: () => setState(() => _showingList = true),
            ),
          ),
        Expanded(
          child: Text(
            l10n.aiRoleplayCard,
            key: const ValueKey('roleplay-template-heading'),
            style: AppDialogStyle.fieldTitleStyle(theme).copyWith(
              fontWeight: FontWeight.w600,
              color: theme.textColorPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _managementPanel(BuildContext context, AiRoleplayBinding binding) {
    final l10n = context.l10n;
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoleplaySelectionArea(
          child: RoleplayCardInfo(card: binding.card, theme: theme),
        ),
        if (widget.detailControls case final controls?) ...[
          const SizedBox(height: 14),
          controls,
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _RoleplayMenuAction(
              key: ValueKey(
                _inChat
                    ? 'roleplay-menu-settings'
                    : 'roleplay-template-settings',
              ),
              theme: theme,
              label: l10n.aiRoleplayCardSettings,
              icon: Symbols.tune_rounded,
              onPressed: () {
                _menu.close();
                widget.onSettings(binding);
              },
            ),
            if (widget.onChooseOpening case final chooseOpening?)
              _RoleplayMenuAction(
                key: const ValueKey('roleplay-menu-opening'),
                theme: theme,
                label: l10n.aiRoleplayStartStory,
                icon: Symbols.auto_stories_rounded,
                onPressed: () {
                  _menu.close();
                  chooseOpening(binding);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _option(BuildContext context, int index, AiRoleplayBinding? template) {
    final card = template?.card;
    final theme = widget.theme;
    final l10n = context.l10n;
    final metadata = card == null ? '' : _roleplayCardMetadata(context, card);
    final selected = identical(template, widget.binding);
    return buildPopupMenuOption(
      key: ValueKey('roleplay-template-option-$index'),
      theme: theme,
      leading: card == null
          ? const SizedBox.square(
              dimension: 28,
              child: Icon(_noRoleplayCardIcon, size: 16, fill: 0),
            )
          : RoleplayAvatar(card: card, theme: theme, size: 28),
      title: card?.name ?? l10n.aiRoleplayNoCard,
      description: card == null
          ? l10n.aiRoleplayNoCardSummary
          : metadata.isEmpty
          ? l10n.aiRoleplayCardDetailsSummary
          : metadata,
      selected: selected,
      next: card != null,
      onPressed: () {
        if (template == null) {
          _menu.close();
        } else {
          setState(() => _showingList = false);
        }
        if (!selected) widget.onSelected?.call(template);
      },
    );
  }
}

class RoleplayFieldButton extends StatelessWidget {
  const RoleplayFieldButton({
    super.key,
    required this.theme,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expanded = false,
  });

  final AppTheme theme;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final background = theme.selectControlColorForSurface(
      AppDialogStyle.backgroundColor(theme),
    );
    return MenuItemSurface(
      theme: theme,
      backgroundColor: background,
      surfaceColor: background,
      foregroundColor: onPressed == null
          ? theme.textColorTertiary
          : theme.textColorSecondary,
      borderRadius: BorderRadius.circular(4),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(data: const IconThemeData(size: 16), child: icon),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0 : -.25,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : PopupMenuTransition.duration,
                child: const Icon(Symbols.expand_more_rounded, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleplayMenuPanel extends StatelessWidget {
  const _RoleplayMenuPanel({
    super.key,
    required this.theme,
    required this.width,
    required this.maxHeight,
    required this.child,
  });

  static const preferredWidth = 336.0;
  static const height = 360.0;

  final AppTheme theme;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopupMenuSurface(
    theme: theme,
    padding: EdgeInsets.zero,
    child: SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      ),
    ),
  );
}

class _RoleplayMenuAction extends StatelessWidget {
  const _RoleplayMenuAction({
    super.key,
    required this.theme,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final AppTheme theme;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppActionButton(
    theme: theme,
    label: label,
    surfaceColor: PopupMenuSurface.backgroundColorFor(theme),
    icon: icon,
    iconFill: 1,
    iconSize: 15,
    iconSpacing: 5,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    onPressed: onPressed,
  );
}

Future<bool?> confirmRoleplayCardImport(
  BuildContext context,
  AppTheme theme,
  AiRoleplayCard card,
) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      theme: theme,
      title: l10n.aiRoleplayImport,
      titleFontWeight: FontWeight.w500,
      constraints: const BoxConstraints(maxWidth: 540),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: _RoleplayCardDialogContent(card: card, theme: theme),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        AppActionButton.dialog(
          key: const ValueKey('roleplay-confirm-import'),
          theme: theme,
          label: l10n.aiRoleplayConfirmImport,
          primary: true,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
}

class RoleplayCardDetails extends StatelessWidget {
  const RoleplayCardDetails({
    super.key,
    required this.card,
    required this.theme,
  });

  final AiRoleplayCard card;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) => _RoleplaySelectionArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RoleplayCardInfo(card: card, theme: theme),
        if (card.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.aiRoleplayTags(card.tags.join(', ')),
            style: AppDialogStyle.descriptionStyle(theme),
          ),
        ],
        if (card.creatorNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.aiRoleplayCreatorNotes,
            style: AppDialogStyle.fieldTitleStyle(theme),
          ),
          const SizedBox(height: 4),
          Text(
            card.creatorNotes,
            style: AppDialogStyle.descriptionStyle(theme),
          ),
        ],
      ],
    ),
  );
}

class RoleplayCardOptionsDialog extends StatefulWidget {
  const RoleplayCardOptionsDialog({
    super.key,
    required this.binding,
    required this.theme,
  });

  final AiRoleplayBinding binding;
  final AppTheme theme;

  @override
  State<RoleplayCardOptionsDialog> createState() =>
      _RoleplayCardOptionsDialogState();
}

class _RoleplayCardOptionsDialogState extends State<RoleplayCardOptionsDialog> {
  late bool _includeProfile = widget.binding.includeProfile;
  late bool _includeWorldBook = widget.binding.includeWorldBook;
  late bool _includeAdvancedPrompts = widget.binding.includeAdvancedPrompts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final card = widget.binding.sourceCard;
    return AppDialog(
      theme: theme,
      title: l10n.aiRoleplayCardSettings,
      titleFontWeight: FontWeight.w500,
      constraints: const BoxConstraints(maxWidth: 540),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: _RoleplayCardDialogContent(
        card: card,
        theme: theme,
        profile: (
          value: _includeProfile,
          onChanged: (value) => setState(() => _includeProfile = value),
        ),
        worldBook: (
          value: _includeWorldBook,
          onChanged: (value) => setState(() => _includeWorldBook = value),
        ),
        advanced: (
          value: _includeAdvancedPrompts,
          onChanged: (value) => setState(() => _includeAdvancedPrompts = value),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(context),
        ),
        AppActionButton.dialog(
          key: const ValueKey('roleplay-import-confirm'),
          theme: theme,
          label: l10n.aiRoleplaySaveSettings,
          primary: true,
          onPressed:
              !_includeProfile && !_includeWorldBook && !_includeAdvancedPrompts
              ? null
              : () => Navigator.pop(
                  context,
                  AiRoleplayBinding(
                    card: card,
                    playerName: widget.binding.playerName,
                    includeProfile: _includeProfile,
                    includeWorldBook: _includeWorldBook,
                    includeAdvancedPrompts: _includeAdvancedPrompts,
                  ),
                ),
        ),
      ],
    );
  }
}

typedef _RoleplayOption = ({bool value, ValueChanged<bool> onChanged});

class _RoleplayCardDialogContent extends StatelessWidget {
  const _RoleplayCardDialogContent({
    required this.card,
    required this.theme,
    this.profile,
    this.worldBook,
    this.advanced,
  });

  final AiRoleplayCard card;
  final AppTheme theme;
  final _RoleplayOption? profile;
  final _RoleplayOption? worldBook;
  final _RoleplayOption? advanced;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unavailable = profile == null
        ? l10n.aiRoleplayNotInCard
        : l10n.aiRoleplayContentUnavailable;
    return SizedBox(
      width: 492,
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context)
            .copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              RoleplayCardDetails(card: card, theme: theme),
              _option(
                key: const ValueKey('roleplay-import-profile'),
                title: l10n.aiRoleplayImportProfile,
                subtitle: l10n.aiRoleplayImportProfileDetail,
                available: true,
                control: profile,
              ),
              _option(
                key: const ValueKey('roleplay-import-world-book'),
                title: l10n.aiRoleplayImportWorldBook,
                subtitle: card.worldEntryCount > 0
                    ? l10n.aiRoleplayImportWorldBookDetail(card.worldEntryCount)
                    : unavailable,
                available: card.worldEntryCount > 0,
                control: worldBook,
              ),
              _option(
                key: const ValueKey('roleplay-import-advanced'),
                title: l10n.aiRoleplayImportAdvanced,
                subtitle: card.hasAdvancedPrompts
                    ? l10n.aiRoleplayImportAdvancedDetail
                    : unavailable,
                available: card.hasAdvancedPrompts,
                control: advanced,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option({
    required Key key,
    required String title,
    required String subtitle,
    required bool available,
    required _RoleplayOption? control,
  }) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Opacity(
              opacity: available ? 1 : .65,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppDialogStyle.fieldTitleStyle(theme)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppDialogStyle.descriptionStyle(theme)),
                ],
              ),
            ),
          ),
          if (control != null) ...[
            const SizedBox(width: 8),
            CompactSettingSwitch(
              controlKey: key,
              theme: theme,
              surface: AppDialogStyle.backgroundColor(theme),
              value: control.value,
              onChanged: available ? control.onChanged : null,
            ),
          ],
        ],
      ),
    );
  }
}

const _openingDialogPadding = EdgeInsets.only(top: 16, bottom: 24);
const _openingBodyPadding = EdgeInsets.symmetric(horizontal: 24);

Future<({int index, bool clearExisting})?> pickRoleplayOpening(
  BuildContext context,
  AppTheme theme,
  AiRoleplayBinding binding, {
  required bool Function() hasConversationToRestart,
  bool forCreation = false,
  int? selectedOpening,
  VoidCallback? onClearSelection,
}) {
  final l10n = context.l10n;
  final openings = binding.sourceCard.openings;
  final surface = AppDialogStyle.backgroundColor(theme);
  return showDialog<({int index, bool clearExisting})>(
    context: context,
    builder: (dialogContext) => AppDialog(
      theme: theme,
      title: l10n.aiRoleplaySelectOpening,
      constraints: const BoxConstraints(maxWidth: 400),
      contentPadding: _openingDialogPadding,
      content: SizedBox(
        width: 388,
        child: SingleChildScrollView(
          padding: _openingBodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: popupMenuOptionSpacing,
            children: [
              if (forCreation)
                buildPopupMenuOption(
                  key: const ValueKey('roleplay-opening-clear-selection'),
                  theme: theme,
                  backgroundColor: surface,
                  leading: const SizedBox.square(
                    dimension: 28,
                    child: Icon(Symbols.edit_note_rounded, size: 16, fill: 1),
                  ),
                  title: l10n.aiRoleplayManualOpening,
                  description: l10n.aiRoleplayManualOpeningSummary,
                  selected: selectedOpening == null,
                  onPressed: () {
                    onClearSelection?.call();
                    Navigator.pop(dialogContext);
                  },
                ),
              for (final (index, opening) in openings.indexed)
                buildPopupMenuOption(
                  key: ValueKey('roleplay-opening-$index'),
                  theme: theme,
                  backgroundColor: surface,
                  leading: const SizedBox.square(
                    dimension: 28,
                    child: Icon(
                      Symbols.auto_stories_rounded,
                      size: 16,
                      fill: 1,
                    ),
                  ),
                  title: l10n.aiRoleplayOpeningNumber(index + 1),
                  description: binding.openingText(opening),
                  selected: forCreation && selectedOpening == index,
                  next: true,
                  onPressed: () async {
                    final clearExisting = hasConversationToRestart();
                    final confirmed = await _confirmRoleplayOpening(
                      dialogContext,
                      theme,
                      title: l10n.aiRoleplayOpeningNumber(index + 1),
                      text: binding.openingText(opening),
                      clearExisting: clearExisting,
                      forCreation: forCreation,
                    );
                    if (confirmed == true && dialogContext.mounted) {
                      Navigator.pop(dialogContext, (
                        index: index,
                        clearExisting: clearExisting,
                      ));
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmRoleplayOpening(
  BuildContext context,
  AppTheme theme, {
  required String title,
  required String text,
  required bool clearExisting,
  required bool forCreation,
}) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (previewContext) => AppDialog(
      theme: theme,
      title: l10n.aiRoleplayOpeningPreview(title),
      constraints: const BoxConstraints(maxWidth: 540),
      contentPadding: _openingDialogPadding,
      content: SizedBox(
        width: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (clearExisting)
              Padding(
                padding: _openingBodyPadding.copyWith(bottom: 12),
                child: Text(
                  l10n.aiRoleplayRestartWarning,
                  style: AppDialogStyle.fieldTitleStyle(theme)
                      .copyWith(color: theme.materialColors.error, height: 1.4),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: _openingBodyPadding,
                child: _RoleplaySelectionArea(
                  child: Text(
                    text,
                    key: const ValueKey('roleplay-opening-preview-text'),
                    style: AppDialogStyle.fieldTitleStyle(theme)
                        .copyWith(fontWeight: FontWeight.normal, height: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppActionButton.dialog(
          key: const ValueKey('roleplay-opening-preview-cancel'),
          theme: theme,
          label: l10n.settingsCancel,
          onPressed: () => Navigator.pop(previewContext),
        ),
        AppActionButton.dialog(
          key: const ValueKey('roleplay-opening-preview-confirm'),
          theme: theme,
          label: clearExisting
              ? l10n.aiRoleplayClearAndStart
              : forCreation
              ? l10n.aiRoleplayUseOpening
              : l10n.aiRoleplayStartStory,
          primary: !clearExisting,
          destructive: clearExisting,
          onPressed: () => Navigator.pop(previewContext, true),
        ),
      ],
    ),
  );
}

class _RoleplaySelectionArea extends StatefulWidget {
  const _RoleplaySelectionArea({required this.child});

  final Widget child;

  @override
  State<_RoleplaySelectionArea> createState() => _RoleplaySelectionAreaState();
}

class _RoleplaySelectionAreaState extends State<_RoleplaySelectionArea> {
  final _selection = GlobalKey<SelectionAreaState>();

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    onTapOutside: (event) {
      if (event.buttons != kPrimaryMouseButton) return;
      _selection.currentState?.selectableRegion
        ?..hideToolbar()
        ..clearSelection();
    },
    child: SelectionArea(
      key: _selection,
      contextMenuBuilder: AppTextSelectionMenu.buildRegion,
      child: widget.child,
    ),
  );
}

String _roleplayCardMetadata(BuildContext context, AiRoleplayCard card) {
  final l10n = context.l10n;
  return [
    if (card.creator.isNotEmpty) l10n.aiRoleplayAuthor(card.creator),
    if (card.version.isNotEmpty) l10n.aiRoleplayCardVersion(card.version),
    if (card.formatVersion.isNotEmpty)
      l10n.aiRoleplayFormatVersion(card.formatVersion),
  ].join(' · ');
}

class RoleplayCardInfo extends StatelessWidget {
  const RoleplayCardInfo({
    super.key,
    required this.card,
    required this.theme,
    this.subtitle,
  });

  final AiRoleplayCard card;
  final AppTheme theme;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final metadata = _roleplayCardMetadata(context, card);
    return Row(
      spacing: 10,
      children: [
        RoleplayAvatar(card: card, theme: theme, size: 36),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                overflow: TextOverflow.clip,
                style: AppDialogStyle.titleStyle(theme).copyWith(fontSize: 15),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  metadata,
                  overflow: TextOverflow.clip,
                  style: AppDialogStyle.descriptionStyle(theme),
                ),
              ],
              if (subtitle case final detail?) ...[
                const SizedBox(height: 4),
                Text(detail, style: AppDialogStyle.descriptionStyle(theme)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class RoleplayAvatar extends StatelessWidget {
  const RoleplayAvatar({
    super.key,
    required this.card,
    required this.theme,
    required this.size,
  });

  final AiRoleplayCard card;
  final AppTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = card.avatar;
    final fallback = Center(
      child: Icon(
        Symbols.person_rounded,
        color: theme.textColorSecondary,
        size: size * .65,
        fill: 1,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: ColoredBox(
            color: theme.secondary,
            child: bytes == null
                ? fallback
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
