/*
 * @Description: 在独立弹窗中编辑模型服务，支持读取模型列表并在确认后提交。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 12:04:44
 * @LastEditTime: 2026-11-09 10:36:06
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
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
  final _formScrollController = ScrollController();
  late AiApiProtocol _protocol;
  late AiServicePreset _preset;
  bool _working = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _preset = service?.preset ?? AiServicePreset.custom;
    _protocol = service?.protocol ?? AiApiProtocol.openAiChatCompletions;
    _name = TextEditingController(text: service?.name ?? '');
    _address = TextEditingController(text: service?.baseUrl ?? '');
    _models = TextEditingController(text: service?.models.join('\n') ?? '');
  }

  String get _baseUrl => _preset.baseUrl ?? _address.text;
  AiApiProtocol get _apiProtocol => _preset.protocol ?? _protocol;

  bool get _mustEnterKey => switch (widget.service) {
    final service? => widget.assistant.hasServiceKey(service.id),
    null => false,
  };

  bool get _canReuseKey {
    final address = Uri.tryParse(_baseUrl);
    return widget.assistant.hasServiceKey(widget.service?.id) &&
        address != null &&
        ['https', 'http'].contains(address.scheme) &&
        address.host.isNotEmpty &&
        widget.service?.preset == _preset &&
        address.origin == Uri.parse(widget.service!.baseUrl).origin;
  }

  void _changePreset(AiServicePreset? preset) {
    if (preset == null || preset == _preset) return;
    setState(() {
      _preset = preset;
      _key.clear();
      _models.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _models.dispose();
    _key.dispose();
    _formScrollController.dispose();
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
        protocol: _apiProtocol,
        baseUrl: _baseUrl,
        preset: _preset,
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
    _revealModelStatus();
    try {
      final models = await widget.assistant.discoverModels(
        baseUrl: _baseUrl,
        apiKey: _key.text,
        serviceId: _canReuseKey ? widget.service?.id : null,
      );
      if (models.isEmpty) {
        throw const AiConfigurationException(AiProblem.modelsRequired);
      }
      if (mounted) _models.text = models.join('\n');
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _revealModelStatus();
      }
    }
  }

  void _revealModelStatus() {
    // 等待进度条或模型列表完成布局，再露出表单底部，避免内容被视口裁切。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_formScrollController.hasClients) return;
      final target = _formScrollController.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _formScrollController.jumpTo(target);
      } else {
        _formScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
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
            controller: _formScrollController,
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
                _fieldSection(
                  l10n.aiProviderLabel,
                  l10n.aiProviderDescription,
                  SettingSelect<AiServicePreset>(
                    key: const ValueKey('ai-service-preset'),
                    theme: theme,
                    surfaceColor: theme.materialColors.surfaceContainerHigh,
                    value: _preset,
                    items: [
                      DropdownMenuItem(
                        value: AiServicePreset.custom,
                        child: Text(l10n.aiProviderCustom),
                      ),
                      DropdownMenuItem(
                        value: AiServicePreset.deepSeek,
                        child: Text(l10n.aiProviderDeepseek),
                      ),
                      DropdownMenuItem(
                        value: AiServicePreset.openAi,
                        child: Text(l10n.aiProviderOpenAi),
                      ),
                    ],
                    onChanged: _working ? null : _changePreset,
                  ),
                ),
                const SizedBox(height: 16),
                if (_preset == AiServicePreset.custom) ...[
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
                    surfaceColor: theme.materialColors.surfaceContainerHigh,
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
                ],
                Text(
                  l10n.aiApiKeyLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _canReuseKey
                      ? l10n.aiApiKeyStored
                      : _mustEnterKey
                      ? l10n.aiKeyRequired
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
