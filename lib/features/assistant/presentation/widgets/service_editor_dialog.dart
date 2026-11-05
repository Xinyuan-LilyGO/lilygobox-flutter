/*
 * @Description: 在独立弹窗中编辑模型服务，支持读取模型列表并在确认后提交。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-04 15:26:02
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../domain/models.dart';
import '../../state/provider.dart';
import 'error_text.dart';

class ServiceEditorDialog extends StatefulWidget {
  const ServiceEditorDialog({
    super.key,
    required this.theme,
    required this.assistant,
    this.service,
  });
  final AppTheme theme;
  final AiAssistantProvider assistant;
  final AiModelService? service;

  @override
  State<ServiceEditorDialog> createState() => _ServiceEditorDialogState();
}

class _ServiceEditorDialogState extends State<ServiceEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _models;
  final _key = TextEditingController();
  late AiApiProtocol _protocol;
  bool _working = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _protocol = service?.protocol ?? AiApiProtocol.openAiChatCompletions;
    _name = TextEditingController(text: service?.name ?? '');
    _address = TextEditingController(text: service?.baseUrl ?? '');
    _models = TextEditingController(text: service?.models.join('\n') ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _models.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final id = await widget.assistant.saveService(
        id: widget.service?.id,
        name: _name.text,
        protocol: _protocol,
        baseUrl: _address.text,
        models: _models.text.split(RegExp(r'[,，\n\r]+')),
        apiKey: _key.text,
      );
      if (mounted) {
        setState(() => _working = false);
        Navigator.pop(context, id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _working = false;
        });
      }
    }
  }

  Future<void> _discover() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final models = await widget.assistant.discoverModels(
        baseUrl: _address.text,
        apiKey: _key.text,
        serviceId: widget.service?.id,
      );
      if (models.isEmpty) {
        throw const AiConfigurationException(AiProblem.modelsRequired);
      }
      if (mounted) _models.text = models.join('\n');
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;
    return PopScope(
      canPop: !_working,
      child: AppDialog(
        theme: theme,
        title: widget.service == null
            ? l10n.aiAddModelService
            : l10n.aiEditService,
        constraints: const BoxConstraints(maxWidth: 540),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            // 桌面滚动条绘制在视口内侧，为滚动条和控件之间预留空隙。
            padding: const EdgeInsetsDirectional.only(end: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldSection(
                  l10n.aiServiceName,
                  l10n.aiServiceNameDescription,
                  Semantics(
                    label: l10n.aiServiceName,
                    child: _field(_name, 'ai-service-name'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiProtocolLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiProtocolDescription,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.textColorTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                SettingSelect<AiApiProtocol>(
                  key: const ValueKey('ai-service-protocol'),
                  theme: theme,
                  value: _protocol,
                  items: [
                    DropdownMenuItem(
                      value: AiApiProtocol.openAiChatCompletions,
                      child: Text(l10n.aiProtocolChatCompletions),
                    ),
                    DropdownMenuItem(
                      value: AiApiProtocol.openAiResponses,
                      child: Text(l10n.aiProtocolResponses),
                    ),
                  ],
                  onChanged: _working
                      ? null
                      : (protocol) => setState(() {
                          if (protocol != null) _protocol = protocol;
                        }),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiBaseUrlLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  l10n.aiBaseUrlDescription,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textColorTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: l10n.aiBaseUrlLabel,
                  child: _field(_address, 'ai-service-address'),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiApiKeyLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.assistant.hasServiceKey(widget.service?.id)
                      ? l10n.aiApiKeyStored
                      : l10n.aiApiKeyDescription,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textColorTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: l10n.aiApiKeyLabel,
                  child: _field(_key, 'ai-service-key', secret: true),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiModelLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hint = Text(
                      l10n.aiModelsHint,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: theme.textColorTertiary,
                      ),
                    );
                    final button = AppActionButton(
                      key: const ValueKey('ai-discover-models'),
                      theme: theme,
                      label: l10n.aiFetchModels,
                      onPressed: _working ? null : _discover,
                    );
                    if (constraints.maxWidth < 380) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          hint,
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: button,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: hint),
                        const SizedBox(width: 12),
                        button,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: l10n.aiModelLabel,
                  child: SettingControlledTextField(
                    key: const ValueKey('ai-service-models'),
                    theme: theme,
                    controller: _models,
                    enabled: !_working,
                    minLines: 3,
                    maxLines: 5,
                  ),
                ),
                if (_working)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      aiErrorText(l10n, error),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          AppActionButton(
            theme: theme,
            label: l10n.settingsCancel,
            onPressed: _working ? null : () => Navigator.pop(context),
          ),
          AppActionButton(
            key: const ValueKey('ai-confirm-service'),
            theme: theme,
            label: widget.service == null
                ? l10n.aiAddModelService
                : l10n.aiSaveService,
            primary: true,
            fontSize: 12,
            onPressed: _working ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String key, {
    bool secret = false,
  }) => SettingControlledTextField(
    key: ValueKey(key),
    theme: widget.theme,
    controller: controller,
    enabled: !_working,
    obscureText: secret,
  );

  Widget _fieldSection(String title, String description, Widget input) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.textColorSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: widget.theme.textColorTertiary,
            ),
          ),
          const SizedBox(height: 8),
          input,
        ],
      );
}
