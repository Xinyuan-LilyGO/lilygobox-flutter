import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/language_provider.dart';
import '../theme/definition.dart';
import 'action_button.dart';
import 'app_scroll_behavior.dart';
import 'confirmation_dialog.dart';
import 'desktop_card_selection.dart';
import 'dialog_style.dart';

class CardTransferDialog<Item> extends StatefulWidget {
  const CardTransferDialog({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.items,
    required this.idOf,
    required this.buildInfo,
    required this.confirmLabel,
    required this.keyPrefix,
    this.secondaryDescription,
  });

  final AppTheme theme;
  final String title;
  final String description;
  final String? secondaryDescription;
  final List<Item> items;
  final String Function(Item) idOf;
  final Widget Function(Item) buildInfo;
  final String Function(int) confirmLabel;
  final String keyPrefix;

  @override
  State<CardTransferDialog<Item>> createState() =>
      _CardTransferDialogState<Item>();
}

class _CardTransferDialogState<Item> extends State<CardTransferDialog<Item>> {
  final _selection = DesktopCardSelection();
  final _focus = FocusNode();
  late final _ids = widget.items.map(widget.idOf).toList();

  @override
  void initState() {
    super.initState();
    _selection.selectAll(_ids);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    final items = widget.items;
    final count = _selection.selected.length;
    return DesktopCardSelectionRegion(
      focusNode: _focus,
      selection: _selection,
      ids: _ids,
      onChanged: () => setState(() {}),
      onDelete: null,
      child: AppDialog(
        theme: theme,
        title: widget.title,
        constraints: const BoxConstraints(maxWidth: 520),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SizedBox(
            width: 468,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        widget.description,
                        style: AppDialogStyle.descriptionStyle(theme),
                      ),
                      if (widget.secondaryDescription case final description?)
                        Text(
                          description,
                          style: AppDialogStyle.descriptionStyle(theme),
                        ),
                    ],
                  ),
                ),
                if (items.isNotEmpty)
                  Flexible(
                    child: ScrollbarTheme(
                      data: ScrollbarTheme.of(context).copyWith(
                        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                        mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 2,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildCard(items[index]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          DesktopCardSelectionTarget(
            child: AppActionButton.dialog(
              theme: theme,
              label: items.isEmpty ? l10n.close : l10n.settingsCancel,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (items.isNotEmpty)
            DesktopCardSelectionTarget(
              child: AppActionButton.dialog(
                key: ValueKey('${widget.keyPrefix}-confirm'),
                theme: theme,
                primary: true,
                label: widget.confirmLabel(count),
                onPressed: count == 0
                    ? null
                    : () => Navigator.pop(
                        context,
                        items
                            .where(
                              (item) => _selection.selected.contains(
                                widget.idOf(item),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(Item item) {
    final theme = widget.theme;
    final id = widget.idOf(item);
    final selected = _selection.selected.contains(id);
    final radius = BorderRadius.circular(12);
    return DesktopCardSelectionMenu(
      key: ValueKey('${widget.keyPrefix}-card-$id'),
      id: id,
      theme: theme,
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 167),
          curve: Curves.fastOutSlowIn,
          decoration: BoxDecoration(
            color: theme.secondary,
            border: Border.all(
              color: selected ? theme.basePrimary : Colors.transparent,
            ),
            borderRadius: radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              onTap: () {
                final keyboard = HardwareKeyboard.instance;
                _focus.requestFocus();
                setState(
                  () => _selection.select(
                    id,
                    _ids,
                    control:
                        !keyboard.isShiftPressed ||
                        keyboard.isControlPressed ||
                        keyboard.isMetaPressed,
                    shift: keyboard.isShiftPressed,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: widget.buildInfo(item),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
