/*
 * @Description: 解析回复中的独立口语台词标签，并提取适合朗读的纯文本。
 */

import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;

typedef SpeechReplyContent = ({
  String body,
  String? speech,
  bool pendingSpeech,
});

final _completeSpeechTag = RegExp(
  r'<speech\b[^>]*>([\s\S]*?)</speech>',
  caseSensitive: false,
);
final _openSpeechTag = RegExp(r'<speech\b[^>]*>([\s\S]*)$', caseSensitive: false);

SpeechReplyContent parseSpeechReply(String source) {
  final completeMatches = _completeSpeechTag.allMatches(source).toList();
  if (completeMatches.isNotEmpty) {
    final spoken = [
      for (final match in completeMatches)
        _plainText(match.group(1) ?? '').trim(),
    ].where((part) => part.isNotEmpty).join('\n');
    final body = source.replaceAll(_completeSpeechTag, '').trimRight();
    return (
      body: body,
      speech: spoken.isEmpty ? null : spoken,
      pendingSpeech: false,
    );
  }
  final openMatch = _openSpeechTag.firstMatch(source);
  if (openMatch != null) {
    final body = source.substring(0, openMatch.start).trimRight();
    final spoken = _plainText(openMatch.group(1) ?? '').trim();
    return (
      body: body,
      speech: spoken.isEmpty ? null : spoken,
      pendingSpeech: true,
    );
  }
  return (body: source, speech: null, pendingSpeech: false);
}

String speechReplyText(String source) {
  final parsed = parseSpeechReply(source);
  if (parsed.speech case final spoken?) return spoken;
  return _plainText(parsed.body);
}

String _plainText(String source) {
  final document = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final buffer = StringBuffer();
  void visit(markdown.Node node) {
    if (node is markdown.Text) {
      buffer.write(node.text);
    } else if (node is markdown.Element) {
      if (const {'pre', 'code', 'img', 'script', 'style'}.contains(node.tag)) {
        buffer.write(' ');
        return;
      }
      node.children?.forEach(visit);
      if (const {
        'p',
        'li',
        'tr',
        'br',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
      }.contains(node.tag)) {
        buffer.writeln();
      } else if (node.tag == 'td' || node.tag == 'th') {
        buffer.write(' ');
      }
    }
  }

  document.parseLines(const LineSplitter().convert(source)).forEach(visit);
  return buffer.toString().trim();
}
