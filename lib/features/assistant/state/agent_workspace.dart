/*
 * @Description: 定义独立子智能体工作空间及模型会话信息。
 */
import '../domain/agent_link.dart';
import '../domain/permissions.dart';
import '../domain/reasoning.dart';
import 'provider.dart';

enum AiWorkspaceKind { primary, permanent }

/// A visible undirected task link; hierarchy links retain the child task ID.
class AiTaskConnection {
  const AiTaskConnection({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.isHierarchy,
  });
  final String id;
  final String fromId;
  final String toId;
  final bool isHierarchy;
}

class AiAgentWorkspace {
  AiAgentWorkspace({
    required this.id,
    required this.title,
    required this.task,
    required this.assistant,
    required this.createdAt,
    this.parentId,
    this.kind = AiWorkspaceKind.permanent,
  });
  final String id;
  String title;
  final String task;
  String? parentId;
  AiWorkspaceKind kind;
  bool closed = false;
  String get model =>
      assistant.selectedModel ?? assistant.workspaceSavedModel ?? '';
  String get serviceId =>
      assistant.selectedService?.id ?? assistant.workspaceSavedServiceId ?? '';
  final DateTime createdAt;
  final AiAssistantProvider assistant;
  bool get busy => !closed && assistant.busy;
  bool get needsAttention =>
      !closed &&
      (assistant.pendingApproval != null || assistant.pendingUserInput != null);
  String get status => closed
      ? 'closed'
      : assistant.workspaceSelectionUnavailable
      ? 'unavailable'
      : assistant.stopRequested
      ? 'stopped'
      : needsAttention
      ? 'waiting'
      : busy
      ? 'running'
      : assistant.error != null
      ? 'failed'
      : assistant.messages.lastOrNull?.status?.name == 'stopped'
      ? 'stopped'
      : assistant.messages.isEmpty
      ? 'ready'
      : 'completed';
  String get result =>
      assistant.messages
          .where((m) => m.role == 'assistant')
          .map((m) => m.content)
          .where((text) => text.isNotEmpty)
          .lastOrNull ??
      '';
  static const maximumResultCharacters = 16000;
  Map<String, Object?> toToolResult() => {
    'agent_id': id,
    'url': agentLink(id),
    'kind': kind.name,
    'parent_id': parentId,
    'title': title,
    'status': status,
    'model': model,
    'reasoning_effort': assistant.reasoningEffort?.name,
    'processing_speed': assistant.processingSpeed.name,
    'service_id': serviceId,
    'service_name': assistant.selectedService?.name,
    'result': result.length > maximumResultCharacters
        ? result.substring(0, maximumResultCharacters)
        : result,
    'result_truncated': result.length > maximumResultCharacters,
  };
}

/// Independent conversation and configuration snapshot, excluding credentials.
class AiTaskCardCopy {
  AiTaskCardCopy(
    AiAgentWorkspace source, {
    Iterable<String> connectedSourceIds = const [],
  }) : sourceId = source.id,
       title = source.title,
       kind = source.kind,
       task = source.task,
       parentId = source.parentId,
       serviceId = source.serviceId,
       model = source.model,
       modelSelectionUnavailable =
           source.assistant.workspaceSelectionUnavailable,
       permissions = source.assistant.permissions,
       effort = source.assistant.reasoningEffort,
       processingSpeed = source.assistant.processingSpeed,
       conversation = source.assistant.snapshotConversationFork(),
       connectedSourceIds = List.unmodifiable(connectedSourceIds);
  final AiWorkspaceKind kind;
  final String sourceId;
  final String title;
  final String task;
  final String? parentId;
  final String serviceId;
  final String model;
  final bool modelSelectionUnavailable;
  final AiPermissions permissions;
  final AiReasoningEffort? effort;
  final AiProcessingSpeed processingSpeed;
  final AiConversationFork conversation;
  final List<String> connectedSourceIds;
}
