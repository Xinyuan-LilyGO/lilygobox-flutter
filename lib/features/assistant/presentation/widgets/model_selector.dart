/*
 * @Description: 为主页提供右键菜单风格的服务分组模型菜单与设备风格搜索框。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-09 16:25:40
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'error_text.dart';

class ModelSelector extends StatefulWidget {
  const ModelSelector({
    super.key,
    required this.theme,
    required this.assistant,
  });
  final AppTheme theme;
  final AiAssistantProvider assistant;

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  final _menu = MenuController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  Object? _error;
  int _openRevision = 0;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _select(AiModelService service, String model) async {
    try {
      await widget.assistant.selectModel(service.id, model);
      if (!mounted) return;
      _menu.close();
      setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Widget _searchField() {
    final theme = widget.theme;
    final l10n = context.l10n;
    return TextField(
      key: const ValueKey('ai-model-search'),
      contextMenuBuilder: AppTextSelectionMenu.build,
      controller: _search,
      focusNode: _searchFocus,
      onChanged: (_) => setState(() {}),
      style: TextStyle(fontSize: 13, color: theme.textColorPrimary),
      cursorColor: theme.basePrimary,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.aiSearchModels,
        hintStyle: TextStyle(color: theme.textColorTertiary),
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
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  padding: const EdgeInsets.all(4),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const CircleBorder(),
                  ),
                  tooltip: l10n.homeClearSearch,
                  onPressed: () => setState(_search.clear),
                  icon: Icon(
                    Symbols.close,
                    size: 14,
                    color: theme.textColorSecondary,
                  ),
                ),
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: theme.basePrimary),
        ),
      ),
    );
  }

  Widget _menuContent() {
    final l10n = context.l10n;
    final theme = widget.theme;
    final assistant = widget.assistant;
    final query = _search.text.trim().toLowerCase();
    final groups = [
      for (final service in assistant.services)
        (
          service,
          service.models
              .where(
                (model) =>
                    '${service.name} $model'.toLowerCase().contains(query),
              )
              .toList(),
        ),
    ].where((group) => group.$2.isNotEmpty).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            l10n.aiSelectModel,
            key: const ValueKey('ai-model-menu-title'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.textColorPrimary,
            ),
          ),
        ),
        _searchField(),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * .36).clamp(
              100.0,
              280.0,
            ),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            primary: false,
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Symbols.dns_rounded,
                          size: 24,
                          color: theme.textColorTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          assistant.services.isEmpty
                              ? l10n.aiNoServices
                              : l10n.aiNoMatchingModels,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: theme.textColorTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final (service, models) in groups) ...[
                  if (service != groups.first.$1) const SizedBox(height: 8),
                  Padding(
                    // 服务标题对齐模型按钮外沿，上下留白区分标题和选项。
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.textColorTertiary,
                      ),
                    ),
                  ),
                  for (final model in models) ...[
                    if (model != models.first) const SizedBox(height: 4),
                    MenuItemSurface(
                      key: ValueKey('ai-model-${service.id}-$model'),
                      theme: theme,
                      disableWhenSelected: false,
                      backgroundColor: theme.popupSurfaceColor,
                      selectedColor: theme.primaryTextHoverColor,
                      hoverColor: theme.basePrimary,
                      foregroundColor:
                          assistant.selectedService?.id == service.id &&
                              assistant.selectedModel == model
                          ? theme.type == ThemeType.light
                                ? Colors.black
                                : theme.materialColors.onPrimary
                          : theme.textColorSecondary,
                      hoverForegroundColor: theme.materialColors.onPrimary,
                      isSelected:
                          assistant.selectedService?.id == service.id &&
                          assistant.selectedModel == model,
                      onPressed: assistant.canChangeService
                          ? () => _select(service, model)
                          : null,
                      borderRadius: BorderRadius.circular(4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 28),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 17,
                                child:
                                    assistant.selectedService?.id ==
                                            service.id &&
                                        assistant.selectedModel == model
                                    ? Icon(Symbols.check_rounded, size: 17)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              aiErrorText(l10n, error),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final assistant = widget.assistant;
    final available = MediaQuery.sizeOf(context);
    const edgeGap = 16.0;
    final menuWidth = (available.width - edgeGap * 4).clamp(0.0, 280.0);
    return MenuAnchor(
      controller: _menu,
      clipBehavior: Clip.none,
      // bottomEnd 是弹窗起点，不是右沿对齐；连同安全留白整体向左移。
      alignmentOffset: Offset(-menuWidth - edgeGap * 2, 0),
      crossAxisUnconstrained: true,
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      onOpen: () => setState(() {
        _openRevision++;
        _search.clear();
        _searchFocus.unfocus();
        _error = null;
      }),
      menuChildren: [
        // 留白参与菜单碰撞布局，贴近窗口边缘时也为卡片和阴影保留空间。
        Padding(
          padding: const EdgeInsets.all(edgeGap),
          child: PopupMenuTransition(
            key: ValueKey(_openRevision),
            alignment: Alignment.bottomRight,
            fadeKey: const ValueKey('ai-model-menu-fade'),
            child: SizedBox(
              key: const ValueKey('ai-model-menu-surface'),
              width: menuWidth,
              child: PopupMenuSurface(
                theme: theme,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (available.height - 80).clamp(0.0, 440.0),
                  ),
                  child: ListenableBuilder(
                    listenable: assistant,
                    builder: (context, _) => SingleChildScrollView(
                      primary: false,
                      child: _menuContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => MenuItemSurface(
        key: const ValueKey('ai-model-selector'),
        borderRadius: BorderRadius.circular(999),
        theme: theme,
        backgroundColor: theme.primary,
        onPressed: assistant.credentialLoaded
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  assistant.selectedModel ?? l10n.aiSelectModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              AnimatedRotation(
                key: const ValueKey('ai-model-selector-arrow'),
                turns: controller.isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child: Icon(
                  Symbols.keyboard_arrow_down_rounded,
                  size: 15,
                  color: theme.textColorTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
