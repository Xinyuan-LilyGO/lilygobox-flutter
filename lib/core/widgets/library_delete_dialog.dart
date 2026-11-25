import 'package:material_ui/material_ui.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'action_button.dart';
import 'app_scroll_behavior.dart';
import 'confirmation_dialog.dart';
import 'dialog_style.dart';

typedef LibraryAgentReference = ({String id, String title, bool recycled});

Future<bool?> showLibraryDeleteDialog({
  required BuildContext context,
  required AppTheme theme,
  required String actionKey,
  required String title,
  required String description,
  String? confirmLabel,
  ({String title, List<String> names})? items,
  Iterable<LibraryAgentReference> agents = const [],
}) {
  final l10n = context.l10n;
  final style = AppDialogStyle.descriptionStyle(theme);
  final entryStyle = AppDialogStyle.fieldTitleStyle(theme)
      .copyWith(fontWeight: FontWeight.normal);
  final sections = [
    if (items case (:final title, :final names))
      _LibraryDeleteSection(
        theme: theme,
        title: title,
        entries: [for (final name in names) Text(name, style: entryStyle)],
      ),
    if (agents.isNotEmpty)
      _LibraryDeleteSection(
        theme: theme,
        title: confirmLabel == null
            ? null
            : l10n.aiRoleplayLibraryAgentsToUnbind(agents.length),
        entries: [
          for (final agent in agents)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                Text(
                  agent.recycled
                      ? l10n.aiRoleplayLibraryRecycledAgent(agent.title)
                      : agent.title,
                  style: entryStyle,
                ),
                Text(l10n.aiAgentIdValue(agent.id), style: style),
              ],
            ),
        ],
      ),
  ];
  const bodyPadding = EdgeInsets.symmetric(horizontal: 24);
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      theme: theme,
      title: title,
      constraints: const BoxConstraints(maxWidth: 440),
      contentPadding: const EdgeInsets.only(top: 16, bottom: 24),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Padding(
            padding: bodyPadding,
            child: Text(description, style: style),
          ),
          if (sections.isNotEmpty)
            Flexible(
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(dialogContext).copyWith(
                  crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                  mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                ),
                child: SingleChildScrollView(
                  padding: bodyPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: sections,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        AppActionButton.dialog(
          key: ValueKey('cancel-$actionKey'),
          theme: theme,
          label: confirmLabel == null ? l10n.close : l10n.settingsCancel,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        if (confirmLabel != null)
          AppActionButton.dialog(
            key: ValueKey('confirm-$actionKey'),
            theme: theme,
            label: confirmLabel,
            destructive: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
      ],
    ),
  );
}

class _LibraryDeleteSection extends StatelessWidget {
  const _LibraryDeleteSection({
    required this.theme,
    required this.title,
    required this.entries,
  });

  final AppTheme theme;
  final String? title;
  final List<Widget> entries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [
      if (title case final heading?)
        Semantics(
          header: true,
          child: Text(
            heading,
            style: AppDialogStyle.fieldTitleStyle(theme).copyWith(
              color: theme.textColorPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      Padding(
        padding: EdgeInsetsDirectional.only(start: title == null ? 0 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: entries,
        ),
      ),
    ],
  );
}
