import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_title_bar.dart';
import 'window_page_stack.dart';
import 'window_resize_overlay.dart';

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({
    super.key,
    required this.theme,
    required this.isMaximized,
  });

  final AppTheme theme;
  final bool isMaximized;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: isMaximized ? EdgeInsets.zero : const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: isMaximized ? BorderRadius.zero : BorderRadius.circular(10),
        boxShadow: isMaximized ? [] : _buildBoxShadow(),
      ),
      child: ClipRRect(
        borderRadius: isMaximized ? BorderRadius.zero : BorderRadius.circular(10),
        child: const Stack(
          children: [
            Column(
              children: [
                AppTitleBar(),
                WindowPageStack(),
              ],
            ),
            WindowResizeOverlay(),
          ],
        ),
      ),
    );
  }

  List<BoxShadow> _buildBoxShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 5,
        spreadRadius: -1,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 4,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 3,
        spreadRadius: -3,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 2,
        spreadRadius: -4,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 1,
        spreadRadius: -5,
      ),
    ];
  }
}
