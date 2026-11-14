/*
 * @Description: 渲染聊天 Markdown 正文、消息复制操作与固定发送时间。
 * @Author: LILYGO_L
 * @Date: 2026-11-09 15:26:28
 * @LastEditTime: 2026-11-13 17:42:49
 */

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/empty_line_selection.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../data/message_link_opener.dart';
import '../../domain/agent_link.dart';
import '../../domain/models.dart';
import 'code_block.dart';
import 'error_text.dart';
import 'task_navigation_scope.dart';

class ChatMessageBody extends StatefulWidget {
  const ChatMessageBody({
    super.key,
    required this.message,
    required this.theme,
    this.useParentSelectionArea = false,
    this.linkOpener = const MessageLinkOpener(),
  });

  final AiMessage message;
  final AppTheme theme;
  final bool useParentSelectionArea;
  final MessageLinkOpener linkOpener;

  @override
  State<ChatMessageBody> createState() => _ChatMessageBodyState();
}

class _ChatMessageBodyState extends State<ChatMessageBody> {
  late final _selectionFocus = FocusNode(
    skipTraversal: widget.message.role == 'user',
  );

  AiMessage get message => widget.message;
  AppTheme get theme => widget.theme;

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  Future<void> _openLink(BuildContext context, String? href) async {
    if (isAgentLink(href)) {
      final id = agentIdFromLink(href);
      final navigation = TaskNavigationScope.maybeOf(context);
      if (id == null || navigation == null) {
        showAppNotice(
          ScaffoldMessenger.of(context),
          context.l10n.aiTaskLinkUnavailable,
        );
      } else {
        navigation.openTask(id);
      }
      return;
    }
    final opened = await widget.linkOpener.open(href, message: message);
    if (!opened && context.mounted) {
      showAppNotice(
        ScaffoldMessenger.of(context),
        context.l10n.aiOpenLinkFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    onTapOutside: (event) {
      if (event.buttons == kPrimaryMouseButton && _selectionFocus.hasFocus) {
        _selectionFocus.unfocus();
      }
    },
    child: EmptyLineSelection(child: _buildContent(context)),
  );

  Widget _buildContent(BuildContext context) {
    final text = TextStyle(
      color: theme.textColorPrimary,
      fontSize: 14,
      height: 1.5,
    );
    if (message.role == 'user') {
      if (widget.useParentSelectionArea) {
        return Text(message.content, style: text);
      }
      return SelectableText(
        message.content,
        focusNode: _selectionFocus,
        selectionWidthStyle: ui.BoxWidthStyle.tight,
        contextMenuBuilder: AppTextSelectionMenu.build,
        style: text,
      );
    }
    final codeBuilder = _CodeElementBuilder(theme);
    final markdown = MarkdownBody(
      data: message.content,
      builders: {
        'code': codeBuilder,
        'pre': _CodeBlockBuilder(theme, codeBuilder),
      },
      onTapLink: (_, href, _) => unawaited(_openLink(context, href)),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: text,
        a: text.copyWith(
          color: theme.basePrimary,
          decoration: TextDecoration.underline,
          decorationColor: theme.basePrimary,
        ),
        h1: text.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
        h2: text.copyWith(fontSize: 21, fontWeight: FontWeight.w600),
        h3: text.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        h4: text.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        h5: text.copyWith(fontWeight: FontWeight.w600),
        h6: text.copyWith(fontWeight: FontWeight.w600),
        listBullet: text,
        em: const TextStyle(fontStyle: FontStyle.italic),
        strong: const TextStyle(fontWeight: FontWeight.w600),
        code: text.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: theme.primary,
        ),
        blockquote: text.copyWith(color: theme.textColorSecondary),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.dividerColor, width: 3)),
        ),
        codeblockDecoration: const BoxDecoration(),
        codeblockPadding: const EdgeInsets.all(12),
        tableHead: text.copyWith(fontWeight: FontWeight.w600),
        tableBody: text,
        tableColumnWidth: const FlexColumnWidth(),
        tableBorder: TableBorder.all(color: theme.dividerColor),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
      ),
    );
    if (widget.useParentSelectionArea) return markdown;
    return SelectionArea(
      focusNode: _selectionFocus,
      contextMenuBuilder: AppTextSelectionMenu.buildRegion,
      child: markdown,
    );
  }
}

class ChatMessageActions extends StatefulWidget {
  const ChatMessageActions({
    super.key,
    required this.message,
    required this.theme,
  });

  final AiMessage message;
  final AppTheme theme;

  @override
  State<ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<ChatMessageActions> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = widget.theme;
    final l10n = context.l10n;
    final text = message.content.isNotEmpty
        ? message.content
        : message.requestError == null
        ? ''
        : aiErrorText(l10n, message.requestError!);
    final label = _copied ? l10n.aiMessageCopied : l10n.aiCopyMessage;
    final copyButton = AppTooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: TitleBarIconButton(
          key: ValueKey('ai-copy-message-${message.id}'),
          onPressed: text.isEmpty ? null : () => _copy(text),
          isFocused: true,
          theme: theme,
          icon: _copied ? Symbols.check_rounded : Symbols.content_copy_rounded,
          size: 25,
          iconSize: 15,
          backgroundColor: Colors.transparent,
          surfaceColor: theme.secondary,
          hoverColor: theme.interactionHoverColor(theme.secondary),
          iconColor: theme.textColorSecondary,
        ),
      ),
    );
    final timestamp = message.createdAt == null
        ? null
        : Flexible(
            child: Text(
              DateFormat(
                'yyyy.MM.dd HH:mm:ss',
              ).format(message.createdAt!.toLocal()),
              key: ValueKey('ai-message-time-${message.id}'),
              style: TextStyle(color: theme.textColorTertiary, fontSize: 12),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.role == 'user'
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (message.role == 'user') ...[
            if (timestamp != null) ...[timestamp, const SizedBox(width: 8)],
            copyButton,
          ] else ...[
            copyButton,
            if (timestamp != null) ...[const SizedBox(width: 8), timestamp],
          ],
        ],
      ),
    );
  }
}

/// 区分行内代码与代码块，避免把代码块拆成行内标签。
class _CodeElementBuilder extends MarkdownElementBuilder {
  _CodeElementBuilder(this.theme);
  final AppTheme theme;
  bool insideBlock = false;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (insideBlock) return null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          element.textContent,
          style: TextStyle(
            fontFamily: 'monospace',
            color: theme.textColorPrimary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.theme, this.inlineBuilder);
  final AppTheme theme;
  final _CodeElementBuilder inlineBuilder;

  @override
  void visitElementBefore(md.Element element) =>
      inlineBuilder.insideBlock = true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    inlineBuilder.insideBlock = false;
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final language =
        code?.attributes['class']?.replaceFirst('language-', '') ?? '';
    return ChatCodeBlock(
      text: code?.textContent ?? element.textContent,
      language: language,
      theme: theme,
    );
  }
}
