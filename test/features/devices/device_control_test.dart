/*
 * @Description: 验证控制状态解析与设备能力对真实数据和滑条交互的约束。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/features/devices/domain/device_control.dart';
import 'package:lilygobox/features/devices/presentation/widgets/device_dashboard.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';

Map<String, Object> snapshot() => {
  'ready': true,
  'capabilities': {'screen': true, 'audio': false, 'haptic': false},
  'screenEnabled': false,
  'soundEnabled': true,
  'hapticEnabled': false,
  'brightness': 75,
  'rotation': 90,
  'lockTimeoutSeconds': 300,
  'volume': 65,
  'hapticStrength': 60,
  'battery': {
    'available': true,
    'charging': true,
    'full': false,
    'percent': 48,
    'voltageMv': 3900,
    'currentMa': 250,
    'temperatureC': 28.5,
  },
};

void main() {
  test(
    'auto lock accepts device options and stays unavailable on old firmware',
    () {
      for (final seconds in deviceLockTimeoutOptions) {
        final state = DeviceControlState.parse({
          ...snapshot(),
          'lockTimeoutSeconds': seconds,
        });
        expect(state.number(DeviceControlField.lockTimeoutSeconds), seconds);
        expect(state.supports(DeviceControlField.lockTimeoutSeconds), isTrue);
      }
      for (final seconds in [-1, 10, 90, 601, true]) {
        expect(
          () => DeviceControlState.parse({
            ...snapshot(),
            'lockTimeoutSeconds': seconds,
          }),
          throwsFormatException,
        );
      }
      final old = snapshot()..remove('lockTimeoutSeconds');
      expect(
        DeviceControlState.parse(
          old,
        ).supports(DeviceControlField.lockTimeoutSeconds),
        isFalse,
      );
    },
  );
  test(
    'malformed values fail parsing and unavailable battery is not invented',
    () {
      for (final field in DeviceControlField.values) {
        expect(
          () =>
              DeviceControlState.parse({...snapshot(), field.wireName: 'bad'}),
          throwsFormatException,
        );
      }
      expect(
        () => DeviceControlState.parse({...snapshot(), 'brightness': 0}),
        throwsFormatException,
      );
      expect(
        () => DeviceControlState.parse({...snapshot(), 'rotation': 45}),
        throwsFormatException,
      );
      final state = DeviceControlState.parse({
        ...snapshot(),
        'battery': {'available': false},
      });
      expect(state.battery, isNull);
      expect(state.supports(DeviceControlField.volume), isFalse);
      expect(state.supports(DeviceControlField.brightness), isTrue);
    },
  );

  testWidgets(
    'dashboard uses actual battery and allows brightness while screen is off',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final state = DeviceControlState.parse(snapshot());
      int? selectedTimeout;
      Widget app({bool online = true}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceDashboard(
              theme: theme.themeData,
              name: 'Desk P4',
              status: 'Online',
              online: online,
              connecting: false,
              description: '',
              controlState: state,
              controlsReady: true,
              brightness: .75,
              volume: .65,
              vibration: .60,
              screenOn: false,
              soundOn: true,
              vibrationOn: false,
              rotation: 90,
              onBrightness: (_) {},
              onVolume: (_) {},
              onVibration: (_) {},
              onScreen: (_) {},
              onSound: (_) {},
              onVibrationEnabled: (_) {},
              onRotation: (_) {},
              onLockTimeout: (seconds) => selectedTimeout = seconds,
              onInformation: () {},
              onBattery: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      expect(find.text('48%'), findsOneWidget);
      expect(find.text('82%'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('device-auto-lock-0')));
      await tester.pumpAndSettle();
      expect(selectedTimeout, 0);
      // 宽卡片一行、窄卡片两行，全部选项可见且不依赖横向滚动。
      await tester.binding.setSurfaceSize(const Size(850, 900));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('device-auto-lock-15'));
      final last = find.byKey(const ValueKey('device-auto-lock-0'));
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
      await tester.binding.setSurfaceSize(const Size(360, 900));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(last).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      for (final seconds in deviceLockTimeoutOptions) {
        final rect = tester.getRect(
          find.byKey(ValueKey('device-auto-lock-$seconds')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
      }
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.where((slider) => slider.onChanged != null), hasLength(1));
      expect(
        sliders.singleWhere((slider) => slider.onChanged != null).value,
        .75,
      );
      await tester.pumpWidget(app(online: false));
      selectedTimeout = null;
      await tester.tap(
        find.byKey(const ValueKey('device-auto-lock-15')),
        warnIfMissed: false,
      );
      expect(selectedTimeout, isNull);
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .every((slider) => slider.onChanged == null),
        isTrue,
      );
      expect(find.text('48%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
