/*
 * @Description: 为图片提供统一的右键复制菜单和原图预览入口。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 15:53:00
 * @LastEditTime: 2026-11-10 19:48:38
 */

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clipboard/image_clipboard.dart';
import '../context_menu/right_click_menu.dart';
import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'app_notice.dart';
import 'image_viewer.dart';

class ImageClipboardMenu extends StatefulWidget {
  const ImageClipboardMenu({
    super.key,
    required this.bytes,
    required this.theme,
    required this.child,
  });

  final Uint8List bytes;
  final AppTheme theme;
  final Widget child;

  @override
  State<ImageClipboardMenu> createState() => _ImageClipboardMenuState();
}

class _ImageClipboardMenuState extends State<ImageClipboardMenu> {
  final _menu = RightClickMenuController();

  void _viewOriginal() {
    _menu.close();
    showAppImageViewer(
      context: context,
      bytes: widget.bytes,
      theme: widget.theme,
    );
  }

  @override
  Widget build(BuildContext context) => RightClickMenuBuilder.buildMenuAnchor(
    context: context,
    controller: _menu,
    theme: widget.theme,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _viewOriginal,
      child: widget.child,
    ),
    onSecondaryTap: () {},
    menuItems: [
      RightClickMenuItem(
        label: context.l10n.aiViewOriginal,
        icon: Symbols.open_in_full_rounded,
        onTap: _viewOriginal,
      ),
      RightClickMenuItem(
        label: context.l10n.aiCopyImage,
        icon: Symbols.content_copy,
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final failure = context.l10n.aiCopyImageFailed;
          _menu.close();
          try {
            await ImageClipboard.writeImage(widget.bytes);
          } catch (error, stack) {
            developer.log(
              'Image clipboard write failed',
              name: 'ImageClipboard',
              error: error,
              stackTrace: stack,
            );
            showAppNotice(messenger, failure);
          }
        },
      ),
    ],
  );
}
