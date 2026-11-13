/*
 * @Description: 展示可排序的模型服务列表，并通过弹窗添加或编辑服务。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-11 14:37:42
 */

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'error_text.dart';
import 'service_editor_dialog.dart';

class AiServiceSettingsContent extends StatefulWidget {
  const AiServiceSettingsContent({super.key, required this.theme});
  final AppTheme theme;

  @override
  State<AiServiceSettingsContent> createState() =>
      _AiServiceSettingsContentState();
}

class _AiServiceSettingsContentState extends State<AiServiceSettingsContent> {
  Object? _error;

  Future<void> _edit(
    AiAssistantProvider assistant, [
    AiModelService? service,
  ]) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ServiceEditorDialog(
        theme: widget.theme,
        assistant: assistant,
        service: service,
      ),
    );
    if (mounted && id != null) {
      setState(() {
        _error = null;
      });
    }
  }

  Future<void> _delete(
    AiAssistantProvider assistant,
    AiModelService service,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmation(
      context: context,
      theme: widget.theme,
      actionKey: 'ai-service',
      title: l10n.aiDeleteService,
      description: l10n.aiDeleteServiceMessage(service.name),
      confirmLabel: l10n.aiDeleteService,
    );
    if (!confirmed || !mounted) return;
    try {
      await assistant.removeService(service.id);
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _reorder(
    AiAssistantProvider assistant,
    int oldIndex,
    int newIndex,
  ) async {
    if (!assistant.canChangeService || oldIndex == newIndex) {
      return;
    }
    try {
      await assistant.reorderServices(oldIndex, newIndex);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AiAssistantProvider>();
    final theme = widget.theme;
    final l10n = context.l10n;
    final busy = !assistant.canChangeService;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.aiServiceTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.aiServiceDescription,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.textColorTertiary,
                  ),
                ),
                const SizedBox(height: 24),
                Divider(height: 1, color: theme.dividerColor),
                const SizedBox(height: 20),
                if (!assistant.credentialLoaded)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final title = Text(
                        l10n.aiAddedServices,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textColorPrimary,
                        ),
                      );
                      final addButton = AppActionButton(
                        key: const ValueKey('ai-add-service'),
                        theme: theme,
                        label: l10n.aiAddModelService,
                        icon: Symbols.add_rounded,
                        iconSize: 18,
                        iconSpacing: 6,
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        onPressed: busy ? null : () => _edit(assistant),
                      );
                      if (constraints.maxWidth < 480) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            title,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: addButton,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: title),
                          addButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (assistant.services.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          l10n.aiNoServices,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textColorTertiary,
                          ),
                        ),
                      ),
                    ),
                ],
                if (_error ?? assistant.configurationError
                    case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    aiErrorText(l10n, error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (assistant.credentialLoaded && assistant.services.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            sliver: SliverReorderableList(
              key: const ValueKey('ai-service-list'),
              dragBoundaryProvider: _ServiceDragBoundary.new,
              autoScrollerVelocityScalar: 500,
              itemCount: assistant.services.length,
              onReorder: (oldIndex, newIndex) => _reorder(
                assistant,
                oldIndex,
                newIndex > oldIndex ? newIndex - 1 : newIndex,
              ),
              itemBuilder: (context, index) {
                final service = assistant.services[index];
                return Padding(
                  key: ValueKey(service.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _serviceRow(
                    assistant: assistant,
                    service: service,
                    index: index,
                    busy: busy,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _serviceRow({
    required AiAssistantProvider assistant,
    required AiModelService service,
    required int index,
    required bool busy,
  }) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          service.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.textColorPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${l10n.aiBaseUrlLabel}: ${service.baseUrl}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: theme.textColorSecondary),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppActionButton(
          theme: theme,
          tertiaryBackground: true,
          label: l10n.aiEditService,
          onPressed: busy ? null : () => _edit(assistant, service),
        ),
        AppActionButton(
          key: ValueKey('ai-delete-service-${service.id}'),
          theme: theme,
          destructive: true,
          label: l10n.delete,
          icon: Symbols.delete_outline_rounded,
          iconSize: 16,
          iconSpacing: 6,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          borderRadius: BorderRadius.circular(8),
          onPressed: busy ? null : () => _delete(assistant, service),
        ),
      ],
    );
    final canDrag = !busy && assistant.services.length > 1;
    return Material(
      key: ValueKey('ai-service-card-${service.id}'),
      color: theme.settingsControlBackgroundColor,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Semantics(
              label: l10n.aiDragService,
              enabled: canDrag,
              onIncrease: canDrag && index < assistant.services.length - 1
                  ? () => _reorder(assistant, index, index + 1)
                  : null,
              onDecrease: canDrag && index > 0
                  ? () => _reorder(assistant, index, index - 1)
                  : null,
              child: AppTooltip(
                message: l10n.aiDragService,
                child: MouseRegion(
                  cursor: canDrag
                      ? SystemMouseCursors.grab
                      : SystemMouseCursors.basic,
                  child: ReorderableDragStartListener(
                    key: ValueKey('ai-drag-service-${service.id}'),
                    index: index,
                    enabled: canDrag,
                    child: Container(
                      color: Colors.transparent,
                      width: 28,
                      height: 32,
                      child: Icon(
                        Symbols.drag_indicator_rounded,
                        size: 20,
                        color: theme.iconColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth <
                      620 * MediaQuery.textScalerOf(context).scale(1)) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 排序浮层限制在列表的可见区域；滚动时重新计算边界，避开上方标题和操作区。
class _ServiceDragBoundary extends DragBoundaryDelegate<Rect> {
  _ServiceDragBoundary(this.context);

  final BuildContext context;

  Rect? get _bounds {
    final sliver = context.findRenderObject();
    if (sliver is! RenderSliver || !sliver.attached) return null;
    final viewport = RenderAbstractViewport.of(sliver);
    final paintedBounds = MatrixUtils.transformRect(
      sliver.getTransformTo(null),
      sliver.paintBounds,
    );
    final geometry = sliver.geometry!;
    final listBounds = Rect.fromLTRB(
      paintedBounds.left,
      paintedBounds.top - (sliver.constraints.scrollOffset > 0 ? 2 : 0),
      paintedBounds.right,
      paintedBounds.bottom +
          (geometry.scrollExtent >
                  sliver.constraints.scrollOffset + geometry.paintExtent
              ? 2
              : 0),
    );
    final viewportBounds = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      viewport.paintBounds,
    );
    // Flutter 自动滚动要求浮层越过视口至少 1px；保留 2px 边缘触发带，
    // 同时仍受列表本身的边界约束，不会越过标题区或列表末尾。
    return listBounds.intersect(
      Rect.fromLTRB(
        viewportBounds.left,
        viewportBounds.top - 2,
        viewportBounds.right,
        viewportBounds.bottom + 2,
      ),
    );
  }

  @override
  bool isWithinBoundary(Rect draggedObject) =>
      nearestPositionWithinBoundary(draggedObject) == draggedObject;

  @override
  Rect nearestPositionWithinBoundary(Rect draggedObject) {
    final bounds = _bounds;
    if (bounds == null || bounds.isEmpty) return draggedObject;
    // 极小窗口中可见区域可能比卡片小，固定起点，避免无效 clamp 范围。
    final maxLeft = (bounds.right - draggedObject.width).clamp(
      bounds.left,
      double.infinity,
    );
    final maxTop = (bounds.bottom - draggedObject.height).clamp(
      bounds.top,
      double.infinity,
    );
    return Rect.fromLTWH(
      draggedObject.left.clamp(bounds.left, maxLeft),
      draggedObject.top.clamp(bounds.top, maxTop),
      draggedObject.width,
      draggedObject.height,
    );
  }
}
