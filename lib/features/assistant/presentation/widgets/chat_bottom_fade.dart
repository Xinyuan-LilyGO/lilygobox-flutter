/*
 * @Description: 用上下边缘局部背景渐变淡出聊天内容，避免整屏离屏遮罩。
 */

import 'package:flutter/widgets.dart';

/// 将内容渐变融入周围不透明背景，避免使用离屏遮罩。
class ChatBottomFade extends StatelessWidget {
  const ChatBottomFade({
    super.key,
    required this.backgroundColor,
    required this.child,
    this.fadeHeight = 64,
    this.topFadeHeight = 0,
    this.scrollController,
  }) : assert(fadeHeight >= 0),
       assert(topFadeHeight >= 0);

  final Color backgroundColor;
  final Widget child;
  final double fadeHeight;
  final double topFadeHeight;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      if (topFadeHeight > 0)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: topFadeHeight,
          child: switch (scrollController) {
            final controller? => AnimatedBuilder(
              animation: controller,
              child: _topFade(),
              builder: (context, child) =>
                  controller.hasClients &&
                      controller.position.hasPixels &&
                      controller.position.hasContentDimensions &&
                      controller.position.pixels >
                          controller.position.minScrollExtent
                  ? child!
                  : const SizedBox.shrink(),
            ),
            null => _topFade(),
          },
        ),
      if (fadeHeight > 0)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: fadeHeight,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor.withValues(alpha: 0),
                      backgroundColor,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _topFade() => IgnorePointer(
    child: ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('chat-top-fade'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundColor, backgroundColor.withValues(alpha: 0)],
          ),
        ),
      ),
    ),
  );
}
