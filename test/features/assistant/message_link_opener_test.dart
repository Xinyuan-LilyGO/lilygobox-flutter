/*
 * @Description: 验证聊天链接的系统打开、本地 HTML 路径及相对文件引用。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lilygobox/features/assistant/data/message_link_opener.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

void main() {
  late Directory root;
  late File html;
  late List<Uri> launched;
  late MessageLinkOpener opener;
  const message = AiMessage(id: 'links', role: 'assistant', content: '');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('message-link-');
    html = File.fromUri(root.uri.resolveUri(Uri(path: '鹦鹉 骑车 & #1.html')));
    await html.writeAsString('<!doctype html><title>preview</title>');
    launched = [];
    opener = MessageLinkOpener(
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
    );
  });

  tearDown(() => root.delete(recursive: true));

  for (final href in [
    'https://example.test/search?q=hello#result',
    'http://example.test/',
    'mailto:test@example.test?subject=Hello',
  ]) {
    test('opens existing external link type: $href', () async {
      expect(await opener.open(href, message: message), isTrue);
      expect(launched, [Uri.parse(href)]);
    });
  }

  test('opens encoded file URI containing Chinese, spaces and #', () async {
    expect(await opener.open(html.uri.toString(), message: message), isTrue);
    expect(launched, [html.uri]);
  });

  test('converts a native absolute HTML path to a file URI', () async {
    expect(await opener.open(html.path, message: message), isTrue);
    expect(launched, [html.uri]);
  });

  test('opens the path produced by the actual Markdown link parser', () async {
    final elements = md.Document().parseInline('[预览](<' + html.path + '>)');
    final anchor = elements.whereType<md.Element>().single;
    expect(
      await opener.open(anchor.attributes['href'], message: message),
      isTrue,
    );
    expect(launched, [html.uri]);
  });

  test('keeps an HTML fragment when opening a file URI', () async {
    final uri = html.uri.replace(fragment: 'scene-2');
    expect(await opener.open(uri.toString(), message: message), isTrue);
    expect(launched, [uri]);
  });

  if (Platform.isWindows) {
    test('opens Windows forward-slash and /C:/ paths', () async {
      final forward = html.uri.path.substring(1);
      expect(await opener.open(forward, message: message), isTrue);
      expect(await opener.open('/$forward', message: message), isTrue);
      expect(launched, [html.uri, html.uri]);
    });
  }

  test(
    'resolves a filename against a successful write in this segment',
    () async {
      final written = message.copyWith(
        processingSteps: [
          AiProcessingStep(
            name: 'write_file',
            arguments: {'path': html.path},
            succeeded: true,
          ),
        ],
      );
      final href = Uri(path: html.uri.pathSegments.last, fragment: 'scene');
      expect(await opener.open(href.toString(), message: written), isTrue);
      expect(launched, [html.uri.replace(fragment: 'scene')]);
    },
  );

  test('does not guess a relative file after a failed write', () async {
    final failed = message.copyWith(
      processingSteps: [
        AiProcessingStep(
          name: 'write_file',
          arguments: {'path': html.path},
          succeeded: false,
        ),
      ],
    );
    final href = Uri(path: html.uri.pathSegments.last).toString();
    expect(await opener.open(href, message: message), isFalse);
    expect(await opener.open(href, message: failed), isFalse);
    expect(launched, isEmpty);
  });

  test('does not guess between two written files with the same name', () async {
    final other = await Directory.fromUri(root.uri.resolve('other/')).create();
    final second = File.fromUri(
      other.uri.resolveUri(Uri(path: html.uri.pathSegments.last)),
    );
    await second.writeAsString('second');
    final ambiguous = message.copyWith(
      processingSteps: [
        for (final file in [html, second])
          AiProcessingStep(
            name: 'write_file',
            arguments: {'path': file.path},
            succeeded: true,
          ),
      ],
    );
    expect(
      await opener.open(
        Uri(path: html.uri.pathSegments.last).toString(),
        message: ambiguous,
      ),
      isFalse,
    );
    expect(launched, isEmpty);
  });

  test('does not launch a missing local HTML file', () async {
    await html.delete();
    expect(await opener.open(html.uri.toString(), message: message), isFalse);
    expect(launched, isEmpty);
  });

  test('rejects unsupported schemes and non-HTML local targets', () async {
    final executable = File.fromUri(root.uri.resolve('do-not-run.exe'));
    await executable.writeAsString('not an executable');
    for (final href in [
      null,
      '',
      'javascript:alert(1)',
      'data:text/html,hello',
      'command:run',
      'file://remote-host/share/preview.html',
      'file:///C:invalid.html',
      'file:///C:/bad%2Fname.html',
      executable.uri.toString(),
    ]) {
      expect(await opener.open(href, message: message), isFalse, reason: href);
    }
    expect(launched, isEmpty);
  });

  test('returns failure when the system cannot open a link', () async {
    final failed = MessageLinkOpener(launch: (_) async => false);
    final throwing = MessageLinkOpener(
      launch: (_) async => throw const FileSystemException('Cannot open'),
    );
    const href = 'https://example.test/';
    expect(await failed.open(href, message: message), isFalse);
    expect(await throwing.open(href, message: message), isFalse);
  });
}
