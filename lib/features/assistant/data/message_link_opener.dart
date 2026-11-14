/*
 * @Description: 解析聊天中的网页和本地 HTML 链接，并交给系统默认程序打开。
 * @Author: LILYGO_L
 * @Date: 2026-11-11 23:59:55
 * @LastEditTime: 2026-11-12 00:06:19
 */

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class MessageLinkOpener {
  const MessageLinkOpener({this.launch = _launchExternally});

  final Future<bool> Function(Uri) launch;

  Future<bool> open(String? href, {required AiMessage message}) async {
    try {
      final uri = _resolve(href, message.processingSteps);
      if (uri == null) return false;
      if (uri.scheme == 'file') {
        final file = File.fromUri(uri.replace(query: '', fragment: ''));
        if (!await file.exists()) return false;
      }
      return await launch(uri);
    } on Exception {
      // 路径、文件访问和系统启动失败统一由调用方显示本地化提示。
      return false;
    }
  }

  Uri? _resolve(String? href, List<AiProcessingStep> steps) {
    final value = href?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = _parse(value, decodePath: true);
    if (uri == null) return null;
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return uri.host.isEmpty ? null : uri;
    }
    if (uri.scheme == 'mailto') return uri.path.isEmpty ? null : uri;
    if (_isLocalHtml(uri)) return uri;
    if (uri.hasScheme || uri.hasAuthority || uri.path.isEmpty) return null;

    // 相对链接只匹配本段实际写入成功的文件，不猜测工作目录或任意拼接路径。
    final matches = <Uri>{};
    for (final step in steps) {
      if (!step.succeeded || step.name != 'write_file') continue;
      final path = step.arguments['path'];
      if (path is! String) continue;
      final target = _parse(path);
      if (target == null || !_isLocalHtml(target)) continue;
      final resolved = target.resolveUri(uri);
      final file = resolved.replace(query: '', fragment: '').toString();
      final expected = target.replace(query: '', fragment: '').toString();
      final windows = RegExp(r'^/[a-zA-Z]:/').hasMatch(target.path);
      if (windows
          ? file.toLowerCase() == expected.toLowerCase()
          : file == expected) {
        matches.add(resolved);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  Uri? _parse(String value, {bool decodePath = false}) {
    final uri = Uri.tryParse(value);
    if (['https', 'http', 'mailto', 'file'].contains(uri?.scheme)) return uri;
    // Markdown 已编码链接目的地；路径只解码一次，工具记录中的原生路径不解码。
    var path = decodePath
        ? value.replaceAllMapped(
            RegExp(r'(?:%[0-9a-fA-F]{2})+'),
            (match) => Uri.decodeComponent(match[0]!),
          )
        : value;
    if (RegExp(r'^/[a-zA-Z]:/').hasMatch(path)) path = path.substring(1);
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) {
      if (!RegExp(r'^[a-zA-Z]:[\\/][^<>:"|?*\x00-\x1F]*$').hasMatch(path)) {
        return null;
      }
      return Uri.file(path, windows: true);
    }
    if (path.startsWith('/') && !path.startsWith('//')) {
      return Uri.file(path);
    }
    return uri;
  }

  bool _isLocalHtml(Uri uri) {
    if (uri.scheme != 'file' ||
        uri.hasAuthority && uri.host.isNotEmpty ||
        !uri.path.startsWith('/') ||
        uri.pathSegments.isEmpty) {
      return false;
    }
    final segments = uri.pathSegments;
    if (Platform.isWindows) {
      final drive = RegExp(r'^[a-zA-Z]:$').hasMatch(segments.first);
      if (segments
          .skip(drive ? 1 : 0)
          .any(
            (segment) => RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(segment),
          )) {
        return false;
      }
    } else if (segments.any(
      (segment) => segment.contains('/') || segment.contains('\u0000'),
    )) {
      return false;
    }
    // 本地浏览预览只接入 HTML 文档，不交给系统执行脚本或可执行文件。
    final name = segments.last.toLowerCase();
    return name.endsWith('.html') || name.endsWith('.htm');
  }
}
