/*
 * @Description: 分离兼容接口放入正文开头的思考内容，并保留流式边界。
 * @Author: Codex
 * @Date: 2026-11-13 16:57:31
 * @LastEditTime: 2026-11-13 16:57:31
 */

/// Separates leading reasoning wrappers used by some compatible gateways.
///
/// Standard API reasoning fields are handled independently. Only a wrapper at
/// the start of a response is recognized; tags in prose or code remain text.
class ReasoningTextFilter {
  ReasoningTextFilter({required this.onText, required this.onReasoning});

  final void Function(String) onText;
  final void Function(String) onReasoning;
  static const _openings = ['<thinking>', '<think>'];
  String _pending = '';
  String? _closing;
  bool _bodyStarted = false;
  bool _sawReasoning = false;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    if (_bodyStarted) {
      onText(chunk);
      return;
    }
    _pending += chunk;
    while (_pending.isNotEmpty) {
      if (_closing case final closing?) {
        final end = _pending.indexOf(closing);
        if (end >= 0) {
          _emitReasoning(_pending.substring(0, end));
          _pending = _pending.substring(end + closing.length);
          _closing = null;
          continue;
        }
        // Keep only a possible split closing tag, not the entire reasoning.
        var retained = 0;
        for (var length = 1; length < closing.length; length++) {
          if (_pending.endsWith(closing.substring(0, length))) {
            retained = length;
          }
        }
        _emitReasoning(_pending.substring(0, _pending.length - retained));
        _pending = _pending.substring(_pending.length - retained);
        return;
      }
      final candidate = _pending.trimLeft();
      if (candidate.isEmpty) return;
      String? opening;
      for (final tag in _openings) {
        if (candidate.startsWith(tag)) {
          opening = tag;
          break;
        }
      }
      if (opening != null) {
        _sawReasoning = true;
        _closing = opening == '<thinking>' ? '</thinking>' : '</think>';
        _pending = candidate.substring(opening.length);
        continue;
      }
      if (_openings.any((tag) => tag.startsWith(candidate))) return;
      _bodyStarted = true;
      onText(_sawReasoning ? _pending.trimLeft() : _pending);
      _pending = '';
    }
  }

  void finish() {
    if (_closing != null) {
      _emitReasoning(_pending);
    } else if (_pending.isNotEmpty) {
      final remaining = _sawReasoning ? _pending.trimLeft() : _pending;
      if (remaining.isNotEmpty) onText(remaining);
    }
    _pending = '';
  }

  void _emitReasoning(String value) {
    if (value.isNotEmpty) onReasoning(value);
  }
}
