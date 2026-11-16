/// 所有面向用户的数据导出共用的本地时间戳。
String datedExportFileName(String name, {DateTime? now}) {
  final value = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${value.year}${two(value.month)}${two(value.day)}${two(value.hour)}${two(value.minute)}';
  final dot = name.lastIndexOf('.');
  return dot > 0
      ? '${name.substring(0, dot)}-$date${name.substring(dot)}'
      : '$name-$date';
}
