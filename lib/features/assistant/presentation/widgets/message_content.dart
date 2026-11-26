/*
 * @Description: 渲染聊天 Markdown 正文、消息复制操作与固定发送时间。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/context_menu/text_selection_menu.dart';
import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_notice.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/empty_line_selection.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import '../../../speech/domain/speech_reply_text.dart';
import '../../../speech/presentation/speech_icon_button.dart';
import '../../../speech/presentation/speech_labels.dart';
import '../../../speech/state/speech_provider.dart';
import '../../data/message_link_opener.dart';
import '../../domain/agent_link.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'chat_content_window.dart';
import 'chat_message_list.dart';
import 'chat_text_segments.dart';
import 'code_block.dart';
import 'task_navigation_scope.dart';

class ChatMessageBody extends StatefulWidget {
  const ChatMessageBody({
    super.key,
    required this.message,
    required this.theme,
    this.useParentSelectionArea = false,
    this.allowExternalContent = true,
    this.linkOpener = const MessageLinkOpener(),
  });

  final AiMessage message;
  final AppTheme theme;
  final bool useParentSelectionArea;
  final bool allowExternalContent;
  final MessageLinkOpener linkOpener;

  static bool usesContentSegments(AiMessage message) =>
      message.content.length >= 2048;

  @override
  State<ChatMessageBody> createState() => _ChatMessageBodyState();
}

class _ChatMessageBodyState extends State<ChatMessageBody> {
  static final _htmlDocumentStart = RegExp(
    r'^\s*(?:<!doctype\s+html\b|<html(?:\s|>))',
    caseSensitive: false,
  );

  late final _selectionFocus = FocusNode(
    skipTraversal: widget.message.role == 'user',
  );

  AiMessage get message => widget.message;
  AppTheme get theme => widget.theme;
  MarkdownBody? _markdown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdown = null;
  }

  @override
  void didUpdateWidget(ChatMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (message.id != oldWidget.message.id ||
        message.content != oldWidget.message.content ||
        message.role != oldWidget.message.role ||
        theme != oldWidget.theme ||
        widget.useParentSelectionArea != oldWidget.useParentSelectionArea ||
        widget.allowExternalContent != oldWidget.allowExternalContent) {
      _markdown = null;
    }
  }

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
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    Theme.of(context);
    MediaQuery.textScalerOf(context);
    final text = TextStyle(
      color: theme.textColorPrimary,
      fontSize: 14,
      height: 1.5,
    );
    if (message.role == 'user') {
      if (widget.useParentSelectionArea) {
        return _ChatUserText(
          messageId: message.id,
          content: message.content,
          style: text,
        );
      }
      return EmptyLineSelection(
        child: SelectableText(
          message.content,
          focusNode: _selectionFocus,
          selectionWidthStyle: ui.BoxWidthStyle.tight,
          contextMenuBuilder: AppTextSelectionMenu.build,
          style: text,
        ),
      );
    }
    final contentText = message.role == 'assistant'
        ? parseSpeechReply(message.content).body
        : message.content;
    final body = _htmlDocumentStart.hasMatch(contentText)
        ? ChatCodeBlock(
            key: PageStorageKey('ai-message-html-${message.id}'),
            text: contentText,
            language: 'html',
            theme: theme,
          )
        : _markdown ??= _buildMarkdown(context, text, contentText);
    if (widget.useParentSelectionArea) return body;
    return SelectionArea(
      focusNode: _selectionFocus,
      contextMenuBuilder: AppTextSelectionMenu.buildRegion,
      child: EmptyLineSelection(child: body),
    );
  }

  MarkdownBody _buildMarkdown(
    BuildContext context,
    TextStyle text,
    String data,
  ) {
    final codeBuilder = _CodeElementBuilder(theme);
    final markdown = MarkdownBody(
      data: data,
      builders: {
        'code': codeBuilder,
        'pre': _CodeBlockBuilder(theme, codeBuilder, message.id),
      },
      onTapLink: widget.allowExternalContent
          ? (_, href, _) => unawaited(_openLink(context, href))
          : null,
      imageBuilder: widget.allowExternalContent
          ? null
          : (_, _, alt) => Text(alt ?? '', style: text),
      styleSheet: MarkdownStyleSheet(
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
    if (widget.useParentSelectionArea) {
      return ChatMarkdownBody(
        markdown,
        storageId: ('chat-markdown', message.id),
        streaming:
            message.status == AiResponseStatus.thinking ||
            message.status == AiResponseStatus.streaming,
      );
    }
    return markdown;
  }
}

class _ChatUserText extends StatefulWidget {
  const _ChatUserText({
    required this.messageId,
    required this.content,
    required this.style,
  });

  final String messageId;
  final String content;
  final TextStyle style;

  @override
  State<_ChatUserText> createState() => _ChatUserTextState();
}

class _ChatUserTextState extends State<_ChatUserText> {
  late List<String> _segments = splitChatTextForWindow(widget.content);

  @override
  void didUpdateWidget(_ChatUserText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _segments = splitChatTextForWindow(widget.content);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ChatContentScope.maybeOf(context) == null || _segments.length == 1) {
      return EmptyLineSelection(
        child: Text(widget.content, style: widget.style),
      );
    }
    return ChatContentWindow(
      childCount: _segments.length,
      revision: widget.content.hashCode,
      storageId: ('chat-text', widget.messageId),
      itemBuilder: (context, index) => RepaintBoundary(
        key: ValueKey('ai-user-text-${widget.messageId}-$index'),
        child: EmptyLineSelection(
          child: Text(
            index < _segments.length - 1 && _segments[index].endsWith('\r')
                ? _segments[index].substring(0, _segments[index].length - 1)
                : _segments[index],
            style: widget.style,
          ),
        ),
      ),
    );
  }
}

class ChatMarkdownBody extends MarkdownBody {
  ChatMarkdownBody(
    MarkdownBody body, {
    super.key,
    this.storageId,
    this.streaming = false,
  }) : super(
         data: body.data,
         selectable: body.selectable,
         builders: body.builders,
         onTapLink: body.onTapLink,
         styleSheet: body.styleSheet,
         blockSyntaxes: body.blockSyntaxes,
         inlineSyntaxes: body.inlineSyntaxes,
         extensionSet: body.extensionSet,
         syntaxHighlighter: body.syntaxHighlighter,
         onSelectionChanged: body.onSelectionChanged,
         onTapText: body.onTapText,
         contextMenuBuilder: body.contextMenuBuilder,
         imageDirectory: body.imageDirectory,
         imageBuilder: body.imageBuilder,
         checkboxBuilder: body.checkboxBuilder,
         bulletBuilder: body.bulletBuilder,
         paddingBuilders: body.paddingBuilders,
         listItemCrossAxisAlignment: body.listItemCrossAxisAlignment,
         shrinkWrap: body.shrinkWrap,
         fitContent: body.fitContent,
         softLineBreak: body.softLineBreak,
       );

  final Object? storageId;
  final bool streaming;

  static const _blocksPerGroup = 8;

  @override
  State<ChatMarkdownBody> createState() => _ChatMarkdownBodyState();

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    final blocks = children!;
    if (blocks.length <= _blocksPerGroup) {
      return RepaintBoundary(
        child: EmptyLineSelection(child: super.build(context, blocks)),
      );
    }
    return ChatMessageList(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var start = 0; start < blocks.length; start += _blocksPerGroup)
          RepaintBoundary(
            key: ValueKey('ai-markdown-paint-group-$start'),
            child: EmptyLineSelection(
              child: super.build(
                context,
                blocks.skip(start).take(_blocksPerGroup).toList(),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatMarkdownBodyState extends State<ChatMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<md.Node>? _nodes;
  List<Widget> _children = const [];
  final _recognizers = <GestureRecognizer>[];
  MarkdownStyleSheet? _styleSheet;
  List<({md.Node node, int codeIndex, bool leadingSpacing})> _segments =
      const [];
  bool _windowed = false;
  bool _needsBlockWindow = false;
  final _fallbackStorageId = Object();
  Timer? _streamParseTimer;
  bool _active = true;
  bool _streamParsePending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasWindowed = _windowed;
    _windowed = ChatContentScope.maybeOf(context) != null;
    _buildMarkdown(force: wasWindowed != _windowed);
  }

  @override
  void didUpdateWidget(ChatMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dataChanged = widget.data != oldWidget.data;
    final syntaxChanged =
        !listEquals(widget.blockSyntaxes, oldWidget.blockSyntaxes) ||
        !listEquals(widget.inlineSyntaxes, oldWidget.inlineSyntaxes) ||
        widget.extensionSet != oldWidget.extensionSet;
    if (dataChanged && widget.streaming && oldWidget.streaming) {
      // Crossing the windowing threshold must be applied in this frame so a
      // reader keeps the existing anchor instead of briefly losing its
      // virtualized content window.
      if (oldWidget.data.length < 2048 && widget.data.length >= 2048) {
        _streamParseTimer?.cancel();
        _streamParseTimer = null;
        _nodes = null;
        _segments = const [];
        _buildMarkdown(force: true);
      } else {
        _scheduleStreamingParse();
      }
    } else {
      _streamParseTimer?.cancel();
      _streamParseTimer = null;
      _streamParsePending = false;
      if (dataChanged ||
          widget.streaming != oldWidget.streaming ||
          syntaxChanged) {
        _nodes = null;
        _segments = const [];
      }
    }
    if (_nodes == null ||
        widget.styleSheet != oldWidget.styleSheet ||
        !mapEquals(widget.builders, oldWidget.builders) ||
        !mapEquals(widget.paddingBuilders, oldWidget.paddingBuilders) ||
        widget.selectable != oldWidget.selectable ||
        widget.syntaxHighlighter != oldWidget.syntaxHighlighter ||
        widget.imageDirectory != oldWidget.imageDirectory ||
        widget.imageBuilder != oldWidget.imageBuilder ||
        widget.checkboxBuilder != oldWidget.checkboxBuilder ||
        widget.bulletBuilder != oldWidget.bulletBuilder ||
        widget.fitContent != oldWidget.fitContent ||
        widget.listItemCrossAxisAlignment !=
            oldWidget.listItemCrossAxisAlignment ||
        widget.onSelectionChanged != oldWidget.onSelectionChanged ||
        widget.onTapText != oldWidget.onTapText ||
        widget.contextMenuBuilder != oldWidget.contextMenuBuilder ||
        widget.softLineBreak != oldWidget.softLineBreak) {
      _buildMarkdown(force: true);
    }
  }

  void _scheduleStreamingParse() {
    if (!_active) {
      _streamParsePending = true;
      return;
    }
    if (_streamParseTimer != null) return;
    final delay = widget.data.length >= 32768
        ? const Duration(milliseconds: 200)
        : widget.data.length >= 8192
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 50);
    _streamParseTimer = Timer(delay, () {
      _streamParseTimer = null;
      if (!mounted || !_active || !widget.streaming) {
        _streamParsePending = !_active && widget.streaming;
        return;
      }
      _nodes = null;
      _segments = const [];
      _buildMarkdown(force: true);
      setState(() {});
    });
  }

  void _buildMarkdown({bool force = false}) {
    final styleSheet = _markdownDefaults(context).merge(widget.styleSheet);
    if (!force &&
        _nodes != null &&
        styleSheet == _styleSheet &&
        (_windowed || _children.isNotEmpty)) {
      return;
    }
    if (_nodes == null) {
      late final List<md.Node> nodes;
      try {
        nodes = md.Document(
          blockSyntaxes: widget.blockSyntaxes,
          inlineSyntaxes: widget.inlineSyntaxes,
          extensionSet: widget.extensionSet ?? md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parseLines(const LineSplitter().convert(widget.data));
      } catch (_) {
        // A partial stream must remain renderable even when a third-party
        // Markdown extension rejects an incomplete document.
        nodes = [
          md.Element('p', [md.Text(widget.data)]),
        ];
      }
      _nodes = nodes;
      _needsBlockWindow =
          widget.data.length >= 2048 ||
          nodes.length > ChatContentWindowState.initialChildren ||
          nodes.whereType<md.Element>().any(
            (node) => _isSegmentedList(node) || _codeBlockCount(node) > 0,
          );
    }
    _styleSheet = styleSheet;
    if (_windowed && _needsBlockWindow) {
      if (_segments.isEmpty) {
        var codeIndex = 0;
        final segments =
            <({md.Node node, int codeIndex, bool leadingSpacing})>[];
        for (final source in _nodes!) {
          for (final segment in _markdownSegments(
            source,
            hasPreviousBlock: segments.isNotEmpty,
          )) {
            final node = segment.node;
            if (node is md.Element &&
                node.tag == 'html' &&
                !widget.builders.containsKey('html')) {
              continue;
            }
            segments.add((
              node: node,
              codeIndex: codeIndex,
              leadingSpacing: segment.leadingSpacing,
            ));
            codeIndex += _codeBlockCount(node);
          }
        }
        _segments = segments;
      }
      _children = const [];
      _disposeRecognizers();
      return;
    }
    _disposeRecognizers();
    for (final builder in widget.builders.values) {
      if (builder is _CodeBlockBuilder) builder.reset();
    }
    _children = MarkdownBuilder(
      delegate: this,
      selectable: widget.selectable,
      styleSheet: styleSheet,
      imageDirectory: widget.imageDirectory,
      imageBuilder: widget.imageBuilder,
      checkboxBuilder: widget.checkboxBuilder,
      bulletBuilder: widget.bulletBuilder,
      builders: widget.builders,
      paddingBuilders: widget.paddingBuilders,
      fitContent: widget.fitContent,
      listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
      onSelectionChanged: widget.onSelectionChanged,
      onTapText: widget.onTapText,
      contextMenuBuilder: widget.contextMenuBuilder,
      softLineBreak: widget.softLineBreak,
    ).build(_nodes!);
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onTapLink?.call(text, href, title);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final source = code.replaceFirst(RegExp(r'\n$'), '');
    return widget.syntaxHighlighter?.format(source) ??
        TextSpan(style: styleSheet.code, text: source);
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void deactivate() {
    _active = false;
    _streamParsePending =
        _streamParsePending || (_streamParseTimer != null && widget.streaming);
    _streamParseTimer?.cancel();
    _streamParseTimer = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    if (_streamParsePending) {
      _streamParsePending = false;
      if (widget.streaming) _scheduleStreamingParse();
    }
  }

  @override
  void dispose() {
    _active = false;
    _streamParseTimer?.cancel();
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_windowed || !_needsBlockWindow) {
      return widget.build(context, _children);
    }
    return ChatContentWindow(
      childCount: _segments.length,
      revision: widget.data.hashCode,
      storageId: widget.storageId ?? widget.key ?? _fallbackStorageId,
      itemBuilder: (context, index) => _ChatMarkdownSegment(
        key: ValueKey('ai-markdown-segment-$index'),
        body: widget,
        node: _segments[index].node,
        codeIndex: _segments[index].codeIndex,
        leadingSpacing: _segments[index].leadingSpacing,
        styleSheet: _styleSheet!,
      ),
    );
  }
}

int _codeBlockCount(md.Node node) {
  if (node is! md.Element) return 0;
  return (node.tag == 'pre' ? 1 : 0) +
      (node.children ?? const <md.Node>[]).fold(
        0,
        (count, child) => count + _codeBlockCount(child),
      );
}

const _markdownListChunkSize = 8;

bool _isSegmentedList(md.Element node) =>
    (node.tag == 'ul' || node.tag == 'ol') &&
    (node.children?.length ?? 0) > _markdownListChunkSize;

Iterable<({md.Node node, bool leadingSpacing})> _markdownSegments(
  md.Node node, {
  required bool hasPreviousBlock,
}) sync* {
  if (node is md.Element && node.tag == 'p' && node.textContent.length > 2048) {
    final fragments = _splitMarkdownInlineChildren(
      node.children ?? const <md.Node>[],
    );
    for (var index = 0; index < fragments.length; index++) {
      final paragraph = md.Element('p', fragments[index].nodes)
        ..attributes.addAll(node.attributes);
      yield (node: paragraph, leadingSpacing: hasPreviousBlock && index == 0);
    }
    return;
  }
  if (node is md.Element && _isSegmentedList(node)) {
    final children = node.children!;
    final firstNumber = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    for (
      var start = 0;
      start < children.length;
      start += _markdownListChunkSize
    ) {
      final segment = md.Element(
        node.tag,
        children.skip(start).take(_markdownListChunkSize).toList(),
      )..attributes.addAll(node.attributes);
      if (node.tag == 'ol') {
        segment.attributes['start'] = '${firstNumber + start}';
      }
      yield (node: segment, leadingSpacing: hasPreviousBlock || start > 0);
    }
    return;
  }
  yield (node: node, leadingSpacing: hasPreviousBlock);
}

List<_MarkdownInlineFragment> _splitMarkdownInlineChildren(
  List<md.Node> nodes,
) {
  final fragments = <_MarkdownInlineFragment>[];
  var children = <md.Node>[];
  var length = 0;
  for (final node in nodes) {
    for (final fragment in _splitMarkdownInlineNode(node)) {
      if (length > 0 && length + fragment.length > 2048) {
        fragments.add(_MarkdownInlineFragment(children, length));
        children = <md.Node>[];
        length = 0;
      }
      children.addAll(fragment.nodes);
      length += fragment.length;
    }
  }
  if (children.isNotEmpty || fragments.isEmpty) {
    fragments.add(_MarkdownInlineFragment(children, length));
  }
  return fragments;
}

List<_MarkdownInlineFragment> _splitMarkdownInlineNode(md.Node node) {
  if (node is md.Text && node.text.length > 2048) {
    return [
      for (final text in splitChatTextForWindow(node.text))
        _MarkdownInlineFragment([md.Text(text)], text.length),
    ];
  }
  if (node is! md.Element || node.children == null || node.children!.isEmpty) {
    return [
      _MarkdownInlineFragment([node], node.textContent.length),
    ];
  }
  return [
    for (final fragment in _splitMarkdownInlineChildren(node.children!))
      _MarkdownInlineFragment([
        md.Element(node.tag, fragment.nodes)
          ..attributes.addAll(node.attributes),
      ], fragment.length),
  ];
}

class _MarkdownInlineFragment {
  const _MarkdownInlineFragment(this.nodes, this.length);

  final List<md.Node> nodes;
  final int length;
}

class _ChatMarkdownSegment extends StatefulWidget {
  const _ChatMarkdownSegment({
    super.key,
    required this.body,
    required this.node,
    required this.codeIndex,
    required this.leadingSpacing,
    required this.styleSheet,
  });

  final ChatMarkdownBody body;
  final md.Node node;
  final int codeIndex;
  final bool leadingSpacing;
  final MarkdownStyleSheet styleSheet;

  @override
  State<_ChatMarkdownSegment> createState() => _ChatMarkdownSegmentState();
}

class _ChatMarkdownSegmentState extends State<_ChatMarkdownSegment>
    implements MarkdownBuilderDelegate {
  final _recognizers = <GestureRecognizer>[];
  List<Widget>? _children;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disposeRecognizers();
    _children = null;
  }

  @override
  void didUpdateWidget(_ChatMarkdownSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.node, oldWidget.node) ||
        widget.styleSheet != oldWidget.styleSheet ||
        widget.codeIndex != oldWidget.codeIndex ||
        !identical(widget.body, oldWidget.body)) {
      _disposeRecognizers();
      _children = null;
    }
  }

  List<Widget> _buildChildren() {
    _disposeRecognizers();
    final body = widget.body;
    final builders = Map<String, MarkdownElementBuilder>.of(body.builders);
    final originalCode = builders['pre'];
    if (originalCode is _CodeBlockBuilder) {
      final inline = _CodeElementBuilder(originalCode.theme);
      builders['code'] = inline;
      builders['pre'] = _CodeBlockBuilder(
        originalCode.theme,
        inline,
        originalCode.messageId,
        initialIndex: widget.codeIndex,
      );
    }
    return MarkdownBuilder(
      delegate: this,
      selectable: body.selectable,
      styleSheet: widget.styleSheet,
      imageDirectory: body.imageDirectory,
      imageBuilder: body.imageBuilder,
      checkboxBuilder: body.checkboxBuilder,
      bulletBuilder: body.bulletBuilder,
      builders: builders,
      paddingBuilders: body.paddingBuilders,
      fitContent: body.fitContent,
      listItemCrossAxisAlignment: body.listItemCrossAxisAlignment,
      onSelectionChanged: body.onSelectionChanged,
      onTapText: body.onTapText,
      contextMenuBuilder: body.contextMenuBuilder,
      softLineBreak: body.softLineBreak,
    ).build([widget.node]);
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.body.onTapLink?.call(text, href, title);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final source = code.replaceFirst(RegExp(r'\n$'), '');
    return widget.body.syntaxHighlighter?.format(source) ??
        TextSpan(style: styleSheet.code, text: source);
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = _children ??= _buildChildren();
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(
        top: widget.leadingSpacing ? widget.styleSheet.blockSpacing ?? 0 : 0,
      ),
      child: widget.body.build(context, children),
    );
  }
}

MarkdownStyleSheet _markdownDefaults(BuildContext context) {
  final theme = Theme.of(context);
  final text = theme.textTheme.bodyMedium!;
  return MarkdownStyleSheet(
    a: const TextStyle(color: Colors.blue),
    p: text,
    pPadding: EdgeInsets.zero,
    code: text.copyWith(
      backgroundColor: theme.cardTheme.color,
      fontFamily: 'monospace',
      fontSize: text.fontSize! * 0.85,
    ),
    h1: theme.textTheme.headlineSmall,
    h1Padding: EdgeInsets.zero,
    h2: theme.textTheme.titleLarge,
    h2Padding: EdgeInsets.zero,
    h3: theme.textTheme.titleMedium,
    h3Padding: EdgeInsets.zero,
    h4: theme.textTheme.bodyLarge,
    h4Padding: EdgeInsets.zero,
    h5: theme.textTheme.bodyLarge,
    h5Padding: EdgeInsets.zero,
    h6: theme.textTheme.bodyLarge,
    h6Padding: EdgeInsets.zero,
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.bold),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    blockquote: text,
    img: text,
    checkbox: text.copyWith(color: theme.primaryColor),
    blockSpacing: 8,
    listIndent: 24,
    listBullet: text,
    listBulletPadding: const EdgeInsets.only(right: 4),
    tableHead: const TextStyle(fontWeight: FontWeight.w600),
    tableBody: text,
    tableHeadAlign: TextAlign.center,
    tablePadding: const EdgeInsets.only(bottom: 4),
    tableBorder: TableBorder.all(color: theme.dividerColor),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    tableCellsDecoration: const BoxDecoration(),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    blockquoteDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(3),
      border: Border(
        left: BorderSide(color: theme.colorScheme.primary, width: 3),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(8),
    codeblockDecoration: BoxDecoration(
      color: theme.cardTheme.color ?? theme.cardColor,
      borderRadius: BorderRadius.circular(2),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(width: 5, color: theme.dividerColor)),
    ),
    textScaler: MediaQuery.textScalerOf(context),
  );
}

class ChatMessageActions extends StatefulWidget {
  const ChatMessageActions({
    super.key,
    required this.message,
    required this.theme,
    this.visibleError,
  });

  final AiMessage message;
  final AppTheme theme;
  final String? visibleError;

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
    final body = message.role == 'assistant'
        ? parseSpeechReply(message.content).body
        : message.content;
    final text = switch (widget.visibleError) {
      final error? when body.trim().isEmpty => error,
      final error? => '${body.trimRight()}\n\n$error',
      _ => body,
    };
    final canCopy = text.trim().isNotEmpty;
    final copied = canCopy && _copied;
    final label = copied ? l10n.aiMessageCopied : l10n.aiCopyMessage;
    final copyButton = AppTooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: canCopy,
        child: TitleBarIconButton(
          key: ValueKey('ai-copy-message-${message.id}'),
          onPressed: canCopy ? () => _copy(text) : null,
          isFocused: true,
          theme: theme,
          icon: copied ? Symbols.check_rounded : Symbols.content_copy_rounded,
          size: 25,
          iconSize: 15,
          backgroundColor: Colors.transparent,
          surfaceColor: theme.secondary,
          hoverColor: theme.interactionHoverColor(theme.secondary),
          iconColor: theme.textColorSecondary,
        ),
      ),
    );
    final displayTime =
        message.role == 'assistant' || message.role == 'compaction'
        ? message.finishedAt
        : message.createdAt;
    final timestamp = displayTime == null
        ? null
        : Flexible(
            child: Text(
              DateFormat('yyyy.MM.dd HH:mm:ss').format(displayTime.toLocal()),
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

class SpeechReplyCard extends StatefulWidget {
  const SpeechReplyCard({
    super.key,
    required this.message,
    required this.theme,
  });

  final AiMessage message;
  final AppTheme theme;

  @override
  State<SpeechReplyCard> createState() => _SpeechReplyCardState();
}

class _SpeechReplyCardState extends State<SpeechReplyCard> {
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
    if (message.role != 'assistant') return const SizedBox.shrink();
    final spoken = parseSpeechReply(message.content).speech;
    if (spoken == null || spoken.isEmpty) return const SizedBox.shrink();
    final scope = context.watch<SpeechConversation?>();
    if (scope == null) return const SizedBox.shrink();
    final owner = (scope, message.id);
    final selection = context.select(
      (AiAssistantProvider? ai) => ai?.speechVoice,
    );
    final (available, playing, enabled) = context.select(
      (SpeechProvider? speech) => (
        speech?.library.synthesisModel(selection) != null,
        speech?.isPlaying(owner) ?? false,
        speech != null && !speech.busy && !speech.hasCapture,
      ),
    );
    if (!available && !playing) return const SizedBox.shrink();
    final l10n = context.l10n;
    final accent = playing ? theme.basePrimary : theme.textColorTertiary;
    final copyLabel = _copied ? l10n.aiMessageCopied : l10n.aiCopyMessage;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        key: ValueKey('ai-voice-card-${message.id}'),
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (playing ? theme.basePrimary : theme.dividerColor)
                .withValues(alpha: playing ? 0.65 : 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 10,
            children: [
              Icon(
                Symbols.record_voice_over_rounded,
                size: 16,
                fill: 1,
                color: accent,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      l10n.speechSpokenReply,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: accent,
                      ),
                    ),
                    Text(
                      spoken,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: theme.textColorPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  AppTooltip(
                    message: copyLabel,
                    child: Semantics(
                      label: copyLabel,
                      button: true,
                      enabled: true,
                      child: TitleBarIconButton(
                        key: ValueKey('ai-voice-copy-${message.id}'),
                        onPressed: () => unawaited(_copy(spoken)),
                        isFocused: true,
                        theme: theme,
                        icon: _copied
                            ? Symbols.check_rounded
                            : Symbols.content_copy_rounded,
                        size: 28,
                        iconSize: 16,
                        backgroundColor: Colors.transparent,
                        surfaceColor: theme.primary,
                        hoverColor: theme.interactionHoverColor(theme.primary),
                        iconColor: theme.textColorSecondary,
                      ),
                    ),
                  ),
                  SpeechIconButton(
                    key: ValueKey('ai-voice-play-${message.id}'),
                    theme: theme,
                    surface: theme.primary,
                    size: 28,
                    iconSize: 18,
                    label: playing
                        ? l10n.speechStopPlayback
                        : l10n.speechPlayReply,
                    icon: playing
                        ? Symbols.stop_rounded
                        : Symbols.volume_up_rounded,
                    onPressed: playing
                        ? () =>
                              context.read<SpeechProvider>().stopPlayback(owner)
                        : enabled
                        ? () =>
                              unawaited(_playSpeechText(context, owner, spoken))
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _playSpeechText(
  BuildContext context,
  Object owner,
  String text,
) async {
  final error = await context.read<SpeechProvider>().play(
    owner,
    text,
    selection: context.read<AiAssistantProvider?>()?.speechVoice,
  );
  if (error != null && context.mounted) {
    showAppNotice(
      ScaffoldMessenger.of(context),
      speechErrorLabel(context.l10n, error),
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
  _CodeBlockBuilder(
    this.theme,
    this.inlineBuilder,
    this.messageId, {
    this.initialIndex = 0,
  }) : _nextIndex = initialIndex;
  final AppTheme theme;
  final _CodeElementBuilder inlineBuilder;
  final String messageId;
  final int initialIndex;
  int _nextIndex;

  void reset() => _nextIndex = initialIndex;

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
      key: PageStorageKey('ai-message-code-$messageId-${_nextIndex++}'),
      text: code?.textContent ?? element.textContent,
      language: language,
      theme: theme,
    );
  }
}
