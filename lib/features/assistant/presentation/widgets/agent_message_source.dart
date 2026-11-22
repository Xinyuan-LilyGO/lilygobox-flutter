import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../domain/models.dart';
import 'task_navigation_scope.dart';

class AgentMessageSource extends StatelessWidget {
  const AgentMessageSource({
    super.key,
    required this.message,
    required this.theme,
    this.linkToAgent = false,
  });

  final AiMessage message;
  final AppTheme theme;
  final bool linkToAgent;

  @override
  Widget build(BuildContext context) {
    if (message.toolName != 'agent_message') return const SizedBox.shrink();
    final arguments = message.toolArguments;
    final sourceId = arguments?['source_agent_id'] as String?;
    final title = arguments?['source_agent_title'] as String? ?? sourceId;
    if (title == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final (label, icon) = switch (arguments?['source_agent_kind']) {
      'primary' => (l10n.aiTopologyMessageFromMain(title), Symbols.hub_rounded),
      'permanent' => (
        l10n.aiTopologyMessageFromChild(title),
        Symbols.account_tree_rounded,
      ),
      _ => (l10n.aiTopologyMessageFrom(title), null),
    };
    final navigation = linkToAgent && sourceId != null
        ? TaskNavigationScope.maybeOf(context)
        : null;
    final style = TextStyle(
      fontSize: 11,
      color: theme.textColorTertiary,
      fontWeight: FontWeight.normal,
    );
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, fill: 1, color: style.color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            key: ValueKey('agent-message-source-${message.id}'),
            style: style,
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (linkToAgent)
          InkWell(
            onTap: navigation == null || sourceId == null
                ? null
                : () => navigation.openTask(sourceId),
            borderRadius: BorderRadius.circular(4),
            child: heading,
          )
        else
          heading,
        if (sourceId != null && sourceId.isNotEmpty)
          Text(
            l10n.aiAgentIdValue(sourceId),
            key: ValueKey('agent-message-source-id-${message.id}'),
            style: style,
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
