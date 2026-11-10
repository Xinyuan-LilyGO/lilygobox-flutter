/*
 * @Description: 将 AI 配置与请求错误映射为当前语言的可恢复提示。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-10 17:19:17
 */

import 'dart:async';

import '../../../../generated/l10n/app_localizations.dart';
import '../../data/chat_completion_client.dart';
import '../../domain/models.dart';

String aiErrorText(AppLocalizations l10n, Object error) => switch (error) {
  AiConfigurationException(:final problem) => switch (problem) {
    AiProblem.invalidAddress => l10n.aiInvalidAddress,
    AiProblem.nameRequired => l10n.aiNameRequired,
    AiProblem.modelsRequired => l10n.aiModelsRequired,
    AiProblem.keyRequired => l10n.aiKeyRequired,
    AiProblem.storage => l10n.aiStorageError,
    AiProblem.noService => l10n.aiNoServices,
    AiProblem.busy => l10n.aiServiceBusy,
    AiProblem.invalidResponse => l10n.aiInvalidResponse,
    AiProblem.request => l10n.aiRequestFailed,
    AiProblem.timeout => l10n.aiRequestTimeout,
    AiProblem.imageUnsupported => l10n.aiImageUnsupported,
  },
  TimeoutException() => l10n.aiRequestTimeout,
  // 服务端错误保留原文；本地错误始终使用本地化消息。
  AiRequestException(:final message) => message,
  _ => l10n.aiRequestFailed,
};
