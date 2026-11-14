/*
 * @Description: 提供原图遮罩预览、关闭交互和 Ctrl 滚轮缩放。
 */

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'app_tooltip.dart';
import 'interaction_decoration.dart';
import 'title_bar_icon_button.dart';

Future<void> showAppImageViewer({
  required BuildContext context,
  required Uint8List bytes,
  required AppTheme theme,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : InteractionDecoration.animationDuration,
  transitionBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, animation, secondaryAnimation) =>
      _ImageViewer(bytes: bytes, theme: theme),
);

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.bytes, required this.theme});
  final Uint8List bytes;
  final AppTheme theme;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _transform = TransformationController();
  final _image = GlobalKey();
  bool _closing = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _zoom(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final current = _transform.value.getMaxScaleOnAxis();
      final next = (current * math.exp(-event.scrollDelta.dy * .002)).clamp(
        .25,
        8.0,
      );
      final anchor = event.localPosition;
      final ratio = next / current;
      // 围绕鼠标位置缩放，避免放大时图片中心突然偏移。
      _transform.value = Matrix4.identity()
        ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
        ..scaleByDouble(ratio, ratio, ratio, 1)
        ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1)
        ..multiply(_transform.value);
    });
  }

  void _dismissOutside(TapUpDetails details) {
    final box = _image.currentContext?.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.size.contains(box.globalToLocal(details.globalPosition))) {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: Focus(
      autofocus: true,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('image-viewer-backdrop'),
                behavior: HitTestBehavior.opaque,
                onTapUp: _dismissOutside,
                child: Listener(
                  onPointerSignal: _zoom,
                  child: InteractiveViewer(
                    key: const ValueKey('image-viewer-viewport'),
                    transformationController: _transform,
                    scaleEnabled: false,
                    minScale: .25,
                    maxScale: 8,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: SizedBox.expand(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Image.memory(
                            widget.bytes,
                            key: _image,
                            fit: BoxFit.contain,
                            semanticLabel: context.l10n.aiViewOriginal,
                            frameBuilder:
                                (
                                  context,
                                  child,
                                  frame,
                                  synchronous,
                                ) => AnimatedOpacity(
                                  opacity: synchronous || frame != null ? 1 : 0,
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : InteractionDecoration.animationDuration,
                                  child: child,
                                ),
                            errorBuilder: (context, error, stack) => Text(
                              context.l10n.aiImagePreviewFailed,
                              style: TextStyle(
                                color: widget.theme.textColorPrimary,
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
            Positioned(
              top: 16,
              right: 16,
              child: AppTooltip(
                message: context.l10n.close,
                child: Semantics(
                  button: true,
                  label: context.l10n.close,
                  child: TitleBarIconButton(
                    key: const ValueKey('image-viewer-close'),
                    theme: widget.theme,
                    isFocused: true,
                    icon: Symbols.close_rounded,
                    size: 28,
                    iconSize: 18,
                    backgroundColor: widget.theme.primary,
                    hoverColor: widget.theme.primaryTextHoverColor,
                    onPressed: _close,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
