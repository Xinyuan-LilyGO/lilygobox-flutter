/*
 * @Description: 从已显示的回复正文提取适合朗读的文字。
 */

import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;

String speechReplyText(String source) {
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
