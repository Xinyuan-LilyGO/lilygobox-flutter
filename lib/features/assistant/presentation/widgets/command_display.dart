import 'dart:io';

/// 展示格式使用的 shell 类型，与参数引用规则保持一致。
String get aiCommandDisplayLanguage =>
    Platform.isWindows ? 'powershell' : 'shell';

/// 参照 Codex 对参数逐项引用；只用于展示，不参与进程启动或重新解析。
/// Windows 使用 PowerShell 的单引号规则，其他平台使用 POSIX shell 规则。
/// 保留 shell 包装、全部参数和脚本换行，便于核对实际请求。
String formatAiCommand(Map<String, Object?> arguments, {bool? windows}) {
  final executable = arguments['executable'] as String? ?? '';
  final values = arguments['arguments'];
  final parts = values is List
      ? values.whereType<String>().toList()
      : <String>[];
  final isWindows = windows ?? Platform.isWindows;
  final safe = isWindows
      ? RegExp(r'^[a-zA-Z0-9_./:\\=+-]+$')
      : RegExp(r'^[a-zA-Z0-9_./:@%+=,-]+$');
  String quote(String value) {
    if (value.isNotEmpty && safe.hasMatch(value)) return value;
    final escaped = isWindows
        ? value.replaceAllMapped(
            RegExp("['\u2018\u2019]"),
            (match) => '${match[0]}${match[0]}',
          )
        : value.replaceAll("'", "'\"'\"'");
    return "'$escaped'";
  }

  final program = quote(executable);
  final prefix = isWindows && program.startsWith("'") ? '& ' : '';
  return '$prefix${[program, ...parts.map(quote)].join(' ')}';
}
