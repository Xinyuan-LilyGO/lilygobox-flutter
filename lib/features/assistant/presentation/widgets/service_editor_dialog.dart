/*
 * @Description: 在独立弹窗中编辑模型服务，支持读取模型列表并在确认后提交。
 */

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/app_scroll_behavior.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/dialog_style.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../../../core/widgets/settings/select.dart';
import '../../../../core/widgets/title_bar_icon_button.dart';
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
  final Map<String, AiImageInput> _imageInputs = {};
  late String _capabilityAddress;
  late AiApiProtocol _protocol;
  late AiServicePreset _preset;
  bool _working = false;
  bool _showApiKey = false;
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
    _imageInputs.addAll(service?.imageInputs ?? {});
    _capabilityAddress = _baseUrl;
    _address.addListener(_addressChanged);
  }

  void _addressChanged() {
    if (_baseUrl == _capabilityAddress) return;
    setState(() {
      _imageInputs.clear();
      _capabilityAddress = _baseUrl;
    });
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
      _imageInputs.clear();
      _capabilityAddress = _baseUrl;
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
        imageInputs: _imageInputs,
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
      final catalog = await widget.assistant.discoverModelCatalog(
        baseUrl: _baseUrl,
        apiKey: _key.text,
        serviceId: _canReuseKey ? widget.service?.id : null,
      );
      final models = catalog.models;
      if (models.isEmpty) {
        throw const AiConfigurationException(AiProblem.modelsRequired);
      }
      if (mounted) {
        // 每次成功获取均以本次服务声明为准，缺失能力恢复为未知。
        _imageInputs
          ..clear()
          ..addAll(catalog.imageInputs);
        _models.text = models.join('\n');
      }
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
        // 横向留白放入滚动内容，滑块才能靠近弹窗边缘。
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: SizedBox(
          width: 498,
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(
              context,
            ).copyWith(crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset),
            child: SingleChildScrollView(
              controller: _formScrollController,
              key: const ValueKey('ai-service-form-scroll'),
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      style: AppDialogStyle.fieldTitleStyle(theme),
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
                              if (protocol != null && protocol != _protocol) {
                                _protocol = protocol;
                                _imageInputs.clear();
                              }
                            }),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.aiBaseUrlLabel,
                      style: AppDialogStyle.fieldTitleStyle(theme),
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
                    style: AppDialogStyle.fieldTitleStyle(theme),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.aiModelLabel,
                          style: AppDialogStyle.fieldTitleStyle(theme),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: AppActionButton(
                          key: const ValueKey('ai-discover-models'),
                          theme: theme,
                          label: l10n.aiFetchModels,
                          onPressed: _working ? null : _discover,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.aiModelsHint,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: theme.textColorTertiary,
                    ),
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
        ),
        actions: [
          AppActionButton.dialog(
            theme: theme,
            label: l10n.settingsCancel,
            onPressed: _working ? null : () => Navigator.pop(context),
          ),
          AppActionButton.dialog(
            key: const ValueKey('ai-confirm-service'),
            theme: theme,
            label: widget.service == null
                ? l10n.aiAddModelService
                : l10n.aiSaveService,
            primary: true,
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
    obscureText: secret && !_showApiKey,
    suffixIcon: secret
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              button: true,
              toggled: _showApiKey,
              child: AppTooltip(
                message: _showApiKey
                    ? context.l10n.aiHideApiKey
                    : context.l10n.aiShowApiKey,
                child: TitleBarIconButton(
                  key: const ValueKey('ai-service-key-visibility'),
                  theme: widget.theme,
                  isFocused: true,
                  icon: _showApiKey
                      ? Symbols.visibility_rounded
                      : Symbols.visibility_off_rounded,
                  iconColor: widget.theme.iconColor,
                  backgroundColor: Colors.transparent,
                  surfaceColor: AppDialogStyle.backgroundColor(widget.theme),
                  onPressed: _working
                      ? null
                      : () => setState(() => _showApiKey = !_showApiKey),
                ),
              ),
            ),
          )
        : null,
  );

  Widget _fieldSection(String title, String description, Widget input) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppDialogStyle.fieldTitleStyle(widget.theme)),
          const SizedBox(height: 4),
          Text(
            description,
            style: AppDialogStyle.descriptionStyle(widget.theme),
          ),
          const SizedBox(height: 8),
          input,
        ],
      );
}
