import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/empty_line_selection.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
import 'chat_content_window.dart';
import 'chat_text_segments.dart';

/// 聊天 Markdown 与命令详情共用的代码面板，正文继续参与外层唯一选区。
class ChatCodeBlock extends StatefulWidget {
  const ChatCodeBlock({
    super.key,
    required this.text,
    required this.language,
    required this.theme,
    this.backgroundColor,
    this.maxBodyHeight,
    this.initialSoftWrap = false,
  });
  final String text;
  final String language;
  final AppTheme theme;

  /// 嵌入批准面板等同色容器时，可选用另一层主题背景。
  final Color? backgroundColor;

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
  PageStorageBucket? _storage;
  List<String>? _segments;
  final _fallbackStorageId = Object();
  double _measuredCodeWidth = 0;
  TextScaler? _widthTextScaler;
  TextDirection? _widthTextDirection;

  Object? get _wrapStorageId =>
      widget.key is PageStorageKey ? ('ai-code-wrap', widget.key) : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    if (scaler != _widthTextScaler || direction != _widthTextDirection) {
      _measuredCodeWidth = 0;
      _widthTextScaler = scaler;
      _widthTextDirection = direction;
    }
    final storage = PageStorage.maybeOf(context);
    if (identical(storage, _storage)) return;
    _storage = storage;
    if (_wrapStorageId case final identifier?) {
      final saved = storage?.readState(context, identifier: identifier);
      if (saved is bool) _softWrap = saved;
    }
  }

  void _toggleWrap() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _softWrap = !_softWrap);
    if (_wrapStorageId case final identifier?) {
      _storage?.writeState(context, _softWrap, identifier: identifier);
    }
  }

  @override
  void didUpdateWidget(ChatCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _segments = null;
      if (!widget.text.startsWith(oldWidget.text)) _measuredCodeWidth = 0;
    }
  }

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
    final surfaceColor = widget.backgroundColor ?? theme.primary;
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
          color: surfaceColor,
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
                            onPressed: _toggleWrap,
                            icon: Symbols.wrap_text_rounded,
                            size: 25,
                            iconSize: 15,
                            backgroundColor: _softWrap
                                ? theme.interactionHoverColor(surfaceColor)
                                : surfaceColor,
                            surfaceColor: surfaceColor,
                            hoverColor: theme.interactionSelectedColor(
                              surfaceColor,
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
                            backgroundColor: surfaceColor,
                            surfaceColor: surfaceColor,
                            hoverColor: theme.interactionHoverColor(
                              surfaceColor,
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
                  if (widget.maxBodyHeight == null &&
                      widget.text.length >= 4096 &&
                      ChatContentScope.maybeOf(context) != null) {
                    final segments = _segments ??= splitChatText(widget.text);
                    if (segments.length > 1) {
                      return _segmentedBody(
                        style,
                        constraints.maxWidth,
                        segments,
                      );
                    }
                  }
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

  Widget _segmentedBody(
    TextStyle style,
    double maxWidth,
    List<String> segments,
  ) {
    Widget body = ChatContentWindow(
      childCount: segments.length,
      revision: widget.text.hashCode,
      storageId: ('chat-code-lines', widget.key ?? _fallbackStorageId),
      itemBuilder: (context, index) => RepaintBoundary(
        key: ValueKey('ai-code-lines-$index'),
        child: EmptyLineSelection(
          child: Text(
            index < segments.length - 1 && segments[index].endsWith('\r')
                ? segments[index].substring(0, segments[index].length - 1)
                : segments[index],
            style: style,
            softWrap: _softWrap,
          ),
        ),
      ),
    );
    if (_softWrap) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: body,
      );
    }
    body = SingleChildScrollView(
      key: const ValueKey('ai-code-horizontal-scroll'),
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: _MeasuredCodeWidth(
          minimumWidth: _measuredCodeWidth,
          onMeasured: (width) => _measuredCodeWidth = width,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: (maxWidth - 24).clamp(0, double.infinity),
            ),
            child: body,
          ),
        ),
      ),
    );
    if (widget.key is PageStorageKey) {
      body = KeyedSubtree(
        key: const PageStorageKey('ai-code-horizontal'),
        child: body,
      );
    }
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
        mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
      ),
      child: Scrollbar(
        key: const ValueKey('ai-code-horizontal-scrollbar'),
        controller: _scroll,
        interactive: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: ScrollConfiguration(
          behavior: const AppScrollBehavior(scrollbars: false),
          child: ClipRect(
            key: const ValueKey('ai-code-scroll-gutter'),
            clipper: const _CodeBodyClipper(EdgeInsets.fromLTRB(12, 0, 12, 20)),
            child: body,
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
      if (widget.key is PageStorageKey) {
        body = KeyedSubtree(
          key: const PageStorageKey('ai-code-horizontal'),
          child: body,
        );
      }
    }
    if (vertical) {
      body = SingleChildScrollView(
        key: const ValueKey('ai-code-vertical-scroll'),
        controller: _verticalScroll,
        child: body,
      );
      if (widget.key is PageStorageKey) {
        body = KeyedSubtree(
          key: const PageStorageKey('ai-code-vertical'),
          child: body,
        );
      }
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

class _MeasuredCodeWidth extends SingleChildRenderObjectWidget {
  const _MeasuredCodeWidth({
    required this.minimumWidth,
    required this.onMeasured,
    required super.child,
  });

  final double minimumWidth;
  final ValueChanged<double> onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredCodeWidth(minimumWidth, onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasuredCodeWidth renderObject,
  ) {
    renderObject.minimumWidth = minimumWidth;
    renderObject.onMeasured = onMeasured;
  }
}

class _RenderMeasuredCodeWidth extends RenderProxyBox {
  _RenderMeasuredCodeWidth(this._minimumWidth, this.onMeasured);

  double _minimumWidth;
  ValueChanged<double> onMeasured;

  set minimumWidth(double value) {
    if (_minimumWidth == value) return;
    _minimumWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(
      constraints.enforce(BoxConstraints(minWidth: _minimumWidth)),
      parentUsesSize: true,
    );
    size = constraints.constrain(child!.size);
    if (size.width > _minimumWidth) {
      _minimumWidth = size.width;
      onMeasured(_minimumWidth);
    }
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
