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
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/popup_menu_surface.dart';
import '../../domain/command_policy.dart';
import '../../domain/models.dart';
import '../../domain/permissions.dart';
import 'code_block.dart';
import 'command_display.dart';
import 'command_policy_text.dart';
import 'permission_labels.dart';

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
      'run_command' => l10n.aiToolCommand,
      _ => l10n.aiActionUnknown,
    };
    final command = widget.request.toolName == 'run_command';
    final commandReason = args['reason']?.toString().trim() ?? '';
    final commandDirectory =
        (args['resolved_path'] ?? args['working_directory'])?.toString() ?? '';
    final safetyApproval = command && args['command_safety_approval'] == true;
    final category = AiPermissionCategory.values
        .where((value) => value.name == args['permission_category'])
        .firstOrNull;
    final commandDescription = <String>[
      if (safetyApproval) ...[
        for (final risk in AiCommandRisk.values.where(
          (value) =>
              (args['command_risks'] as List?)?.contains(value.name) == true,
        ))
          aiCommandRiskText(l10n, risk),
        if ((args['command_rules'] as List?)?.isNotEmpty == true) ...[
          l10n.aiCommandRulePrompt,
          '${l10n.aiCommandMatchedRules}: ${(args['command_rules'] as List).join(', ')}',
        ],
      ],
      if (command) l10n.aiCommandApprovalNotice,
    ].join(' ');
    final heading = safetyApproval
        ? l10n.aiCommandSafetyTitle
        : command && category != null
        ? aiPermissionCategoryLabel(l10n, category)
        : l10n.aiApprovalTitle;
    final target = (args['path'] ?? args['url'] ?? args['executable'] ?? '')
        .toString();
    final resolved = args['resolved_path'] as String?;
    final style = TextStyle(color: theme.textColorSecondary, fontSize: 13);
    final fieldTitleStyle = style.copyWith(
      color: theme.textColorPrimary,
      fontWeight: FontWeight.w500,
    );
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
          key: const ValueKey('ai-approval-surface'),
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
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
                            heading,
                            style: TextStyle(
                              color: theme.textColorPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ScrollbarTheme(
                      data: ScrollbarTheme.of(context).copyWith(
                        crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
                      ),
                      child: Scrollbar(
                        key: const ValueKey('ai-approval-scrollbar'),
                        controller: _scroll,
                        child: ScrollConfiguration(
                          behavior: const AppScrollBehavior(scrollbars: false),
                          child: SingleChildScrollView(
                            key: const ValueKey('ai-approval-scroll'),
                            controller: _scroll,
                            // 视口延伸到内层表面边缘，正文另留通道，避免滑块覆盖文字。
                            padding: const EdgeInsets.only(left: 16, right: 20),
                            child: SelectionArea(
                              child: Column(
                                key: const ValueKey(
                                  'ai-approval-scroll-content',
                                ),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (title != heading) ...[
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: theme.textColorPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (!command) Text(target, style: style),
                                  if (command) ...[
                                    // 说明连续排版，宽度不足时自然折行，不插入强制换行。
                                    Text(
                                      commandDescription,
                                      key: const ValueKey(
                                        'ai-approval-description',
                                      ),
                                      style: style.copyWith(height: 1.5),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.aiCommandFull,
                                      style: fieldTitleStyle,
                                    ),
                                    const SizedBox(height: 6),
                                    ChatCodeBlock(
                                      key: const ValueKey(
                                        'ai-approval-full-command',
                                      ),
                                      text: formatAiCommand(args),
                                      language: aiCommandDisplayLanguage,
                                      theme: theme,
                                      backgroundColor: theme.secondary,
                                      maxBodyHeight: 160,
                                      initialSoftWrap: true,
                                    ),
                                    if (commandReason.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.aiCommandReason,
                                        style: fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(commandReason, style: style),
                                    ],
                                    if (commandDirectory.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.aiCommandDirectory,
                                        style: fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(commandDirectory, style: style),
                                    ],
                                  ],
                                  if (!command &&
                                      resolved != null &&
                                      resolved != target) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${l10n.aiPermissionResolvedPath}: $resolved',
                                      style: style,
                                    ),
                                  ],
                                  if (widget.request.toolName ==
                                      'write_file') ...[
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppDialogScope(
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
