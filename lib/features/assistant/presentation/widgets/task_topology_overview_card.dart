import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';

typedef _Label = (
  String,
  TextStyle,
  double,
  TextDirection,
  TextScaler,
  Locale?,
);

class TaskOverviewPaintCache {
  final _labels = <_Label, TextPainter>{};
  final _cards = <Object, ui.Image>{};
  bool _texturesAvailable =
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.windows ||
      ui.ImageFilter.isShaderFilterSupported;
  int _bytes = 0;

  ui.Image? _card(
    Object key,
    Size size,
    double ratio,
    void Function(Canvas) draw,
  ) {
    final cached = _cards.remove(key);
    if (cached != null) return _cards[key] = cached;
    final width = (size.width * ratio).ceil();
    final height = (size.height * ratio).ceil();
    final bytes = width * height * 4;
    if (width <= 0 ||
        height <= 0 ||
        width > 2048 ||
        height > 2048 ||
        bytes > 1024 * 1024) {
      return null;
    }
    while (_bytes + bytes > 32 * 1024 * 1024 && _cards.isNotEmpty) {
      final oldest = _cards.remove(_cards.keys.first)!;
      _bytes -= oldest.width * oldest.height * 4;
      oldest.dispose();
    }
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder)..scale(width / size.width, height / size.height));
    final picture = recorder.endRecording();
    try {
      final image = picture.toImageSync(width, height);
      _bytes += bytes;
      return _cards[key] = image;
    } finally {
      picture.dispose();
    }
  }

  TextPainter _layout(_Label label) {
    final cached = _labels.remove(label);
    if (cached != null) return _labels[label] = cached;
    final (text, style, width, direction, scaler, locale) = label;
    if (_labels.length >= 1024) {
      _labels.remove(_labels.keys.first)!.dispose();
    }
    return _labels[label] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
  }

  void _releaseTextures() {
    _texturesAvailable = false;
    for (final image in _cards.values) {
      image.dispose();
    }
    _cards.clear();
    _bytes = 0;
  }

  void dispose() {
    for (final label in _labels.values) {
      label.dispose();
    }
    _labels.clear();
    _releaseTextures();
  }
}

class TaskTopologyOverviewCard extends StatefulWidget {
  const TaskTopologyOverviewCard({
    super.key,
    required this.title,
    required this.summary,
    required this.modelLabel,
    required this.idLabel,
    required this.selected,
    required this.showPorts,
    required this.indicator,
    required this.onOpen,
    required this.onSelect,
    required this.theme,
    required this.cache,
  });

  final String title;
  final String summary;
  final String modelLabel;
  final String idLabel;
  final bool selected;
  final bool showPorts;
  final Color? indicator;
  final VoidCallback onOpen;
  final VoidCallback onSelect;
  final AppTheme theme;
  final TaskOverviewPaintCache cache;

  @override
  State<TaskTopologyOverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<TaskTopologyOverviewCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final theme = widget.theme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${widget.title}, ${widget.summary}, ${widget.modelLabel}, ${widget.idLabel}',
      onTap: widget.onOpen,
      customSemanticsActions: widget.selected
          ? null
          : {
              CustomSemanticsAction(label: context.l10n.cardSelect):
                  widget.onSelect,
            },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: CustomPaint(
          painter: _OverviewPainter(
            cache: widget.cache,
            title: widget.title,
            summary: widget.summary,
            metadata: _hovered ? (widget.modelLabel, widget.idLabel) : null,
            titleStyle: style.copyWith(
              color: theme.textColorPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            summaryStyle: style.copyWith(
              color: theme.textColorSecondary,
              fontSize: 15,
            ),
            theme: theme,
            selected: widget.selected,
            showPorts: widget.showPorts || _hovered,
            indicator: widget.indicator,
            direction: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
            scaler: MediaQuery.textScalerOf(context),
            ratio: .55 * MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

class _OverviewPainter extends CustomPainter {
  const _OverviewPainter({
    required this.cache,
    required this.title,
    required this.summary,
    required this.metadata,
    required this.titleStyle,
    required this.summaryStyle,
    required this.theme,
    required this.selected,
    required this.showPorts,
    required this.indicator,
    required this.direction,
    required this.locale,
    required this.scaler,
    required this.ratio,
  });

  final TaskOverviewPaintCache cache;
  final String title;
  final String summary;
  final (String, String)? metadata;
  final TextStyle titleStyle;
  final TextStyle summaryStyle;
  final AppTheme theme;
  final bool selected;
  final bool showPorts;
  final Color? indicator;
  final TextDirection direction;
  final Locale? locale;
  final TextScaler scaler;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    if (metadata == null && cache._texturesAvailable) {
      final bounds = (Offset.zero & size).inflate(4);
      final key = (
        size,
        ratio,
        title,
        summary,
        titleStyle,
        summaryStyle,
        theme,
        indicator,
        selected,
        showPorts,
        direction,
        locale,
        scaler,
      );
      try {
        final image = cache._card(key, bounds.size, ratio, (canvas) {
          canvas.translate(4, 4);
          _paintCard(canvas, size);
        });
        if (image != null) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            bounds,
            Paint()..filterQuality = FilterQuality.low,
          );
          return;
        }
      } on ui.PictureRasterizationException {
        cache._releaseTextures();
      }
    }
    _paintCard(canvas, size);
  }

  void _paintCard(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final card = RRect.fromRectAndRadius(bounds, const Radius.circular(12));
    final paint = Paint()..color = theme.primary;
    canvas.drawRRect(card, paint);
    if (selected) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = theme.basePrimary;
      canvas.drawRRect(card.deflate(1.5), paint);
      paint.style = PaintingStyle.fill;
    }
    final width = size.width - 32;
    final heading = cache._layout((
      title,
      titleStyle,
      width,
      direction,
      scaler,
      locale,
    ));
    final detail = cache._layout((
      summary,
      summaryStyle,
      width,
      direction,
      scaler,
      locale,
    ));
    final labels = metadata;
    final extra = labels == null
        ? const <TextPainter>[]
        : [
            for (final text in [labels.$1, labels.$2])
              cache._layout((
                text,
                summaryStyle,
                width,
                direction,
                scaler,
                locale,
              )),
          ];
    final extraHeight = extra.fold(0.0, (sum, row) => sum + row.height);
    final top =
        (size.height - heading.height - detail.height - 5 - extraHeight) / 2;
    heading.paint(canvas, Offset(16, top));
    detail.paint(canvas, Offset(16, top + heading.height + 5));
    var position = top + heading.height + 5 + detail.height;
    for (final row in extra) {
      row.paint(canvas, Offset(16, position));
      position += row.height;
    }
    if (indicator case final color?) {
      canvas.drawCircle(Offset(size.width - 18, 18), 5, paint..color = color);
    }
    final end = Offset(size.width - 17, size.height - 25);
    paint
      ..color = theme.textColorSecondary
      ..strokeWidth = 2;
    canvas.drawLine(end + const Offset(-10, 10), end, paint);
    canvas.drawLine(end + const Offset(-9, 0), end, paint);
    canvas.drawLine(end + const Offset(0, 9), end, paint);
    paint.color = theme.basePrimary.withValues(alpha: showPorts ? 1 : .16);
    for (final port in [
      bounds.centerLeft,
      bounds.centerRight,
      bounds.topCenter,
      bounds.bottomCenter,
    ]) {
      canvas.drawCircle(port, 4, paint);
    }
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      old.title != title ||
      old.summary != summary ||
      old.metadata != metadata ||
      old.titleStyle != titleStyle ||
      old.summaryStyle != summaryStyle ||
      old.theme != theme ||
      old.selected != selected ||
      old.showPorts != showPorts ||
      old.indicator != indicator ||
      old.direction != direction ||
      old.locale != locale ||
      old.ratio != ratio ||
      old.scaler != scaler;
}
