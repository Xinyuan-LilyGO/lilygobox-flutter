import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';

/// 聊天 Markdown 与命令详情共用的代码面板，正文继续参与外层唯一选区。
class ChatCodeBlock extends StatefulWidget {
  const ChatCodeBlock({
    super.key,
    required this.text,
    required this.language,
    required this.theme,
    this.maxBodyHeight,
    this.initialSoftWrap = false,
  });
  final String text;
  final String language;
  final AppTheme theme;

  /// 仅限制正文高度，语言标签和复制按钮固定；普通聊天代码块不限制。
  final double? maxBodyHeight;

  /// 完整命令默认换行，普通 Markdown 保留原始行布局；用户可单独切换。
  final bool initialSoftWrap;

  @override
  State<ChatCodeBlock> createState() => _ChatCodeBlockState();
}

class _ChatCodeBlockState extends State<ChatCodeBlock> {
  final _scroll = ScrollController();
  final _verticalScroll = ScrollController();
  bool _copied = false;
  late bool _softWrap = widget.initialSoftWrap;
  Timer? _reset;

  @override
  void dispose() {
    _scroll.dispose();
    _verticalScroll.dispose();
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final l10n = context.l10n;
    final label = _copied ? l10n.aiMessageCopied : l10n.aiCopyCode;
    final wrapLabel = _softWrap
        ? l10n.aiDisableCodeWrap
        : l10n.aiEnableCodeWrap;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        key: const ValueKey('ai-code-block'),
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SelectionContainer.disabled(
                  child: Row(
                    children: [
                      Icon(
                        Symbols.code_rounded,
                        size: 16,
                        color: theme.textColorSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.language.isEmpty ||
                                  widget.language == 'text' ||
                                  widget.language == 'plaintext'
                              ? l10n.aiPlainText
                              : widget.language,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColorSecondary,
                          ),
                        ),
                      ),
                      AppTooltip(
                        message: wrapLabel,
                        child: Semantics(
                          label: wrapLabel,
                          button: true,
                          toggled: _softWrap,
                          child: TitleBarIconButton(
                            key: const ValueKey('ai-code-wrap'),
                            theme: theme,
                            isFocused: true,
                            onPressed: () {
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                              setState(() => _softWrap = !_softWrap);
                            },
                            icon: Symbols.wrap_text_rounded,
                            size: 25,
                            iconSize: 15,
                            backgroundColor: _softWrap
                                ? theme.interactionHoverColor(theme.primary)
                                : theme.primary,
                            surfaceColor: theme.primary,
                            hoverColor: theme.interactionSelectedColor(
                              theme.primary,
                            ),
                            iconColor: _softWrap
                                ? theme.textColorPrimary
                                : theme.textColorSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AppTooltip(
                        message: label,
                        child: Semantics(
                          label: label,
                          button: true,
                          child: TitleBarIconButton(
                            key: const ValueKey('ai-copy-code'),
                            theme: theme,
                            isFocused: true,
                            onPressed: _copy,
                            icon: _copied
                                ? Symbols.check_rounded
                                : Symbols.content_copy_rounded,
                            size: 25,
                            iconSize: 15,
                            backgroundColor: theme.primary,
                            surfaceColor: theme.primary,
                            hoverColor: theme.interactionHoverColor(
                              theme.primary,
                            ),
                            iconColor: theme.textColorSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final style = TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: theme.textColorPrimary,
                  );
                  final painter = TextPainter(
                    text: TextSpan(text: widget.text, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  final textWidth = painter.width;
                  final textHeight = painter.height;
                  painter.dispose();
                  return _body(
                    style: style,
                    maxWidth: constraints.maxWidth,
                    maxHeight: widget.maxBodyHeight,
                    textWidth: textWidth,
                    textHeight: textHeight,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body({
    required TextStyle style,
    required double maxWidth,
    required double? maxHeight,
    required double textWidth,
    required double textHeight,
  }) {
    // 视口延伸至卡片边缘；正文留白在内侧，不能叠加到滚动条靠边距离。
    bool vertical;
    bool horizontal;
    if (_softWrap) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: (maxWidth - 24).clamp(0, double.infinity));
      vertical = maxHeight != null && painter.height + 12 > maxHeight;
      painter.dispose();
      horizontal = false;
    } else {
      vertical = maxHeight != null && textHeight + 12 > maxHeight;
      horizontal = textWidth > maxWidth - 12 - (vertical ? 20 : 12);
      vertical =
          maxHeight != null && textHeight + (horizontal ? 20 : 12) > maxHeight;
      horizontal = textWidth > maxWidth - 12 - (vertical ? 20 : 12);
    }
    if (!vertical && !horizontal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Text(widget.text, style: style),
      );
    }

    final gutter = EdgeInsets.only(
      left: 12,
      right: vertical ? 20 : 12,
      bottom: horizontal ? 20 : 12,
    );
    Widget body = Padding(
      padding: gutter,
      child: Text(widget.text, style: style, softWrap: _softWrap),
    );
    if (horizontal) {
      body = SingleChildScrollView(
        key: const ValueKey('ai-code-horizontal-scroll'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: body,
      );
    }
    if (vertical) {
      body = SingleChildScrollView(
        key: const ValueKey('ai-code-vertical-scroll'),
        controller: _verticalScroll,
        child: body,
      );
    }
    // 滚动视口与卡片等宽，保证轨道两端的 6 px 按真实边缘计算。
    // 固定裁剪区在滚动后仍保留正文通道，避免文字滑入滚动条下方。
    body = ClipRect(
      key: const ValueKey('ai-code-scroll-gutter'),
      clipper: _CodeBodyClipper(gutter),
      child: body,
    );
    body = ConstrainedBox(
      key: const ValueKey('ai-code-body-viewport'),
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      child: body,
    );
    if (vertical) {
      body = Scrollbar(
        key: const ValueKey('ai-code-vertical-scrollbar'),
        controller: _verticalScroll,
        interactive: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.vertical,
        child: body,
      );
    }
    if (horizontal) {
      body = Scrollbar(
        key: const ValueKey('ai-code-horizontal-scrollbar'),
        controller: _scroll,
        interactive: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: body,
      );
    }
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
        mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
      ),
      child: ScrollConfiguration(
        behavior: const AppScrollBehavior(scrollbars: false),
        child: body,
      ),
    );
  }
}

class _CodeBodyClipper extends CustomClipper<Rect> {
  const _CodeBodyClipper(this.gutter);

  final EdgeInsets gutter;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    gutter.left,
    0,
    size.width - gutter.right,
    size.height - gutter.bottom,
  );

  @override
  bool shouldReclip(_CodeBodyClipper oldClipper) => gutter != oldClipper.gutter;
}
