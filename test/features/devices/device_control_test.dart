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
import 'package:lilygobox/features/devices/presentation/widgets/device_battery_estimate.dart';
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
  test('device names validate UTF-8 byte limits and legacy support', () {
    expect(isValidDeviceName('设备' * 10), isTrue);
    expect(isValidDeviceName('设备' * 11), isFalse);
    expect(isValidDeviceName('a' * 64), isTrue);
    expect(isValidDeviceName('a' * 65), isFalse);
    expect(isValidDeviceName('  '), isFalse);
    expect(isValidDeviceName('a\nb'), isFalse);
    final legacy = DeviceControlState.parse(snapshot());
    expect(legacy.supports(DeviceControlField.deviceName), isFalse);
    final source = snapshot();
    final caps = Map<String, dynamic>.from(source['capabilities'] as Map);
    final state = DeviceControlState.parse({
      ...source,
      'capabilities': {...caps, 'identity': true},
      'deviceName': 'My device',
    });
    expect(state.supports(DeviceControlField.deviceName), isTrue);
    expect(state.accepts(DeviceControlField.deviceName, '新设备'), isTrue);
    expect(state.accepts(DeviceControlField.deviceName, 12), isFalse);
  });

  test(
    'negative current hides estimates without overriding the device state',
    () {
      final battery = snapshot()['battery'] as Map<String, Object>;
      final state = DeviceControlState.parse({
        ...snapshot(),
        'battery': {
          ...battery,
          'charging': true,
          'currentMa': -127,
          'timeToFullMinutes': 22,
          'timeToEmptyMinutes': 408,
        },
      });
      expect(state.battery!.charging, isTrue);
      expect(state.battery!.timeToFullMinutes, isNull);
      expect(state.battery!.timeToEmptyMinutes, isNull);
    },
  );
  test('low current preserves reported state and hides time estimates', () {
    final battery = snapshot()['battery'] as Map<String, Object>;
    for (final charging in [true, false]) {
      for (final current in [-30, -22, 0, 22, 30]) {
        final state = DeviceControlState.parse({
          ...snapshot(),
          'battery': {
            ...battery,
            'charging': charging,
            'currentMa': current,
            'timeToFullMinutes': 22,
            'timeToEmptyMinutes': 408,
          },
        });
        expect(state.battery!.charging, charging);
        expect(state.battery!.timeToFullMinutes, isNull);
        expect(state.battery!.timeToEmptyMinutes, isNull);
      }
    }
  });
  testWidgets('battery headline combines percent with the active estimate', (
    tester,
  ) async {
    Widget app(bool charging) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 220,
          child: DeviceBatteryEstimate(
            color: Colors.black,
            battery: DeviceBatteryState(
              percent: 75,
              charging: charging,
              full: false,
              voltageMv: 3900,
              currentMa: charging ? 100 : -100,
              temperatureC: 25,
              timeToFullMinutes: 22,
              timeToEmptyMinutes: 408,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(find.text('75% · 22 min'), findsOneWidget);
    await tester.pumpWidget(app(false));
    expect(find.text('75% · 6 hr 48 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'battery telemetry is optional and unknown values are not fabricated',
    () {
      final old = DeviceControlState.parse(snapshot());
      expect(old.battery!.healthPercent, isNull);
      expect(old.battery!.timeToFullMinutes, isNull);
      expect(old.supports(DeviceControlField.batteryCapacityMah), isFalse);
      final battery = snapshot()['battery'] as Map<String, Object>;
      final state = DeviceControlState.parse({
        ...snapshot(),
        'battery': {
          ...battery,
          'healthPercent': 92,
          'timeToFullMinutes': 75,
          'timeToEmptyMinutes': null,
          'temperatureC': null,
        },
      });
      expect(state.battery!.healthPercent, 92);
      expect(state.battery!.timeToFullMinutes, 75);
      expect(state.battery!.timeToEmptyMinutes, isNull);
      expect(state.battery!.temperatureC, isNull);
      for (final value in [0, 101, '92']) {
        expect(
          () => DeviceControlState.parse({
            ...snapshot(),
            'battery': {...battery, 'healthPercent': value},
          }),
          throwsFormatException,
        );
      }
      for (final value in [0, 65535, -1]) {
        expect(
          () => DeviceControlState.parse({
            ...snapshot(),
            'battery': {...battery, 'timeToFullMinutes': value},
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('capacity follows device range and remains editable without a pack', () {
    final state = DeviceControlState.parse({
      ...snapshot(),
      'capabilities': {
        'screen': true,
        'audio': false,
        'haptic': false,
        'battery': true,
      },
      'batteryCapacityMah': 1000,
      'batteryCapacityMinimumMah': 1,
      'batteryCapacityMaximumMah': 32767,
      'battery': {'available': false},
    });
    expect(state.supports(DeviceControlField.batteryCapacityMah), isTrue);
    expect(state.accepts(DeviceControlField.batteryCapacityMah, 32767), isTrue);
    for (final value in [0, 32768, 1.5, true]) {
      expect(
        state.accepts(DeviceControlField.batteryCapacityMah, value),
        isFalse,
      );
    }
    expect(state.battery, isNull);
  });

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
          () => DeviceControlState.parse({
            ...snapshot(),
            field.wireName: field == DeviceControlField.deviceName ? '' : 'bad',
          }),
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
      expect(find.text('48% · —'), findsOneWidget);
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
      expect(find.text('48% · —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
