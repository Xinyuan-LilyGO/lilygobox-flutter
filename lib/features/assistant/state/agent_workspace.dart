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

/// Explicit approval snapshot for joining two hierarchy trees.
class AiTaskTreeMerge {
  const AiTaskTreeMerge({
    required this.fromId,
    required this.toId,
    required this.sourceRootId,
    required this.targetRootId,
    required this.rootId,
    required this.parentId,
    required this.changesRole,
    required this.fromKind,
    required this.toKind,
    required this.sourceRootKind,
    required this.targetRootKind,
    required this.previousParentId,
    required this.detachedConnectionIds,
  });
  final String fromId;
  final String toId;
  final String sourceRootId;
  final String targetRootId;
  final String rootId;
  final String parentId;
  final String? previousParentId;
  final List<String> detachedConnectionIds;
  final bool changesRole;
  final AiWorkspaceKind fromKind;
  final AiWorkspaceKind toKind;
  final AiWorkspaceKind sourceRootKind;
  final AiWorkspaceKind targetRootKind;

  bool matches(AiTaskTreeMerge other) =>
      fromId == other.fromId &&
      toId == other.toId &&
      sourceRootId == other.sourceRootId &&
      targetRootId == other.targetRootId &&
      rootId == other.rootId &&
      parentId == other.parentId &&
      changesRole == other.changesRole &&
      fromKind == other.fromKind &&
      toKind == other.toKind &&
      sourceRootKind == other.sourceRootKind &&
      targetRootKind == other.targetRootKind &&
      previousParentId == other.previousParentId &&
      detachedConnectionIds.length == other.detachedConnectionIds.length &&
      detachedConnectionIds.indexed.every(
        (entry) => entry.$2 == other.detachedConnectionIds[entry.$1],
      );
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
       permissions = source.assistant.permissions,
       effort = source.assistant.reasoningEffort,
       conversation = source.assistant.snapshotConversationFork(),
       connectedSourceIds = List.unmodifiable(connectedSourceIds);
  final AiWorkspaceKind kind;
  final String sourceId;
  final String title;
  final String task;
  final String? parentId;
  final String serviceId;
  final String model;
  final AiPermissions permissions;
  final AiReasoningEffort? effort;
  final AiConversationFork conversation;
  final List<String> connectedSourceIds;
}
