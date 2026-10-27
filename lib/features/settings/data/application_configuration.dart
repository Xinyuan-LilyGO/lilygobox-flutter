import 'dart:convert';

/// 可迁移的应用界面偏好；不包含账号、设备配对信息或缓存。
class ApplicationConfiguration {
  const ApplicationConfiguration({
    required this.theme,
    required this.language,
    required this.font,
    required this.sidebarWidth,
    required this.sidebarVisible,
    required this.splitWidth,
    required this.settingsSidebarWidth,
  });

  static const formatName = 'lilygobox-config';
  static const schemaVersion = 1;

  final String theme;
  final String language;
  final String font;
  final double sidebarWidth;
  final bool sidebarVisible;
  final double splitWidth;
  final double settingsSidebarWidth;

  Map<String, Object> toJson({DateTime? exportedAt}) => {
    'format': formatName,
    'schemaVersion': schemaVersion,
    'exportedAt': (exportedAt ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String(),
    'settings': {
      'theme': theme,
      'language': language,
      'font': font,
      'sidebarWidth': sidebarWidth,
      'sidebarVisible': sidebarVisible,
      'splitWidth': splitWidth,
      'settingsSidebarWidth': settingsSidebarWidth,
    },
  };

  String encode({DateTime? exportedAt}) => const JsonEncoder.withIndent(
    '  ',
  ).convert(toJson(exportedAt: exportedAt));

  static ApplicationConfiguration decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        decoded['schemaVersion'] is! int ||
        decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'Unsupported LilygoBox configuration format.',
      );
    }

    final settings = decoded['settings'];
    if (settings is! Map<String, dynamic>) {
      throw const FormatException('Missing configuration settings.');
    }

    return ApplicationConfiguration(
      theme: _enumValue(settings, 'theme', const {'dark', 'light'}),
      language: _enumValue(settings, 'language', const {'auto', 'en', 'zh'}),
      font: _enumValue(settings, 'font', const {
        'system',
        'googleSansFlex',
        'inter',
        'roboto',
      }),
      sidebarWidth: _numberValue(settings, 'sidebarWidth', 180, 360),
      sidebarVisible: _boolValue(settings, 'sidebarVisible'),
      splitWidth: _numberValue(settings, 'splitWidth', 100, 1200),
      settingsSidebarWidth: _numberValue(
        settings,
        'settingsSidebarWidth',
        176,
        300,
      ),
    );
  }

  static String _enumValue(
    Map<String, dynamic> values,
    String key,
    Set<String> allowed,
  ) {
    final value = values[key];
    if (value is! String || !allowed.contains(value)) {
      throw FormatException('Invalid configuration value: $key.');
    }
    return value;
  }

  static double _numberValue(
    Map<String, dynamic> values,
    String key,
    double minimum,
    double maximum,
  ) {
    final value = values[key];
    if (value is! num ||
        !value.isFinite ||
        value < minimum ||
        value > maximum) {
      throw FormatException('Invalid configuration value: $key.');
    }
    return value.toDouble();
  }

  static bool _boolValue(Map<String, dynamic> values, String key) {
    final value = values[key];
    if (value is! bool) {
      throw FormatException('Invalid configuration value: $key.');
    }
    return value;
  }
}
