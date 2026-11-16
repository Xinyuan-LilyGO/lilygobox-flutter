import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../domain/memory_conflict.dart';

Future<bool> reviewMemoryImport(
  BuildContext context,
  AppTheme theme,
  List<MemoryImportItem> items,
) => showDialog<bool>(
  context: context,
  builder: (context) => _Review(theme: theme, items: items),
).then((v) => v ?? false);

class _Review extends StatefulWidget {
  const _Review({required this.theme, required this.items});
  final AppTheme theme;
  final List<MemoryImportItem> items;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  late final drafts = [
    for (final item in widget.items)
      MemoryImportItem(
          incoming: item.incoming,
          target: item.target,
          existing: item.existing,
          incomingPrevious: item.incomingPrevious,
          duplicate: item.duplicate,
        )
        ..content = item.content
        ..resolution = item.resolution,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = widget.theme;
    return AppDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      theme: theme,
      title: l.agentMemoryReview,
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * .6).clamp(
              120.0,
              560.0,
            ),
          ),
          child: ListView.builder(
            key: const ValueKey('memory-review-list'),
            shrinkWrap: true,
            primary: false,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: drafts.length,
            itemBuilder: (context, i) {
              final item = drafts[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  key: ValueKey('memory-review-card-$i'),
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item.duplicate
                              ? l.agentMemoryDuplicate
                              : item.conflict
                              ? l.agentMemoryConflict
                              : l.agentMemoryNew,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.textColorSecondary,
                          ),
                        ),
                        if (item.conflict) ...[
                          const SizedBox(height: 10),
                          Text(
                            l.agentMemoryExisting,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textColorTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (item.existing ?? item.incomingPrevious)!['content']
                                as String,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l.agentMemoryIncoming,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textColorTertiary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          item.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: theme.textColorPrimary,
                          ),
                        ),
                        if (!item.duplicate) ...[
                          const SizedBox(height: 12),
                          SettingSelect<MemoryResolution>(
                            key: ValueKey('memory-review-resolution-$i'),
                            theme: theme,
                            surfaceColor: theme.primary,
                            value: item.resolution,
                            items: [
                              DropdownMenuItem(
                                value: MemoryResolution.skip,
                                child: Text(l.agentMemorySkip),
                              ),
                              DropdownMenuItem(
                                value: MemoryResolution.keepBoth,
                                child: Text(
                                  item.conflict
                                      ? l.agentMemoryBoth
                                      : l.agentMemoryAdd,
                                ),
                              ),
                              if (item.conflict && item.existing != null)
                                DropdownMenuItem(
                                  value: MemoryResolution.replace,
                                  child: Text(l.agentMemoryReplace),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => item.resolution = value);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        AppActionButton.dialog(
          key: const ValueKey('memory-review-cancel'),
          theme: theme,
          label: l.settingsCancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppActionButton.dialog(
          key: const ValueKey('memory-review-import'),
          theme: theme,
          label: l.agentStorageImport,
          primary: true,
          onPressed: () {
            for (var i = 0; i < drafts.length; i++) {
              widget.items[i].resolution = drafts[i].resolution;
            }
            Navigator.pop(context, true);
          },
        ),
      ],
    );
  }
}
