/*
 * @Description: 构建双层 AI 输入区，承载附件与待处理引导并提供键盘发送和模型选择。
 */

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/clipboard/image_clipboard.dart';
import '../../../../core/context_menu/right_click_menu.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/empty_line_selection.dart';
import '../../../../core/widgets/image_clipboard_menu.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'agent_message_source.dart';
import 'approval_panel.dart';
import 'model_selector.dart';
import 'permissions_button.dart';
import 'usage_chart_colors.dart';
import 'user_input_panel.dart';

/// 后层承载队列与附件，前层保留独立文字输入区。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.input,
    required this.focusNode,
    required this.scrollController,
    required this.theme,
    required this.assistant,
    required this.ready,
    required this.onSend,
    required this.attachments,
    required this.onAttachmentsChanged,
    this.onManageContext,
    this.readClipboardImage = ImageClipboard.readPng,
  });

  final TextEditingController input;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final bool ready;
  final ValueChanged<bool> onSend;
  final List<AiImageAttachment> attachments;
  final ValueChanged<List<AiImageAttachment>> onAttachmentsChanged;
  final VoidCallback? onManageContext;
  final Future<Uint8List?> Function() readClipboardImage;

  Future<void> _pickImages(BuildContext context) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: context.l10n.aiAttachFile,
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        ),
      ],
    );
    if (files.isEmpty) return;
    final selected = <AiImageAttachment>[...attachments];
    for (final file in files) {
      final extension = file.name.toLowerCase().split('.').last;
      final mimeType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        _ => 'image/png',
      };
      selected.add(
        AiImageAttachment(
          name: file.name,
          bytes: await file.readAsBytes(),
          mimeType: mimeType,
        ),
      );
    }
    onAttachmentsChanged(selected);
  }

  Future<void> _pasteImage(BuildContext context) async {
    Uint8List? bytes;
    try {
      bytes = await readClipboardImage();
    } catch (error, stack) {
      developer.log(
        'Image clipboard read failed',
        name: 'ImageClipboard',
        error: error,
        stackTrace: stack,
      );
      if (context.mounted) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiPasteImageFailed,
        );
      }
    }
    if (!context.mounted) return;
    if (bytes != null) {
      onAttachmentsChanged([
        ...attachments,
        AiImageAttachment(
          name: 'clipboard.png',
          bytes: bytes,
          mimeType: 'image/png',
        ),
      ]);
      return;
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return;
    final selection = input.selection;
    final start = selection.isValid ? selection.start : input.text.length;
    final end = selection.isValid ? selection.end : start;
    if (focusNode.context case final editingContext?) {
      if (!editingContext.mounted) return;
      Actions.invoke(
        editingContext,
        ReplaceTextIntent(
          input.value,
          text,
          TextRange(start: start, end: end),
          SelectionChangedCause.keyboard,
        ),
      );
    }
  }

  Widget _attachmentStrip(BuildContext context) {
    final child = attachments.isEmpty && assistant.pendingGuidance.isEmpty
        ? const SizedBox.shrink()
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (assistant.pendingGuidance.isNotEmpty)
                _PendingGuidance(
                  bottomInset: attachments.isNotEmpty ? 0 : 7,
                  theme: theme,
                  assistant: assistant,
                  onEdit: (id) {
                    final message = assistant.takePendingGuidance(id);
                    if (message == null) return;
                    final draft = input.text;
                    final text = [
                      message.content,
                      if (draft.isNotEmpty) draft,
                    ].where((part) => part.isNotEmpty).join('\n');
                    input.value = TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length),
                    );
                    onAttachmentsChanged([
                      ...message.attachments,
                      ...attachments,
                    ]);
                    focusNode.requestFocus();
                  },
                ),
              if (attachments.isNotEmpty &&
                  assistant.pendingGuidance.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Divider(
                    key: const ValueKey('ai-queue-attachments-divider'),
                    height: 1,
                    thickness: 1,
                    color: theme.dividerColor,
                  ),
                ),
              if (attachments.isNotEmpty)
                _ComposerAttachments(
                  topInset: assistant.pendingGuidance.isNotEmpty ? 0 : 7,
                  attachments: attachments,
                  theme: theme,
                  onAttachmentsChanged: onAttachmentsChanged,
                ),
            ],
          );
    // 零时长 AnimatedSize 在附件改变尺寸时可能在布局中再次标记自身。
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }

  Widget _actionButton({
    required AppTheme theme,
    required Key key,
    required String label,
    required IconData icon,
    double size = 32,
    required VoidCallback? onPressed,
  }) => AppTooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      child: TitleBarIconButton(
        key: key,
        theme: theme,
        isFocused: true,
        icon: icon,
        size: size,
        iconSize: 20,
        backgroundColor: theme.textColorPrimary,
        hoverColor: theme.textColorSecondary,
        iconColor: theme.primary,
        onPressed: onPressed,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final request = assistant.pendingApproval;
    final question = assistant.pendingUserInput;
    return PopupMenuPageTransition(
      child: request != null
          ? _pendingCard(
              request.id,
              (countdown) => AssistantApprovalPanel(
                request: request,
                theme: theme,
                inputFocus: focusNode,
                countdown: countdown,
                onResolve: (approve) =>
                    assistant.resolveTool(request.id, approve: approve),
              ),
            )
          : question != null
          ? _pendingCard(
              question.id,
              (countdown) => AssistantUserInputPanel(
                request: question,
                theme: theme,
                inputFocus: focusNode,
                countdown: countdown,
                onSubmit: (answers) =>
                    assistant.resolveUserInput(question.id, answers),
                onCancel: () => assistant.cancelUserInput(question.id),
              ),
            )
          : EmptyLineSelection(child: _buildInput(context)),
    );
  }

  Widget _pendingCard(String id, Widget Function(Widget) panel) => Listener(
    key: ValueKey(id),
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => assistant.keepPendingRequest(id),
    child: Focus(
      canRequestFocus: false,
      onFocusChange: (focused) {
        if (focused) assistant.keepPendingRequest(id);
      },
      child: panel(
        ValueListenableBuilder(
          valueListenable: assistant.requestCountdown,
          builder: (context, countdown, _) {
            if (countdown == null || countdown.id != id) {
              return const SizedBox.shrink();
            }
            final l10n = context.l10n;
            return Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: AppTooltip(
                message: l10n.aiRequestCountdownHint,
                child: Text(
                  l10n.aiRequestCountdown(countdown.seconds),
                  key: const ValueKey('ai-request-countdown'),
                  style: TextStyle(
                    color: theme.textColorSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _buildInput(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          key: const ValueKey('ai-composer-context-layer'),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              theme.primary.withValues(alpha: .42),
              theme.secondary,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: PopupMenuSurface.shadowsFor(theme),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _attachmentStrip(context),
                AnimatedBuilder(
                  animation: focusNode,
                  builder: (context, child) => TextFieldTapRegion(
                    // 第一层空白属于输入区，按住时不能被当作框外点击而失焦。
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapDown: (_) => focusNode.requestFocus(),
                      child: AnimatedContainer(
                        key: const ValueKey('ai-composer-input-layer'),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: focusNode.hasFocus
                                ? theme.basePrimary
                                : Colors.transparent,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: ColoredBox(
                            key: const ValueKey('ai-composer-input-background'),
                            color: theme.primary,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 10, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Focus(
                          onKeyEvent: (_, event) {
                            // 不截获输入法候选确认，也不改变 Shift+Enter 换行行为。
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed &&
                                input.value.composing.isCollapsed) {
                              if (assistant.canSendMessage &&
                                  (input.text.trim().isNotEmpty ||
                                      attachments.isNotEmpty)) {
                                onSend(true);
                              }
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              PasteTextIntent: CallbackAction<PasteTextIntent>(
                                onInvoke: (_) {
                                  unawaited(_pasteImage(context));
                                  return null;
                                },
                              ),
                            },
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.textScalerOf(context).scale(14) *
                                    1.5 *
                                    8,
                              ),
                              child: Scrollbar(
                                key: const ValueKey('ai-input-scrollbar'),
                                controller: scrollController,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 14,
                                  ),
                                  child: ScrollConfiguration(
                                    behavior: const AppScrollBehavior(
                                      scrollbars: false,
                                    ),
                                    child: SingleChildScrollView(
                                      controller: scrollController,
                                      primary: false,
                                      child: TextField(
                                        key: const ValueKey('ai-message-input'),
                                        contextMenuBuilder: (context, editable) =>
                                            AppTextSelectionMenu.buildWithPaste(
                                              context,
                                              editable,
                                              () => unawaited(
                                                _pasteImage(context),
                                              ),
                                            ),
                                        controller: input,
                                        selectionWidthStyle:
                                            ui.BoxWidthStyle.tight,
                                        focusNode: focusNode,
                                        minLines: 2,
                                        maxLines: null,
                                        scrollPhysics:
                                            const NeverScrollableScrollPhysics(),
                                        textInputAction:
                                            TextInputAction.newline,
                                        cursorColor: theme.basePrimary,
                                        style: TextStyle(
                                          color: theme.textColorPrimary,
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: assistant.busy
                                              ? l10n.aiGuidanceHint
                                              : l10n.aiInputHint,
                                          hintStyle: TextStyle(
                                            color: theme.textColorTertiary,
                                          ),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                          filled: false,
                                          isCollapsed: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return Row(
                              children: [
                                AppTooltip(
                                  message: l10n.aiAttachFile,
                                  child: Semantics(
                                    label: l10n.aiAttachFile,
                                    button: true,
                                    child: MenuItemSurface(
                                      key: const ValueKey(
                                        'ai-attach-file-button',
                                      ),
                                      theme: theme,
                                      onPressed: () => _pickImages(context),
                                      borderRadius: BorderRadius.circular(14),
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: Transform.rotate(
                                            angle: math.pi / 4,
                                            child: Icon(
                                              Symbols.attach_file_rounded,
                                              size: 16,
                                              color: theme.textColorSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                AssistantPermissionsButton(
                                  theme: theme,
                                  assistant: assistant,
                                  compact:
                                      constraints.maxWidth < 520 ||
                                      MediaQuery.textScalerOf(context)
                                              .scale(12) >
                                          16,
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: ModelSelector(
                                      theme: theme,
                                      assistant: assistant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: input,
                                  builder: (context, value, _) =>
                                      assistant.busy &&
                                          value.text.trim().isEmpty &&
                                          attachments.isEmpty
                                      ? _actionButton(
                                          theme: theme,
                                          key: const ValueKey('ai-stop-button'),
                                          label: l10n.aiStop,
                                          icon: Symbols.stop_rounded,
                                          size: 30,
                                          onPressed: assistant.stopGeneration,
                                        )
                                      : assistant.canContinue &&
                                            value.text.trim().isEmpty &&
                                            attachments.isEmpty
                                      ? _actionButton(
                                          theme: theme,
                                          key: const ValueKey(
                                            'ai-continue-button',
                                          ),
                                          label: l10n.aiContinue,
                                          icon: Symbols.play_arrow_rounded,
                                          size: 30,
                                          onPressed: () => onSend(false),
                                        )
                                      : _actionButton(
                                          theme: theme,
                                          key: const ValueKey('ai-send-button'),
                                          label: assistant.busy
                                              ? l10n.aiGuideTurn
                                              : ready
                                              ? l10n.aiSend
                                              : l10n.aiSetupAction,
                                          icon: Symbols.arrow_upward_rounded,
                                          size: 30,
                                          onPressed:
                                              !assistant.canSendMessage ||
                                                  value.text.trim().isEmpty &&
                                                      attachments.isEmpty
                                              ? null
                                              : () => onSend(false),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ComposerMetrics(
          theme: theme,
          assistant: assistant,
          onManageContext: onManageContext,
        ),
      ],
    );
  }
}

class _ComposerMetrics extends StatelessWidget {
  const _ComposerMetrics({
    required this.theme,
    required this.assistant,
    required this.onManageContext,
  });

  final AppTheme theme;
  final AiAssistantProvider assistant;
  final VoidCallback? onManageContext;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: assistant,
    builder: (context, _) {
      final l10n = context.l10n;
      final cacheUsage = assistant.latestCacheUsage;
      final rate = assistant.latestReplySpeed;
      final compacting = assistant.compacting.value;
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 8, top: 5),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppTooltip(
              key: const ValueKey('ai-output-speed-metric'),
              message: l10n.aiAverageOutputSpeedHint,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.speed_rounded,
                      size: 14,
                      color: theme.textColorTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l10n.aiAverageOutputSpeed,
                      style: TextStyle(
                        color: theme.textColorTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      rate == null
                          ? '—'
                          : l10n.aiOutputTokensPerSecond(
                              rate.toStringAsFixed(1),
                            ),
                      style: TextStyle(
                        color: theme.textColorSecondary,
                        fontSize: 12,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _ComposerMetric(
              key: const ValueKey('ai-cache-usage-metric'),
              theme: theme,
              label: l10n.aiCacheHit,
              ratio: cacheUsage?.cacheHitRatio,
              detailTitle: l10n.aiCacheUsageDetails,
              figures: switch (cacheUsage) {
                AiTokenUsage(:final cachedTokens?, :final inputTokens?) =>
                  '${_compactTokenCount(cachedTokens)} / ${_compactTokenCount(inputTokens)}',
                _ => null,
              },
              details: _CacheUsageDetails(theme: theme, usage: cacheUsage),
            ),
            _ComposerMetric(
              key: const ValueKey('ai-context-usage-metric'),
              theme: theme,
              label: compacting ? l10n.aiContextCompacting : l10n.aiContextUsed,
              busyHint: compacting ? l10n.aiCompactionCancelHint : null,
              ratio: assistant.contextUsageRatio,
              detailBarColor: UsageChartColors.green,
              contextMenuItems: (close) => [
                if (onManageContext case final manageContext?)
                  RightClickMenuItem(
                    key: const ValueKey('ai-context-menu-manage-chat'),
                    label: l10n.agentStorageManageContext,
                    icon: Symbols.chat_rounded,
                    onTap: () {
                      close();
                      manageContext();
                    },
                  ),
                RightClickMenuItem(
                  key: const ValueKey('ai-compaction-context-menu-action'),
                  label: compacting
                      ? l10n.aiCancelCompaction
                      : l10n.agentStorageCompactNow,
                  icon: compacting
                      ? Symbols.stop_rounded
                      : Symbols.compress_rounded,
                  isEnabled: !assistant.stopRequested,
                  onTap: () {
                    close();
                    if (compacting) {
                      assistant.cancelContextCompaction();
                    } else {
                      unawaited(_compactContext(context, assistant));
                    }
                  },
                ),
              ],
              detailTitle: l10n.aiContextUsageDetails,
              figures:
                  '~${_compactTokenCount(assistant.estimatedContextTokens)} / ${_compactTokenCount(assistant.contextBudgetTokens)}',
              summaryRatio: math.min(
                assistant.estimatedSummaryTokens /
                    assistant.contextBudgetTokens,
                assistant.contextUsageRatio,
              ),
              details: _ContextUsageDetails(theme: theme, assistant: assistant),
            ),
          ],
        ),
      );
    },
  );
}

String _compactTokenCount(int tokens) {
  for (final (scale, suffix) in const [
    (1000000000, 'B'),
    (1000000, 'M'),
    (1000, 'K'),
  ]) {
    if (tokens >= scale) {
      final number = (tokens / scale).toStringAsFixed(1);
      return '${number.endsWith('.0') ? number.substring(0, number.length - 2) : number}$suffix';
    }
  }
  return '$tokens';
}

class _ComposerMetric extends StatefulWidget {
  const _ComposerMetric({
    super.key,
    required this.theme,
    required this.label,
    required this.ratio,
    required this.detailTitle,
    required this.details,
    this.figures,
    this.summaryRatio = 0,
    this.detailBarColor,
    this.busyHint,
    this.contextMenuItems,
  });

  final AppTheme theme;
  final String label;
  final double? ratio;
  final String detailTitle;
  final Widget details;
  final String? figures;
  final double summaryRatio;
  final Color? detailBarColor;
  final String? busyHint;
  final List<RightClickMenuItem> Function(VoidCallback close)? contextMenuItems;

  @override
  State<_ComposerMetric> createState() => _ComposerMetricState();
}

class _ComposerMetricState extends State<_ComposerMetric> {
  final _detailsMenu = MenuController();
  final _contextMenu = RightClickMenuController();
  var _openRevision = 0;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final ratio = widget.ratio;
    final percentText = switch (ratio) {
      null => '—',
      > 0 && < 0.01 => '<1%',
      > 0.99 && < 1 => '>99%',
      _ => '${(ratio * 100).round()}%',
    };
    final reading = ratio == null
        ? context.l10n.aiCacheNotReported
        : percentText;
    final busy = widget.busyHint != null;
    final semanticLabel = busy ? widget.label : '${widget.label}: $reading';
    final detailsAnchor = RawMenuAnchor(
      controller: _detailsMenu,
      onOpen: () {
        if (mounted) setState(() => _openRevision++);
      },
      overlayBuilder: (context, info) {
        const inset = 8.0;
        final size = info.overlaySize;
        final anchor = info.anchorRect;
        final width = math.min(300.0, math.max(0.0, size.width - inset * 2));
        final left = (anchor.right - width)
            .clamp(inset, math.max(inset, size.width - width - inset))
            .toDouble();
        final above = math.max(0.0, anchor.top - inset * 2);
        final below = math.max(0.0, size.height - anchor.bottom - inset * 2);
        final opensAbove = above >= 190 || above >= below;
        return Positioned(
          left: left,
          width: width,
          top: opensAbove ? null : anchor.bottom + inset,
          bottom: opensAbove ? size.height - anchor.top + inset : null,
          child: TapRegion(
            groupId: info.tapRegionGroupId,
            onTapOutside: (_) => _detailsMenu.close(),
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event.logicalKey != LogicalKeyboardKey.escape) {
                  return KeyEventResult.ignored;
                }
                if (event is KeyDownEvent) _detailsMenu.close();
                return KeyEventResult.handled;
              },
              child: PopupMenuTransition(
                key: ValueKey(_openRevision),
                alignment: opensAbove
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                child: PopupMenuSurface(
                  key: ValueKey('${widget.key}-details'),
                  theme: theme,
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: opensAbove ? above : below,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: _MetricDetailsFrame(
                        theme: theme,
                        title: widget.detailTitle,
                        reading: percentText,
                        figures: widget.figures,
                        ratio: ratio,
                        summaryRatio: widget.summaryRatio,
                        barColor: widget.detailBarColor ?? theme.basePrimary,
                        child: widget.details,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      builder: (context, controller, _) => AppTooltip(
        message: widget.busyHint ?? semanticLabel,
        child: Semantics(
          label: semanticLabel,
          hint: widget.busyHint,
          button: true,
          expanded: controller.isOpen,
          child: MenuItemSurface(
            theme: theme,
            backgroundColor: theme.secondaryTextHoverColor.withValues(alpha: 0),
            surfaceColor: theme.secondary,
            hoverColor: theme.secondaryTextHoverColor,
            borderRadius: BorderRadius.circular(8),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      value: busy ? null : ratio ?? 0,
                      strokeWidth: 2,
                      backgroundColor: theme.textColorTertiary.withValues(
                        alpha: 0.28,
                      ),
                      color: theme.basePrimary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: theme.textColorTertiary,
                      fontSize: 12,
                    ),
                  ),
                  if (!busy) ...[
                    const SizedBox(width: 4),
                    Text(
                      percentText,
                      style: TextStyle(
                        color: theme.textColorSecondary,
                        fontSize: 12,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
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
    final trigger = Semantics(
      container: true,
      explicitChildNodes: true,
      child: detailsAnchor,
    );
    final menuItems = widget.contextMenuItems;
    if (menuItems == null) return trigger;
    return RightClickMenuBuilder.buildMenuAnchor(
      context: context,
      controller: _contextMenu,
      menuItems: menuItems(_contextMenu.close),
      theme: theme,
      fitWidthToItems: true,
      onSecondaryTap: _detailsMenu.close,
      child: trigger,
    );
  }

  @override
  void dispose() {
    _contextMenu.close();
    super.dispose();
  }
}

class _MetricDetailsFrame extends StatelessWidget {
  const _MetricDetailsFrame({
    required this.theme,
    required this.title,
    required this.reading,
    required this.figures,
    required this.ratio,
    required this.summaryRatio,
    required this.barColor,
    required this.child,
  });

  final AppTheme theme;
  final String title;
  final String reading;
  final String? figures;
  final double? ratio;
  final double summaryRatio;
  final Widget child;
  final Color barColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OverflowBar(
        spacing: 8,
        overflowSpacing: 2,
        alignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$title  $reading',
            style: TextStyle(
              color: theme.textColorPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (figures != null)
            Text(
              figures!,
              style: TextStyle(color: theme.textColorSecondary, fontSize: 12),
            ),
        ],
      ),
      const SizedBox(height: 7),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            LinearProgressIndicator(
              value: ratio ?? 0,
              minHeight: 4,
              color: barColor,
              backgroundColor: theme.dividerColor,
            ),
            if (summaryRatio > 0)
              LinearProgressIndicator(
                value: summaryRatio,
                minHeight: 4,
                color: UsageChartColors.blue,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _CacheUsageDetails extends StatelessWidget {
  const _CacheUsageDetails({required this.theme, required this.usage});

  final AppTheme theme;
  final AiTokenUsage? usage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <(String, int?, Color?)>[
      (l10n.aiCacheInputTokens, usage?.inputTokens, null),
      (l10n.aiCacheCachedTokens, usage?.cachedTokens, theme.basePrimary),
      (l10n.aiCacheUncachedTokens, usage?.uncachedTokens, theme.dividerColor),
      (l10n.aiCacheOutputTokens, usage?.outputTokens, null),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usage?.cacheHitRatio == null)
          Text(
            l10n.aiCacheNotReportedHint,
            style: TextStyle(color: theme.textColorSecondary, fontSize: 12),
          ),
        for (final (label, value, swatch) in rows)
          if (value case final count?)
            _MetricDetailRow(
              theme: theme,
              label: label,
              value: l10n.aiMetricTokenCount(count),
              swatch: swatch,
            ),
      ],
    );
  }
}

class _ContextUsageDetails extends StatelessWidget {
  const _ContextUsageDetails({required this.theme, required this.assistant});

  final AppTheme theme;
  final AiAssistantProvider assistant;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lastCompaction = assistant.lastCompaction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricDetailRow(
          theme: theme,
          label: l10n.aiContextBudgetUsage,
          value: l10n.aiMetricTokenCount(assistant.estimatedContextTokens),
        ),
        _MetricDetailRow(
          theme: theme,
          label: l10n.aiContextChatHistory,
          value: l10n.aiMetricTokenCount(
            assistant.estimatedContextTokens - assistant.estimatedSummaryTokens,
          ),
          swatch: UsageChartColors.green,
        ),
        _MetricDetailRow(
          theme: theme,
          label: l10n.aiContextSummaryUsage,
          value: l10n.aiMetricTokenCount(assistant.estimatedSummaryTokens),
          swatch: UsageChartColors.blue,
        ),
        _MetricDetailRow(
          theme: theme,
          label: l10n.agentStorageContextBudget,
          value: l10n.aiMetricTokenCount(assistant.contextBudgetTokens),
        ),
        _MetricDetailRow(
          theme: theme,
          label: l10n.aiContextCompactionThreshold,
          value: l10n.aiMetricTokenCount(
            assistant.contextCompactionThresholdTokens,
          ),
        ),
        _MetricDetailRow(
          theme: theme,
          label: l10n.aiContextLastCompaction,
          value: lastCompaction == null
              ? l10n.aiContextNoCompaction
              : '${_compactTokenCount(lastCompaction.before)} → ${_compactTokenCount(lastCompaction.after)}',
        ),
      ],
    );
  }
}

class _MetricDetailRow extends StatelessWidget {
  const _MetricDetailRow({
    required this.theme,
    required this.label,
    required this.value,
    this.swatch,
  });

  final AppTheme theme;
  final String label;
  final String value;
  final Color? swatch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: OverflowBar(
      spacing: 8,
      overflowSpacing: 2,
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatch case final color?) ...[
              SizedBox.square(
                dimension: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: theme.textColorTertiary, fontSize: 12),
              ),
            ),
          ],
        ),
        Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(color: theme.textColorSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}

Future<void> _compactContext(
  BuildContext context,
  AiAssistantProvider assistant,
) async {
  final l10n = context.l10n;
  final before = assistant.estimatedContextTokens;
  try {
    final outcome = await assistant.compactContext();
    if (!context.mounted) return;
    final message = switch (outcome) {
      AiContextCompactionOutcome.compacted => l10n.agentStorageCompactResult(
        before,
        assistant.estimatedContextTokens,
      ),
      AiContextCompactionOutcome.insufficientHistory =>
        l10n.agentStorageCompactTooShort,
      AiContextCompactionOutcome.unavailableModel =>
        l10n.agentStorageCompactUnavailable,
      AiContextCompactionOutcome.busy => l10n.aiContextCompactionBusy,
      AiContextCompactionOutcome.cancelled => l10n.agentStorageCompactCancelled,
      AiContextCompactionOutcome.unchanged => l10n.agentStorageCompactUnchanged,
    };
    showAppNotice(ScaffoldMessenger.of(context), message);
  } catch (_) {
    if (context.mounted) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        l10n.agentStorageCompactFailed,
      );
    }
  }
}

/// 待发送队列与附件共用后层，编辑时将内容取回主输入框。
class _PendingGuidance extends StatefulWidget {
  const _PendingGuidance({
    this.bottomInset = 7,
    required this.theme,
    required this.assistant,
    required this.onEdit,
  });
  final double bottomInset;
  final ValueChanged<String> onEdit;
  final AppTheme theme;
  final AiAssistantProvider assistant;

  @override
  State<_PendingGuidance> createState() => _PendingGuidanceState();
}

class _PendingGuidanceState extends State<_PendingGuidance> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final assistant = widget.assistant;
    return Padding(
      key: const ValueKey('ai-pending-guidance'),
      padding: EdgeInsets.only(top: 7, bottom: widget.bottomInset),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 5),
              child: Text(
                '${context.l10n.aiGuidancePending} (${assistant.pendingGuidance.length})',
                key: const ValueKey('ai-pending-guidance-heading'),
                style: TextStyle(color: theme.textColorTertiary, fontSize: 11),
              ),
            ),
            Flexible(
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(context).copyWith(
                  crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset - 4,
                ),
                child: Scrollbar(
                  controller: _scroll,
                  child: ScrollConfiguration(
                    behavior: const AppScrollBehavior(scrollbars: false),
                    child: SingleChildScrollView(
                      key: const ValueKey('ai-pending-guidance-scroll'),
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        spacing: 5,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final message in assistant.pendingGuidance)
                            _QueuedMessage(
                              key: ValueKey(message.id),
                              message: message,
                              theme: theme,
                              assistant: assistant,
                              onEdit: widget.onEdit,
                            ),
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
    );
  }
}

class _QueuedMessage extends StatefulWidget {
  const _QueuedMessage({
    super.key,
    required this.message,
    required this.theme,
    required this.assistant,
    required this.onEdit,
  });
  final ValueChanged<String> onEdit;
  final AiMessage message;
  final AppTheme theme;
  final AiAssistantProvider assistant;

  @override
  State<_QueuedMessage> createState() => _QueuedMessageState();
}

class _QueuedMessageState extends State<_QueuedMessage> {
  Widget _button(
    String action,
    String label,
    IconData icon,
    VoidCallback? onPressed,
  ) {
    final theme = widget.theme;
    final background = theme.assistantQueueSurfaceColor;
    return AppTooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: TitleBarIconButton(
          key: ValueKey('ai-$action-guidance-${widget.message.id}'),
          theme: theme,
          isFocused: true,
          icon: icon,
          size: 25,
          iconSize: 15,
          backgroundColor: Colors.transparent,
          surfaceColor: background,
          hoverColor: theme.interactionHoverColor(background),
          onPressed: onPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final assistant = widget.assistant;
    final waitingToSteer = assistant.pendingTurnSteerId == message.id;
    final theme = widget.theme;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.assistantQueueSurfaceColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 5, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.toolName == 'agent_message')
                      AgentMessageSource(message: message, theme: theme),
                    if (message.attachments.isNotEmpty)
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final attachment in message.attachments)
                            ImageClipboardMenu(
                              bytes: attachment.bytes,
                              theme: theme,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  attachment.bytes,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox(width: 64, height: 64),
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (message.attachments.isNotEmpty &&
                        message.content.isNotEmpty)
                      const SizedBox(height: 8),
                    if (message.content.isNotEmpty)
                      Text(
                        message.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColorPrimary,
                          fontSize: 13,
                        ),
                      ),
                    if (waitingToSteer)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.aiGuidanceAwaitingBoundary,
                          style: TextStyle(
                            color: theme.textColorSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _button(
                'steer',
                l10n.aiSendPendingGuidance,
                Symbols.arrow_upward_rounded,
                assistant.canGuideNow
                    ? () => unawaited(assistant.steerPendingMessage(message.id))
                    : null,
              ),
              _button(
                'edit',
                l10n.aiEditQueuedMessage,
                Symbols.edit_rounded,
                assistant.canGuideNow ? () => widget.onEdit(message.id) : null,
              ),
              _button(
                'remove',
                l10n.aiRemoveGuidance,
                Symbols.close_rounded,
                assistant.canRemovePendingGuidance(message.id)
                    ? () => assistant.removePendingGuidance(message.id)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 附件在后层自动换行，超过两行后独立滚动，不挤压正文编辑区。
class _ComposerAttachments extends StatefulWidget {
  const _ComposerAttachments({
    this.topInset = 7,
    required this.attachments,
    required this.theme,
    required this.onAttachmentsChanged,
  });

  final double topInset;
  final List<AiImageAttachment> attachments;
  final AppTheme theme;
  final ValueChanged<List<AiImageAttachment>> onAttachmentsChanged;

  @override
  State<_ComposerAttachments> createState() => _ComposerAttachmentsState();
}

class _ComposerAttachmentsState extends State<_ComposerAttachments> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      const horizontalInset = 12.0;
      final width = math.max(0.0, constraints.maxWidth - horizontalInset * 2);
      // 最多十列；窄窗口按可读缩略图宽度减少列数。
      final columns = math.min(
        10,
        math.max(1, ((width + gap) / (48 + gap)).floor()),
      );
      final size = math.max(0.0, (width - gap * (columns - 1)) / columns);
      // 上下留白放在滚动区域外，滚动到中段时也不会消失。
      return Padding(
        padding: EdgeInsets.only(top: widget.topInset, bottom: 7),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size * 2 + gap),
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset - 4,
            ),
            child: Scrollbar(
              key: const ValueKey('ai-attachments-scrollbar'),
              controller: _scroll,
              child: ScrollConfiguration(
                behavior: const AppScrollBehavior(scrollbars: false),
                child: SingleChildScrollView(
                  key: const ValueKey('ai-attachments-scroll'),
                  controller: _scroll,
                  primary: false,
                  // 左右对称留白，右侧滚动条也位于这段留白内。
                  padding: const EdgeInsets.symmetric(
                    horizontal: horizontalInset,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (
                        var index = 0;
                        index < widget.attachments.length;
                        index++
                      )
                        _AttachmentThumbnail(
                          size: size,
                          attachment: widget.attachments[index],
                          theme: widget.theme,
                          onRemove: () {
                            final updated = [...widget.attachments]
                              ..removeAt(index);
                            widget.onAttachmentsChanged(updated);
                          },
                        ),
                    ],
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

class _AttachmentThumbnail extends StatefulWidget {
  const _AttachmentThumbnail({
    required this.attachment,
    required this.size,
    required this.theme,
    required this.onRemove,
  });

  final double size;
  final AiImageAttachment attachment;
  final AppTheme theme;
  final VoidCallback onRemove;

  @override
  State<_AttachmentThumbnail> createState() => _AttachmentThumbnailState();
}

class _AttachmentThumbnailState extends State<_AttachmentThumbnail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ImageClipboardMenu(
            bytes: widget.attachment.bytes,
            theme: widget.theme,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                widget.attachment.bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: IgnorePointer(
              ignoring: !_hovered,
              child: AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: AppTooltip(
                  message: context.l10n.aiRemoveImage,
                  child: TitleBarIconButton(
                    key: const ValueKey('ai-remove-image-button'),
                    theme: widget.theme,
                    isFocused: true,
                    icon: Symbols.close_rounded,
                    size: 18,
                    iconSize: 12,
                    backgroundColor: widget.theme.primary,
                    hoverColor: widget.theme.secondaryTextHoverColor,
                    iconColor: widget.theme.textColorPrimary,
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
