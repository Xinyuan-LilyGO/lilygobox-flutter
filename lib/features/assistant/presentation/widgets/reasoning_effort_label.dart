/*
 * @Description: 为模型菜单与每轮处理记录统一提供思考强度的本地化名称。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 13:45:16
 * @LastEditTime: 2026-11-10 13:53:32
 */

import '../../../../generated/l10n/app_localizations.dart';
import '../../domain/reasoning.dart';

String reasoningEffortLabel(AppLocalizations l10n, AiReasoningEffort effort) =>
    switch (effort) {
      AiReasoningEffort.none => l10n.aiReasoningNone,
      AiReasoningEffort.minimal => l10n.aiReasoningMinimal,
      AiReasoningEffort.low => l10n.aiReasoningLow,
      AiReasoningEffort.medium => l10n.aiReasoningMedium,
      AiReasoningEffort.high => l10n.aiReasoningHigh,
      AiReasoningEffort.xhigh => l10n.aiReasoningXhigh,
      AiReasoningEffort.max => l10n.aiReasoningMax,
      AiReasoningEffort.ultra => l10n.aiReasoningUltra,
    };
