/*
 * @Description: 提供跨平台图片剪贴板的读取和写入能力。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 15:52:00
 * @LastEditTime: 2026-11-10 16:50:56
 */

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

class ImageClipboard {
  const ImageClipboard._();

  static const _windows = MethodChannel('lilygobox/image_clipboard');

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<T?> _invokeWindows<T>(
    String method, [
    Object? arguments,
  ]) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _windows.invokeMethod<T>(method, arguments);
      } on PlatformException catch (error) {
        if (error.code != 'clipboard_busy' || attempt >= 3) rethrow;
        // 系统历史面板可能短暂持有剪贴板锁；异步退让，不阻塞窗口线程。
        await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
      }
    }
  }

  static Future<Uint8List?> readPng() async {
    if (_isWindows) {
      final bytes = await _invokeWindows<Uint8List>('readImage');
      if (bytes != null) return _toPng(bytes);
    }
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) throw StateError('Image clipboard unavailable');
    final reader = await clipboard.read();
    // 文件管理器复制的图片通过文件 URI 提供，而不是 PNG 剪贴板格式。
    for (final item in reader.items) {
      if (!item.canProvide(Formats.fileUri)) continue;
      final uri = await item.readValue(Formats.fileUri);
      if (uri == null) continue;
      final format = switch (uri.path.toLowerCase().split('.').last) {
        'png' => Formats.png,
        'jpg' || 'jpeg' || 'jfif' => Formats.jpeg,
        'gif' => Formats.gif,
        'webp' => Formats.webp,
        'bmp' => Formats.bmp,
        'tif' || 'tiff' => Formats.tiff,
        _ => null,
      };
      if (format == null) continue;
      final bytes = await _readFile(item, format);
      if (bytes != null) return _toPng(bytes);
    }
    for (final format in [
      Formats.png,
      Formats.jpeg,
      Formats.gif,
      Formats.webp,
      Formats.bmp,
      Formats.tiff,
    ]) {
      if (!reader.canProvide(format)) continue;
      final bytes = await _readFile(reader, format);
      if (bytes != null) return _toPng(bytes);
    }
    return null;
  }

  static Future<Uint8List?> _readFile(
    DataReader reader,
    FileFormat format,
  ) async {
    final result = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!result.isCompleted) result.complete(bytes);
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        }
      },
      onError: (error) {
        if (!result.isCompleted) result.completeError(error);
      },
    );
    if (progress == null) return null;
    return result.future.timeout(const Duration(seconds: 10));
  }

  static Future<Uint8List> _toPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) throw StateError('PNG encoding failed');
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static Future<void> writeImage(Uint8List bytes) async {
    if (_isWindows) {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (png == null || rgba == null) {
            throw StateError('Image encoding failed');
          }
          await _invokeWindows<void>('writeImage', {
            'png': png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            'rgba': rgba.buffer.asUint8List(
              rgba.offsetInBytes,
              rgba.lengthInBytes,
            ),
            'width': frame.image.width,
            'height': frame.image.height,
          });
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return;
    }
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) throw StateError('Image clipboard unavailable');
    final png = await _toPng(bytes);
    final item = DataWriterItem()..add(Formats.png(png));
    await clipboard.write([item]);
  }
}
