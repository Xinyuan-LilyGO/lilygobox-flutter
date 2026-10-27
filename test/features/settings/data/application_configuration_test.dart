import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/settings/data/application_configuration.dart';

void main() {
  const configuration = ApplicationConfiguration(
    theme: 'dark',
    language: 'auto',
    font: 'system',
    sidebarWidth: 180,
    sidebarVisible: false,
    splitWidth: 300,
    settingsSidebarWidth: 176,
  );

  group('ApplicationConfiguration', () {
    test('round trips supported preferences through JSON', () {
      final decoded = ApplicationConfiguration.decode(
        configuration.encode(exportedAt: DateTime.utc(2026, 1, 1)),
      );

      expect(decoded.theme, 'dark');
      expect(decoded.language, 'auto');
      expect(decoded.font, 'system');
      expect(decoded.sidebarWidth, 180);
      expect(decoded.sidebarVisible, isFalse);
      expect(decoded.splitWidth, 300);
      expect(decoded.settingsSidebarWidth, 176);
    });

    test('does not export account, device, or cache data', () {
      final exported =
          jsonDecode(configuration.encode()) as Map<String, dynamic>;
      final serialized = jsonEncode(exported);

      expect(serialized, isNot(contains('token')));
      expect(serialized, isNot(contains('devices')));
      expect(serialized, isNot(contains('firmware')));
    });

    test('rejects unsupported format versions', () {
      final invalid = configuration.toJson()..['schemaVersion'] = 2;

      expect(
        () => ApplicationConfiguration.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    });

    test('rejects out-of-range layout values before import', () {
      final invalid = configuration.toJson();
      (invalid['settings'] as Map<String, Object>)['sidebarWidth'] = 40;

      expect(
        () => ApplicationConfiguration.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    });
  });
}
