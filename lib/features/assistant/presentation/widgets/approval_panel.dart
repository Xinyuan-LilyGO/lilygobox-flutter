/*
 * @Description: 在聊天输入区展示单次工具批准，保留操作详情与固定的批准按钮。
 * @Author: OpenAI Codex
 * @Date: 2026-11-11 17:07:00
 * @LastEditTime: 2026-11-12 16:21:03
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../domain/models.dart';

class AssistantApprovalPanel extends StatefulWidget {
  const AssistantApprovalPanel({
    super.key,
    required this.request,
    required this.theme,
    required this.inputFocus,
    required this.onResolve,
  });

  final AiMessage request;
  final AppTheme theme;
  final FocusNode inputFocus;
  final ValueChanged<bool> onResolve;

  @override
  State<AssistantApprovalPanel> createState() => _AssistantApprovalPanelState();
}

class _AssistantApprovalPanelState extends State<AssistantApprovalPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 输入区切换后释放焦点，避免批准期间键盘继续修改隐藏的草稿。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.inputFocus.unfocus();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final l10n = context.l10n;
    final args = widget.request.toolArguments ?? const <String, Object?>{};
    final title = switch (widget.request.toolName) {
      'read_webpage' => l10n.aiToolWeb,
      'list_directory' => l10n.aiToolList,
      'read_file' => l10n.aiToolRead,
      'write_file' => l10n.aiToolWrite,
      _ => l10n.aiActionUnknown,
    };
    final target = (args['path'] ?? args['url'] ?? '').toString();
    final resolved = args['resolved_path'] as String?;
    final style = TextStyle(color: theme.textColorSecondary, fontSize: 13);
    return DecoratedBox(
      key: const ValueKey('ai-approval-panel'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.primary.withValues(alpha: .42),
          theme.secondary,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: PopupMenuSurface.shadowsFor(theme),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(
                  320,
                  MediaQuery.sizeOf(context).height * .5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.shield_rounded,
                        fill: 1,
                        size: 20,
                        color: theme.textColorPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.aiApprovalTitle,
                          style: TextStyle(
                            color: theme.textColorPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: theme.textColorPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(target, style: style),
                            if (resolved != null && resolved != target) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${l10n.aiPermissionResolvedPath}: $resolved',
                                style: style,
                              ),
                            ],
                            if (widget.request.toolName == 'write_file') ...[
                              const SizedBox(height: 12),
                              Text(l10n.aiWritePreview, style: style),
                              const SizedBox(height: 6),
                              Text(
                                '${l10n.aiBefore}:\n${args['expected_content'] ?? ''}\n\n${l10n.aiAfter}:\n${args['content'] ?? ''}',
                                style: TextStyle(
                                  color: theme.textColorPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppDialogScope(
                    surfaceColor: theme.primary,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppActionButton.dialog(
                          key: const ValueKey('ai-approval-deny'),
                          theme: theme,
                          label: l10n.aiReject,
                          onPressed: () => widget.onResolve(false),
                        ),
                        AppActionButton.dialog(
                          key: const ValueKey('ai-approval-allow'),
                          theme: theme,
                          label: l10n.aiApprove,
                          primary: true,
                          onPressed: () => widget.onResolve(true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
