/*
 * @Description: 将 AI 配置与请求错误映射为当前语言的可恢复提示。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-12 15:00:41
 */

import 'dart:async';

import '../../../../generated/l10n/app_localizations.dart';
import '../../data/chat_completion_client.dart';
import '../../domain/models.dart';
import '../../domain/web_failure.dart';

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
  AiWebFailure(:final problem, :final statusCode) => switch (problem) {
    AiWebProblem.invalidUrl => l10n.aiWebInvalidUrl,
    AiWebProblem.unsupportedScheme => l10n.aiWebUnsupportedScheme,
    AiWebProblem.unsupportedPort => l10n.aiWebUnsupportedPort,
    AiWebProblem.credentialsNotAllowed => l10n.aiWebCredentialsNotAllowed,
    AiWebProblem.blockedAddress => l10n.aiWebBlockedAddress,
    AiWebProblem.dns => l10n.aiWebDns,
    AiWebProblem.connection => l10n.aiWebConnection,
    AiWebProblem.timeout => l10n.aiWebTimeout,
    AiWebProblem.tls => l10n.aiWebTls,
    AiWebProblem.httpStatus => switch (statusCode) {
      401 => l10n.aiWebUnauthorized,
      403 => l10n.aiWebForbidden,
      404 => l10n.aiWebNotFound,
      429 => l10n.aiWebRateLimited,
      final code? when code >= 500 => l10n.aiWebServerError(code),
      _ => l10n.aiWebHttpStatus(statusCode ?? 0),
    },
    AiWebProblem.invalidRedirect => l10n.aiWebInvalidRedirect,
    AiWebProblem.redirectLoop => l10n.aiWebRedirectLoop,
    AiWebProblem.tooManyRedirects => l10n.aiWebTooManyRedirects,
    AiWebProblem.contentType => l10n.aiWebContentType,
    AiWebProblem.encoding => l10n.aiWebEncoding,
    AiWebProblem.tooLarge => l10n.aiWebTooLarge,
    AiWebProblem.emptyContent => l10n.aiWebEmptyContent,
    AiWebProblem.cancelled => l10n.aiWebCancelled,
  },
  TimeoutException() => l10n.aiRequestTimeout,
  // 服务端错误保留原文；本地错误始终使用本地化消息。
  AiRequestException(:final message) => message,
  _ => l10n.aiRequestFailed,
};
