/*
 * @Description: 构建双层 AI 输入区，承载附件与待处理引导并提供键盘发送和模型选择。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 11:07:40
 * @LastEditTime: 2026-11-12 11:40:05
 */

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/clipboard/image_clipboard.dart';
import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/image_clipboard_menu.dart';
import '../../../../core/widgets/menu_item_surface.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../../../core/widgets/popup_menu_transition.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'approval_panel.dart';
import 'model_selector.dart';
import 'permissions_button.dart';

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
    final value = input.value;
    input.value = value.copyWith(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
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
    return PopupMenuPageTransition(
      child: request != null
          ? AssistantApprovalPanel(
              key: ValueKey(request.id),
              request: request,
              theme: theme,
              inputFocus: focusNode,
              onResolve: (approve) =>
                  assistant.resolveTool(request.id, approve: approve),
            )
          : _buildInput(context),
    );
  }

  Widget _buildInput(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
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
                        child: Scrollbar(
                          key: const ValueKey('ai-input-scrollbar'),
                          controller: scrollController,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 14),
                            child: ScrollConfiguration(
                              behavior: const AppScrollBehavior(
                                scrollbars: false,
                              ),
                              child: TextField(
                                key: const ValueKey('ai-message-input'),
                                contextMenuBuilder: (context, editable) =>
                                    AppTextSelectionMenu.buildWithPaste(
                                      context,
                                      editable,
                                      () => unawaited(_pasteImage(context)),
                                    ),
                                controller: input,
                                scrollController: scrollController,
                                selectionWidthStyle: ui.BoxWidthStyle.tight,
                                focusNode: focusNode,
                                minLines: 2,
                                maxLines: 8,
                                textInputAction: TextInputAction.newline,
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
                                  key: const ValueKey('ai-attach-file-button'),
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
                                  MediaQuery.textScalerOf(context).scale(12) >
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
                                      key: const ValueKey('ai-continue-button'),
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
    );
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
                  ],
                ),
              ),
              _button(
                'steer',
                l10n.aiSendPendingGuidance,
                Symbols.arrow_upward_rounded,
                assistant.canGuideNow
                    ? () => unawaited(assistant.guidePendingMessage(message.id))
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
                () => assistant.removePendingGuidance(message.id),
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
