import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/desktop_card_selection.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../domain/models.dart';
import 'error_text.dart';

class ModelDiscoveryDialog extends StatefulWidget {
  const ModelDiscoveryDialog({
    super.key,
    required this.theme,
    required this.existingModels,
    required this.load,
  });

  final AppTheme theme;
  final Set<String> existingModels;
  final Future<AiModelCatalog> Function(Future<void> abort) load;

  @override
  State<ModelDiscoveryDialog> createState() => _ModelDiscoveryDialogState();
}

class _ModelDiscoveryDialogState extends State<ModelDiscoveryDialog> {
  final _abort = Completer<void>();
  AiModelCatalog? _catalog;
  Object? _error;
  final _selection = DesktopCardSelection();
  final _selectionFocus = FocusNode();
  Set<String> get _selectedModels => _selection.selected;

  @override
  void initState() {
    super.initState();
    _selectionFocus.requestFocus();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.load(_abort.future);
      if (mounted && !_abort.isCompleted) {
        setState(() {
          _catalog = catalog;
          _selectedModels.addAll(
            catalog.models.where(
              (model) => !widget.existingModels.contains(model),
            ),
          );
        });
      }
    } catch (error) {
      if (mounted && !_abort.isCompleted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    _selectionFocus.dispose();
    super.dispose();
  }

  void _selectModel(String model, List<String> models) {
    _selectionFocus.requestFocus();
    setState(() {
      _selection.select(
        model,
        models,
        control:
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed,
        shift: HardwareKeyboard.instance.isShiftPressed,
      );
    });
  }

  AiModelCatalog _selectedCatalog(AiModelCatalog catalog) {
    final models = catalog.models
        .where(
          (model) =>
              widget.existingModels.contains(model) ||
              _selectedModels.contains(model),
        )
        .toList();
    final included = models.toSet();
    return AiModelCatalog(
      models: models,
      imageInputs: {
        for (final entry in catalog.imageInputs.entries)
          if (included.contains(entry.key)) entry.key: entry.value,
      },
      serviceTiers: {
        for (final entry in catalog.serviceTiers.entries)
          if (included.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalog = _catalog;
    final added =
        catalog?.models
            .where((model) => !widget.existingModels.contains(model))
            .toList() ??
        const <String>[];
    final loading = catalog == null && _error == null;
    return DesktopCardSelectionRegion(
      focusNode: _selectionFocus,
      selection: _selection,
      ids: added,
      onChanged: () => setState(() {}),
      onDelete: null,
      child: AppDialog(
        key: const ValueKey('ai-model-discovery-dialog'),
        theme: widget.theme,
        title: l10n.aiFetchModels,
        constraints: const BoxConstraints(maxWidth: 520),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SizedBox(
            width: 468,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        key: const ValueKey('ai-model-discovery-summary'),
                        liveRegion: true,
                        child: Text(
                          loading
                              ? l10n.aiModelDiscoveryLoading
                              : _error != null
                              ? aiErrorText(l10n, _error!)
                              : catalog!.models.isEmpty
                              ? l10n.aiModelDiscoveryEmpty
                              : l10n.aiModelDiscoverySummary(
                                  catalog.models.length,
                                  added.length,
                                  catalog.models.length - added.length,
                                ),
                          style: TextStyle(
                            color: widget.theme.textColorSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                      if (catalog != null &&
                          catalog.models.isNotEmpty &&
                          added.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(l10n.aiModelDiscoveryUnchanged),
                        ),
                      if (added.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.aiModelDiscoveryNewModels,
                          key: const ValueKey(
                            'ai-model-discovery-list-heading',
                          ),
                          style: AppDialogStyle.fieldTitleStyle(widget.theme),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                if (added.isNotEmpty)
                  Flexible(
                    child: ScrollbarTheme(
                      data: ScrollbarTheme.of(context).copyWith(
                        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                        mainAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                      ),
                      child: SingleChildScrollView(
                        key: const ValueKey('ai-model-discovery-scroll'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 2,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final model in added)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: DesktopCardSelectionMenu(
                                  key: ValueKey(model),
                                  id: model,
                                  theme: widget.theme,
                                  child: Semantics(
                                    selected: _selectedModels.contains(model),
                                    button: true,
                                    child: GestureDetector(
                                      key: ValueKey(
                                        'ai-model-discovery-row-$model',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _selectModel(model, added),
                                      child: AnimatedContainer(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 167),
                                        curve: Curves.fastOutSlowIn,
                                        decoration: BoxDecoration(
                                          color: widget.theme.secondary,
                                          border: Border.all(
                                            color:
                                                _selectedModels.contains(model)
                                                ? widget.theme.basePrimary
                                                : Colors.transparent,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Text(
                                            model,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  widget.theme.textColorPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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
              key: const ValueKey('ai-cancel-model-discovery'),
              theme: widget.theme,
              label: loading
                  ? l10n.aiModelDiscoveryCancel
                  : l10n.settingsCancel,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (catalog != null && catalog.models.isNotEmpty)
            DesktopCardSelectionTarget(
              child: AppActionButton.dialog(
                key: const ValueKey('ai-apply-model-discovery'),
                theme: widget.theme,
                primary: true,
                label: added.isNotEmpty
                    ? l10n.aiModelDiscoveryAdd
                    : l10n.aiModelDiscoveryUpdate,
                onPressed:
                    added.isNotEmpty &&
                        _selectedModels.isEmpty &&
                        !catalog.models.any(widget.existingModels.contains)
                    ? null
                    : () => Navigator.pop(context, _selectedCatalog(catalog)),
              ),
            ),
        ],
      ),
    );
  }
}
