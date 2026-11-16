import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';

/// 没有存储管理页面承载错误时，也提供易于理解的失败说明。
String agentTransferFailureMessage(BuildContext context, Object error) {
  final l = context.l10n;
  if (error is FormatException) return l.agentStorageInvalidPackage;
  final detail = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return '${l.agentStorageFailure} $detail';
}
