import 'dart:convert';

import '../../../../generated/l10n/app_localizations.dart';
import '../../domain/command_policy.dart';

String aiCommandRiskText(AppLocalizations l10n, AiCommandRisk risk) =>
    switch (risk) {
      AiCommandRisk.forceDelete => l10n.aiCommandRiskForceDelete,
      AiCommandRisk.discardChanges => l10n.aiCommandRiskDiscardChanges,
      AiCommandRisk.diskWrite => l10n.aiCommandRiskDiskWrite,
      AiCommandRisk.opaqueScript => l10n.aiCommandRiskOpaqueScript,
    };

String aiCommandPolicyFailureText(
  AppLocalizations l10n,
  AiCommandPolicyProblem problem,
) => switch (problem) {
  AiCommandPolicyProblem.forbidden => l10n.aiCommandPolicyForbidden,
  AiCommandPolicyProblem.invalidRules => l10n.aiCommandPolicyInvalidRules,
  AiCommandPolicyProblem.approvalRequired =>
    l10n.aiCommandPolicyApprovalRequired,
  AiCommandPolicyProblem.changed => l10n.aiCommandPolicyChanged,
};

String? aiCommandPolicyOutputText(AppLocalizations l10n, String output) {
  try {
    final value = jsonDecode(output);
    if (value is! Map || value['ok'] != false) return null;
    for (final problem in AiCommandPolicyProblem.values) {
      if (value['error_code'] == 'command_${problem.name}') {
        final message = aiCommandPolicyFailureText(l10n, problem);
        final rules = value['rules'];
        return rules is List && rules.isNotEmpty
            ? '$message\n${l10n.aiCommandMatchedRules}: ${rules.join(', ')}'
            : message;
      }
    }
  } catch (_) {
    // 旧记录或其他工具的原始错误继续按原文展示。
  }
  return null;
}
