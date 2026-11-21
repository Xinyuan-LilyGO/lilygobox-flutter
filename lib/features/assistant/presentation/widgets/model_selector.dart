/*
 * @Description: 为主页提供右键菜单风格的服务分组模型菜单与设备风格搜索框。
 */

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_capsule_slider.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/interaction_decoration.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/search_clear_button.dart';
import '../../domain/models.dart';
import '../../domain/reasoning.dart';
import '../../state/provider.dart';
import 'error_text.dart';
import 'reasoning_effort_label.dart';

class ModelSelector extends StatefulWidget {
  const ModelSelector({
    super.key,
    required this.theme,
    required this.assistant,
    this.selectedServiceId,
    this.selectedModel,
    this.onSelected,
    this.auxiliarySelection,
    this.onAuxiliarySelected,
    this.fieldSurfaceColor,
  }) : assert(onAuxiliarySelected == null || onSelected == null);
  final AppTheme theme;
  final AiAssistantProvider assistant;

  /// 外部选择使用调用者提供的独立草稿，并复用完整模型／强度页面。
  final String? selectedServiceId;
  final String? selectedModel;
  final void Function(String serviceId, String model)? onSelected;
  final AiModelSelection? auxiliarySelection;
  final ValueChanged<AiModelSelection>? onAuxiliarySelected;
  final Color? fieldSurfaceColor;

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  static const _modelIcon = Icon(Symbols.blur_on, size: 16, fill: 1);

  final _menu = MenuController();
  final _dismissGroup = Object();
  final _buttonKey = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  final _selectedModelKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _serviceHeaderKeys = <String, GlobalKey>{};
  bool _revealSelected = false;
  String? _pinnedService;
  Object? _error;
  int _openRevision = 0;
  double? _fieldMenuHeight;
  String? _reasoningModel;
  int _effortIndex = 0;

  bool get _auxiliary => widget.onAuxiliarySelected != null;
  bool get _external => _auxiliary || widget.onSelected != null;
  bool get _followsChatModel => _auxiliary && widget.auxiliarySelection == null;
  String? get _selectedServiceId => _auxiliary && !_followsChatModel
      ? widget.auxiliarySelection?.serviceId
      : widget.onSelected != null
      ? widget.selectedServiceId
      : widget.assistant.selectedService?.id;
  String? get _selectedModel => _auxiliary && !_followsChatModel
      ? widget.auxiliarySelection?.model
      : widget.onSelected != null
      ? widget.selectedModel
      : widget.assistant.selectedModel;
  AiReasoningEffort? get _selectedEffort => _auxiliary && !_followsChatModel
      ? switch (widget.auxiliarySelection) {
          final selection? => widget.assistant.auxiliaryModelEffort(selection),
          null => null,
        }
      : widget.assistant.reasoningEffort;
  Iterable<AiModelService> get _services => widget.assistant.services.where(
    (service) => !_external || widget.assistant.hasServiceKey(service.id),
  );
  bool get _canSelect => _external || widget.assistant.canChangeService;

  bool _isSelectedModel(AiModelService service, String model) =>
      _selectedServiceId == service.id && _selectedModel == model;

  // 吸顶标题保留半透明底色，让下方经过的模型项仍能被看见。
  Color get _serviceHeadingColor =>
      widget.theme.popupSurfaceColor.withValues(alpha: 0.86);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updatePinnedService);
    _lastAssistantSelection = _assistantSelection;
    widget.assistant.addListener(_assistantSelectionChanged);
  }

  Object? _lastAssistantSelection;
  Object get _assistantSelection => (
    widget.assistant.selectedService?.id,
    widget.assistant.selectedModel,
    widget.assistant.reasoningEffort,
    widget.assistant.processingSpeed,
  );

  void _assistantSelectionChanged() {
    final selection = _assistantSelection;
    if (!mounted || _lastAssistantSelection == selection) return;
    setState(() {
      _lastAssistantSelection = selection;
      if (_reasoningModel != _selectedModel) _reasoningModel = null;
    });
  }

  @override
  void didUpdateWidget(covariant ModelSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistant != widget.assistant) {
      oldWidget.assistant.removeListener(_assistantSelectionChanged);
      widget.assistant.addListener(_assistantSelectionChanged);
      _lastAssistantSelection = _assistantSelection;
    }
  }

  void _updatePinnedService() {
    if (!mounted || !_scroll.hasClients) return;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    String? name;
    for (final service in _services) {
      final header = _serviceHeaderKeys[service.id]?.currentContext
          ?.findRenderObject();
      if (header is RenderBox &&
          header.hasSize &&
          header.localToGlobal(Offset.zero).dy < top - 1) {
        name = service.name;
      }
    }
    if (name != _pinnedService) setState(() => _pinnedService = name);
  }

  void _positionModelList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_menu.isOpen || !_scroll.hasClients) return;
      if (_revealSelected && _search.text.isEmpty) {
        final selected = _selectedModelKey.currentContext?.findRenderObject();
        final viewport = _viewportKey.currentContext?.findRenderObject();
        final header = _serviceHeaderKeys[_selectedServiceId]?.currentContext
            ?.findRenderObject();
        if (selected is RenderBox &&
            selected.hasSize &&
            viewport is RenderBox &&
            viewport.hasSize &&
            header is RenderBox &&
            header.hasSize) {
          _revealSelected = false;
          // 在选中行上方为固定的服务标题预留空间。
          final offset =
              _scroll.offset +
              selected.localToGlobal(Offset.zero).dy -
              viewport.localToGlobal(Offset.zero).dy -
              header.size.height;
          _scroll.jumpTo(
            offset.clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      }
      _updatePinnedService();
    });
  }

  void _showModels() {
    setState(() {
      _reasoningModel = null;
      _revealSelected = true;
      _pinnedService = null;
    });
  }

  Widget _serviceHeading(String name, {Key? key}) => ColoredBox(
    key: key,
    color: _serviceHeadingColor,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: widget.theme.textColorTertiary,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    widget.assistant.removeListener(_assistantSelectionChanged);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _select(AiModelService service, String model) async {
    if (widget.onAuxiliarySelected case final pick?) {
      final effort = _selectedServiceId == service.id && _selectedModel == model
          ? _selectedEffort
          : widget.assistant.auxiliaryModelEffort((
              serviceId: service.id,
              model: model,
              reasoningEffort: null,
            ));
      pick((serviceId: service.id, model: model, reasoningEffort: effort));
      final options = AiReasoningCapabilities.forModel(model).levels;
      if (options.isEmpty) {
        _menu.close();
      } else {
        _searchFocus.unfocus();
        setState(() {
          _reasoningModel = model;
          _effortIndex = options.indexWhere((option) => option == effort);
        });
      }
      return;
    }
    try {
      await widget.assistant.selectModel(service.id, model);
      if (!mounted) return;
      widget.onSelected?.call(service.id, model);
      if (AiReasoningCapabilities.forModel(model).levels.isEmpty) {
        _menu.close();
      }
      setState(() {
        _error = null;
        _reasoningModel = AiReasoningCapabilities.forModel(model).levels.isEmpty
            ? null
            : model;
        _effortIndex = _effortOptions.indexWhere(
          (effort) => effort == widget.assistant.reasoningEffort,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  List<AiReasoningEffort> get _effortOptions =>
      AiReasoningCapabilities.forModel(_reasoningModel ?? '').levels;

  Future<void> _saveEffort() async {
    if (widget.onAuxiliarySelected case final pick?) {
      final serviceId = _selectedServiceId;
      final model = _selectedModel;
      if (serviceId == null || model == null || model != _reasoningModel) {
        return;
      }
      final effort = _effortOptions[_effortIndex];
      if (_followsChatModel && effort == _selectedEffort) return;
      pick((serviceId: serviceId, model: model, reasoningEffort: effort));
      return;
    }
    try {
      await widget.assistant.setReasoningEffort(_effortOptions[_effortIndex]);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _effortIndex = _effortOptions.indexWhere(
            (effort) => effort == widget.assistant.reasoningEffort,
          );
        });
      }
    }
  }

  Widget _processingSpeedToggle() {
    final assistant = widget.assistant;
    final theme = widget.theme;
    final l10n = context.l10n;
    final speeds = assistant.processingSpeeds;
    final speed = assistant.processingSpeed;
    final next = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    String label(AiProcessingSpeed value) => switch (value) {
      AiProcessingSpeed.standard => l10n.aiProcessingSpeedStandard,
      AiProcessingSpeed.fast => l10n.aiProcessingSpeedFast,
      AiProcessingSpeed.ultrafast => l10n.aiProcessingSpeedUltra,
    };
    final description = '${l10n.aiProcessingSpeed}: ${label(speed)}';
    final color = speed == AiProcessingSpeed.standard
        ? theme.textColorTertiary
        : theme.basePrimary;
    return AppTooltip(
      message: label(speed),
      child: Semantics(
        label: description,
        button: true,
        child: MenuItemSurface(
          key: const ValueKey('ai-processing-speed-toggle'),
          theme: theme,
          backgroundColor: theme.popupSurfaceColor,
          borderRadius: BorderRadius.circular(16),
          onPressed: assistant.canChangeService
              ? () async {
                  try {
                    await assistant.setProcessingSpeed(next);
                    if (mounted) setState(() => _error = null);
                  } catch (error) {
                    if (mounted) setState(() => _error = error);
                  }
                }
              : null,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: speed == AiProcessingSpeed.ultrafast
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          left: 0,
                          child: Icon(
                            Symbols.bolt_rounded,
                            fill: 1,
                            size: 18,
                            color: color,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: Icon(
                            Symbols.bolt_rounded,
                            fill: 1,
                            size: 18,
                            color: color,
                          ),
                        ),
                      ],
                    )
                  : Icon(Symbols.bolt_rounded, fill: 1, size: 19, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasoningContent() {
    final theme = widget.theme;
    final l10n = context.l10n;
    final options = _effortOptions;
    final index = _effortIndex.clamp(0, options.length - 1);
    return Padding(
      key: const ValueKey('ai-reasoning-panel'),
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuItemSurface(
            key: const ValueKey('ai-reasoning-models'),
            theme: theme,
            backgroundColor: theme.popupSurfaceColor,
            onPressed: _showModels,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: theme.textColorPrimary),
                    child: _modelIcon,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _reasoningModel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textColorPrimary,
                      ),
                    ),
                  ),
                  const Icon(Symbols.chevron_right_rounded, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Text(
                    l10n.aiReasoningEffort,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorTertiary,
                    ),
                  ),
                ),
                if (!_auxiliary && widget.assistant.processingSpeeds.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _processingSpeedToggle(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reasoningEffortLabel(l10n, options[index]),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.basePrimary,
            ),
          ),
          const SizedBox(height: 14),
          AppCapsuleSlider(
            key: const ValueKey('ai-reasoning-slider'),
            theme: theme,
            value: index / (options.length - 1),
            divisions: options.length - 1,
            icon: Symbols.neurology_rounded,
            snapToDivisions: true,
            label: l10n.aiReasoningEffort,
            semanticFormatter: (value) => reasoningEffortLabel(
              l10n,
              options[(value * (options.length - 1)).round()],
            ),
            onChanged: _auxiliary || widget.assistant.canChangeService
                ? (value) => setState(() {
                    _effortIndex = (value * (options.length - 1)).round();
                  })
                : null,
            onChangeEnd: (_) => _saveEffort(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                reasoningEffortLabel(l10n, options.first),
                style: TextStyle(fontSize: 11, color: theme.textColorTertiary),
              ),
              Text(
                reasoningEffortLabel(l10n, options.last),
                style: TextStyle(fontSize: 11, color: theme.textColorTertiary),
              ),
            ],
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                aiErrorText(l10n, error),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.materialColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final theme = widget.theme;
    final l10n = context.l10n;
    return TextField(
      key: const ValueKey('ai-model-search'),
      contextMenuBuilder: AppTextSelectionMenu.build,
      selectionWidthStyle: ui.BoxWidthStyle.tight,
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
                child: SearchClearButton(
                  theme: theme,
                  onPressed: () => setState(_search.clear),
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
      for (final service in _services)
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
    _positionModelList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 12, 8),
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
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: _searchField(),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * .36).clamp(
              100.0,
              280.0,
            ),
          ),
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              // 菜单右侧已有 4 px 留白，总距离保持全局 6 px。
              crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset - 4,
            ),
            child: Scrollbar(
              key: const ValueKey('ai-model-list-scrollbar'),
              controller: _scroll,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: ScrollConfiguration(
                  behavior: const AppScrollBehavior(scrollbars: false),
                  child: Stack(
                    children: [
                      NotificationListener<ScrollMetricsNotification>(
                        onNotification: (_) {
                          _positionModelList();
                          return false;
                        },
                        child: SizedBox(
                          key: _viewportKey,
                          child: SingleChildScrollView(
                            key: const ValueKey('ai-model-list-scroll'),
                            controller: _scroll,
                            primary: false,
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
                                  if (service != groups.first.$1)
                                    const SizedBox(height: 8),
                                  _serviceHeading(
                                    service.name,
                                    key: _serviceHeaderKeys.putIfAbsent(
                                      service.id,
                                      GlobalKey.new,
                                    ),
                                  ),
                                  for (final model in models) ...[
                                    if (model != models.first)
                                      const SizedBox(height: 4),
                                    MenuItemSurface(
                                      key: ValueKey(
                                        'ai-model-${service.id}-$model',
                                      ),
                                      theme: theme,
                                      disableWhenSelected: false,
                                      backgroundColor: theme.popupSurfaceColor,
                                      selectedColor:
                                          theme.primaryTextHoverColor,
                                      hoverColor: theme.basePrimary,
                                      foregroundColor:
                                          _isSelectedModel(service, model)
                                          ? theme.type == ThemeType.light
                                                ? Colors.black
                                                : theme.materialColors.onPrimary
                                          : theme.textColorSecondary,
                                      hoverForegroundColor:
                                          theme.materialColors.onPrimary,
                                      isSelected: _isSelectedModel(
                                        service,
                                        model,
                                      ),
                                      onPressed: _canSelect
                                          ? () => _select(service, model)
                                          : null,
                                      borderRadius: BorderRadius.circular(4),
                                      child: ConstrainedBox(
                                        key: _isSelectedModel(service, model)
                                            ? _selectedModelKey
                                            : null,
                                        constraints: const BoxConstraints(
                                          minHeight: 28,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              _modelIcon,
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  model,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 17,
                                                child:
                                                    _isSelectedModel(
                                                      service,
                                                      model,
                                                    )
                                                    ? Icon(
                                                        Symbols.check_rounded,
                                                        size: 17,
                                                      )
                                                    : null,
                                              ),
                                              if (AiReasoningCapabilities.forModel(
                                                model,
                                              ).levels.isNotEmpty)
                                                const Icon(
                                                  Symbols.chevron_right_rounded,
                                                  size: 16,
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
                      ),
                      if (_pinnedService case final name?)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: _serviceHeading(
                              name,
                              key: const ValueKey('ai-model-pinned-service'),
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

  Widget _dismissRegion(Widget child, {bool anchor = false}) => _auxiliary
      ? TapRegion(
          groupId: _dismissGroup,
          onTapOutside: anchor && _menu.isOpen ? (_) => _menu.close() : null,
          child: child,
        )
      : child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final assistant = widget.assistant;
    final selectedModel = _selectedModel;
    final effort = _selectedEffort;
    final unavailable =
        _auxiliary &&
        !_followsChatModel &&
        selectedModel != null &&
        !_services.any(
          (service) =>
              service.id == _selectedServiceId &&
              service.models.contains(selectedModel),
        );
    final label = selectedModel == null
        ? l10n.aiSelectModel
        : unavailable
        ? l10n.aiAuxiliaryModelUnavailable(selectedModel)
        : effort == null
        ? selectedModel
        : '$selectedModel · ${reasoningEffortLabel(l10n, effort)}';
    final available = MediaQuery.sizeOf(context);
    const edgeGap = 16.0;
    final menuWidth = (available.width - edgeGap * 4).clamp(0.0, 280.0);
    return MenuAnchor(
      controller: _menu,
      clipBehavior: Clip.none,
      // bottomEnd 是弹窗起点，不是右沿对齐；连同安全留白整体向左移。
      alignmentOffset: Offset(
        widget.fieldSurfaceColor == null ? -menuWidth - edgeGap * 2 : -edgeGap,
        widget.fieldSurfaceColor == null ? 0 : -8,
      ),
      crossAxisUnconstrained: true,
      style: MenuStyle(
        alignment: widget.fieldSurfaceColor == null
            ? AlignmentDirectional.bottomEnd
            : AlignmentDirectional.bottomStart,
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
        if (widget.fieldSurfaceColor != null) {
          final box = _buttonKey.currentContext?.findRenderObject();
          final overlay = Overlay.of(context).context.findRenderObject();
          if (box is RenderBox && overlay is RenderBox) {
            final top = box.localToGlobal(Offset.zero, ancestor: overlay).dy;
            final bottom = box
                .localToGlobal(Offset(0, box.size.height), ancestor: overlay)
                .dy;
            final below = overlay.size.height - bottom;
            final space = _auxiliary ? math.max(top, below) : below;
            _fieldMenuHeight = (space - edgeGap * 2).clamp(0.0, 440.0);
          }
        }
        _openRevision++;
        _revealSelected = true;
        _pinnedService = null;
        _search.clear();
        _searchFocus.unfocus();
        _error = null;
        final model = _selectedModel;
        _reasoningModel =
            !unavailable &&
                model != null &&
                AiReasoningCapabilities.forModel(model).levels.isNotEmpty
            ? model
            : null;
        _effortIndex = _effortOptions.indexWhere(
          (effort) => effort == _selectedEffort,
        );
      }),
      onClose: () {
        if (mounted) setState(() {});
      },
      menuChildren: [
        // 留白参与菜单碰撞布局，贴近窗口边缘时也为卡片和阴影保留空间。
        Padding(
          padding: const EdgeInsets.all(edgeGap),
          child: PopupMenuTransition(
            key: ValueKey(_openRevision),
            alignment: widget.fieldSurfaceColor == null
                ? Alignment.bottomRight
                : Alignment.topLeft,
            fadeKey: const ValueKey('ai-model-menu-fade'),
            child: SizedBox(
              key: const ValueKey('ai-model-menu-surface'),
              width: menuWidth,
              child: _dismissRegion(
                PopupMenuSurface(
                  theme: theme,
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: widget.fieldSurfaceColor == null
                          ? (available.height - 80).clamp(0.0, 440.0)
                          : _fieldMenuHeight ?? 440,
                    ),
                    child: ListenableBuilder(
                      listenable: assistant,
                      builder: (context, _) => AnimatedSize(
                        key: const ValueKey('ai-model-menu-size-transition'),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : PopupMenuTransition.duration,
                        curve: InteractionDecoration.animationCurve,
                        alignment: widget.fieldSurfaceColor == null
                            ? Alignment.bottomRight
                            : Alignment.topLeft,
                        child: SingleChildScrollView(
                          primary: false,
                          child: PopupMenuPageTransition(
                            child:
                                _reasoningModel != null &&
                                    _reasoningModel == _selectedModel
                                ? _reasoningContent()
                                : KeyedSubtree(
                                    key: const ValueKey('ai-model-list-panel'),
                                    child: _menuContent(),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => _dismissRegion(
        MenuItemSurface(
          key: const ValueKey('ai-model-selector'),
          borderRadius: BorderRadius.circular(
            widget.fieldSurfaceColor == null ? 8 : 4,
          ),
          theme: theme,
          surfaceColor: widget.fieldSurfaceColor == null
              ? theme.primary
              : theme.selectControlColorForSurface(widget.fieldSurfaceColor!),
          backgroundColor: widget.fieldSurfaceColor == null
              ? theme.primary
              : theme.selectControlColorForSurface(widget.fieldSurfaceColor!),
          onPressed: assistant.credentialLoaded
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Padding(
            key: _buttonKey,
            padding: EdgeInsets.symmetric(
              horizontal: widget.fieldSurfaceColor == null ? 8 : 6,
              vertical: 5,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: theme.textColorSecondary),
                    child: _modelIcon,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    fit: FlexFit.loose,
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
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    key: const ValueKey('ai-model-selector-arrow'),
                    turns: widget.fieldSurfaceColor == null
                        ? (controller.isOpen ? 0.5 : 0)
                        : (controller.isOpen ? 0 : -.25),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : PopupMenuTransition.duration,
                    curve: widget.fieldSurfaceColor == null
                        ? Curves.easeInOut
                        : Curves.linear,
                    child: Icon(
                      widget.fieldSurfaceColor == null
                          ? Symbols.keyboard_arrow_down_rounded
                          : Symbols.expand_more_rounded,
                      size: widget.fieldSurfaceColor == null ? 15 : 14,
                      color: widget.fieldSurfaceColor == null
                          ? theme.textColorTertiary
                          : theme.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        anchor: true,
      ),
    );
  }
}
