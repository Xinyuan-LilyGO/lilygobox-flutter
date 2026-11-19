import 'package:characters/characters.dart';

List<String> splitChatText(String text, {int targetLength = 2048}) {
  if (targetLength <= 0) {
    throw RangeError.value(targetLength, 'targetLength');
  }
  final segments = <String>[];
  var start = 0;
  while (text.length - start > targetLength) {
    final target = start + targetLength;
    final previousNewline = text.lastIndexOf('\n', target);
    final end = previousNewline >= start
        ? previousNewline
        : text.indexOf('\n', target + 1);
    if (end == -1) break;
    segments.add(text.substring(start, end));
    start = end + 1;
  }
  segments.add(text.substring(start));
  return segments;
}

List<String> splitChatTextForWindow(String text, {int targetLength = 2048}) {
  if (targetLength <= 0) {
    throw RangeError.value(targetLength, 'targetLength');
  }
  if (text.length <= targetLength) return [text];

  final characters = text.characters.toList(growable: false);
  final segments = <String>[];
  var start = 0;
  while (start < characters.length) {
    var end = start;
    var segmentLength = 0;
    while (end < characters.length &&
        (segmentLength + characters[end].length <= targetLength ||
            end == start)) {
      segmentLength += characters[end].length;
      end++;
    }
    if (end < characters.length) {
      final earliestBreak = (end - 64).clamp(start, end - 1);
      for (var index = end - 1; index >= earliestBreak; index--) {
        if (characters[index].trim().isEmpty) {
          end = index + 1;
          break;
        }
      }
    }
    segments.add(characters.sublist(start, end).join());
    start = end;
  }
  return segments;
}
