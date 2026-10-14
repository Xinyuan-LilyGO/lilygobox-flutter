/*
 * @Description: 编辑设备名称，校验长度并等待设备保存确认。
 * @Author: LILYGO_L
 * @Date: 2026-10-14 00:00:00
 * @LastEditTime: 2026-10-14 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/settings/fields.dart';
import '../../domain/device_control.dart';

class DeviceNameDialog extends StatefulWidget {
  const DeviceNameDialog({
    super.key,
    required this.theme,
    required this.name,
    required this.onSave,
    this.errorCode,
  });

  final AppTheme theme;
  final String name;
  final Future<bool> Function(String) onSave;
  final String? Function()? errorCode;

  @override
  State<DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<DeviceNameDialog> {
  late String _input = widget.name;
  bool _saving = false;
  bool _invalid = false;
  bool _failed = false;

  Future<void> _save() async {
    final value = _input.trim();
    if (!isValidDeviceName(value)) {
      setState(() {
        _invalid = true;
        _failed = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _invalid = false;
      _failed = false;
    });
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = widget.theme;

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: theme.materialColors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          l10n.deviceNameLabel,
          style: TextStyle(fontSize: 18, color: theme.textColorPrimary),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.deviceNameEditDescription,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textColorSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: l10n.deviceNameLabel,
                child: SettingTextField(
                  theme: theme,
                  value: widget.name,
                  enabled: !_saving,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  onChanged: (value) => setState(() {
                    _input = value;
                    _invalid = false;
                    _failed = false;
                  }),
                ),
              ),
              const SizedBox(height: 8),
              if (_failed)
                Text(
                  widget.errorCode?.call() == 'storage_failed'
                      ? l10n.deviceNameStorageFailed
                      : l10n.deviceNameSaveFailed,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.materialColors.error,
                  ),
                ),
              if (_invalid)
                Text(
                  l10n.deviceNameInvalid,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.materialColors.error,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          AppActionButton(
            theme: theme,
            label: l10n.settingsCancel,
            settingBackground: true,
            onPressed: _saving ? null : () => Navigator.pop(context),
            fontSize: 12,
          ),
          AppActionButton(
            theme: theme,
            label: _saving
                ? l10n.deviceBatteryCapacitySaving
                : l10n.deviceBatteryCapacitySave,
            primary: true,
            onPressed: _saving ? null : _save,
            fontSize: 12,
          ),
        ],
      ),
    );
  }
}
