/*
 * @Description: 编辑设备电池额定容量，校验范围并等待设备保存确认。
 * @Author: LILYGO_L
 * @Date: 2026-10-13 00:00:00
 * @LastEditTime: 2026-10-13 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/language_provider.dart';
import '../../../../core/theme/definition.dart';
import '../../../../core/theme/material_palette.dart';
import '../../../../core/widgets/action_button.dart';
import '../../../../core/widgets/settings/fields.dart';

class BatteryCapacityDialog extends StatefulWidget {
  const BatteryCapacityDialog({
    super.key,
    required this.theme,
    required this.capacity,
    required this.minimum,
    required this.maximum,
    required this.onSave,
  });

  final AppTheme theme;
  final int capacity;
  final int minimum;
  final int maximum;
  final Future<bool> Function(int) onSave;

  @override
  State<BatteryCapacityDialog> createState() => _BatteryCapacityDialogState();
}

class _BatteryCapacityDialogState extends State<BatteryCapacityDialog> {
  late String _input = '${widget.capacity}';
  bool _saving = false;
  bool _invalid = false;
  bool _failed = false;

  Future<void> _save() async {
    final value = int.tryParse(_input);
    if (value == null || value < widget.minimum || value > widget.maximum) {
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
    final range = l10n.deviceBatteryCapacityRange(
      widget.minimum,
      widget.maximum,
    );
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: theme.materialColors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          l10n.deviceBatteryCapacity,
          style: TextStyle(fontSize: 18, color: theme.textColorPrimary),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.deviceBatteryCapacityDescription,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textColorSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: l10n.deviceBatteryCapacity,
                child: SettingTextField(
                  theme: theme,
                  value: '${widget.capacity}',
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) => setState(() {
                    _input = value;
                    _invalid = false;
                    _failed = false;
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _failed ? l10n.deviceBatteryCapacitySaveFailed : range,
                semanticsLabel: _invalid
                    ? '${l10n.deviceBatteryCapacityInvalid} $range'
                    : null,
                style: TextStyle(
                  fontSize: 12,
                  color: _invalid || _failed
                      ? theme.materialColors.error
                      : theme.textColorSecondary,
                ),
              ),
              if (_invalid)
                Text(
                  l10n.deviceBatteryCapacityInvalid,
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
