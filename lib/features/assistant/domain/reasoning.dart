/*
 * @Description: 定义模型可用的思考强度与不同 API 的参数映射。
 */
enum AiReasoningEffort { none, minimal, low, medium, high, xhigh, max, ultra }

/// 以模型名称中连续出现的已知标识识别能力，不依赖服务端扩展字段。
class AiReasoningCapabilities {
  const AiReasoningCapabilities(this.levels, {this.deepSeek = false});

  final List<AiReasoningEffort> levels;
  final bool deepSeek;

  AiReasoningEffort? get initialEffort =>
      levels.length > 1 ? levels[1] : levels.firstOrNull;

  AiReasoningEffort? supportedEffort(AiReasoningEffort? effort) =>
      levels.contains(effort) ? effort : null;

  static const _standard = [
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
  ];
  static const _maxLevels = [
    ..._standard,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
  ];
  static const _extended = AiReasoningCapabilities([
    ..._maxLevels,
    AiReasoningEffort.ultra,
  ]);
  static const _upToMax = AiReasoningCapabilities(_maxLevels);
  static const _offToMax = AiReasoningCapabilities([
    AiReasoningEffort.none,
    ..._maxLevels,
  ]);
  static const _offToUltra = AiReasoningCapabilities([
    AiReasoningEffort.none,
    ..._maxLevels,
    AiReasoningEffort.ultra,
  ]);
  static const _gpt5 = AiReasoningCapabilities([
    AiReasoningEffort.minimal,
    ..._standard,
  ]);
  static const _deepSeek = AiReasoningCapabilities([
    AiReasoningEffort.none,
    AiReasoningEffort.low,
    AiReasoningEffort.high,
    AiReasoningEffort.max,
  ], deepSeek: true);
  static const _models = <String, AiReasoningCapabilities>{
    'deepseek-flash': _deepSeek,
    'deepseek-v4-pro': _deepSeek,
    'gpt-6.2-astra': _upToMax,
    'gpt-6.2-sol': _upToMax,
    'gpt-6-sol': _offToUltra,
    'gpt-6.1-sol': _extended,
    'gpt-6.1-terra': _offToMax,
    'gpt-5.6': _offToMax,
    // 当前 gpt-6-astra 接口拒绝 ultra，带前后缀时也保持最高 max。
    'gpt-6-astra': _upToMax,
    'gpt-6-luna': _offToMax,
    'gpt-5.6-luna': _offToMax,
    'gpt-5.5': AiReasoningCapabilities([..._standard, AiReasoningEffort.xhigh]),
    'o1': AiReasoningCapabilities(_standard),
    'o3': AiReasoningCapabilities(_standard),
    'o3-mini': AiReasoningCapabilities(_standard),
    'o4-mini': AiReasoningCapabilities(_standard),
    'gpt-5': _gpt5,
    'gpt-5-mini': _gpt5,
    'gpt-5-nano': _gpt5,
    'gpt-5.1': AiReasoningCapabilities([AiReasoningEffort.none, ..._standard]),
    'gpt-5.2': AiReasoningCapabilities([
      AiReasoningEffort.none,
      ..._standard,
      AiReasoningEffort.xhigh,
    ]),
    'gpt-5.4': AiReasoningCapabilities([
      AiReasoningEffort.none,
      ..._standard,
      AiReasoningEffort.xhigh,
    ]),
  };
  static final _modelIdentifiers = _models.keys.toList()
    ..sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      return byLength != 0 ? byLength : a.compareTo(b);
    });
  static final _gatewayGpt62 = RegExp(
    r'^(?:auto|group|magicai)/gpt-6\.2-(?:astra|sol)(?:[-_]|$)',
  );
  static final _gatewayGpt6 = RegExp(
    r'^(?:auto|group|magicai)/gpt-6(?:-\d{4}-\d{2}-\d{2})?$',
  );
  static final _gatewayTerra = RegExp(
    r'^(?:auto|group|magicai)/gpt-6\.1-terra(?:[-_]|$)',
  );
  static final _gpt56Variants = RegExp(r'gpt-5\.6-(?:sol|terra)(?:[-_]|$)');
  static final _gpt5Version = RegExp(r'gpt-5(?:\d|\.\d)');

  /// 已知网关档位优先，其余按不区分大小写的最长连续标识匹配。
  static AiReasoningCapabilities forModel(String model) {
    final id = model.toLowerCase();
    if (_gatewayGpt62.hasMatch(id)) return _extended;
    if (_gatewayGpt6.hasMatch(id)) return _offToMax;
    if (_gatewayTerra.hasMatch(id) || _gpt56Variants.hasMatch(id)) {
      return _offToUltra;
    }
    for (final identifier in _modelIdentifiers) {
      if (identifier == 'gpt-5' && _gpt5Version.hasMatch(id)) continue;
      if (id.contains(identifier)) return _models[identifier]!;
    }
    return const AiReasoningCapabilities([]);
  }

  Map<String, Object?> requestParameters(
    AiReasoningEffort? effort, {
    required bool responses,
  }) {
    if (effort == null || !levels.contains(effort)) return const {};
    if (responses) {
      return {
        'reasoning': {'effort': effort.name},
      };
    }
    if (deepSeek) {
      return {
        'thinking': {
          'type': effort == AiReasoningEffort.none ? 'disabled' : 'enabled',
        },
        if (effort != AiReasoningEffort.none) 'reasoning_effort': effort.name,
      };
    }
    return {'reasoning_effort': effort.name};
  }
}

/// 服务处理档位独立于思考强度；目录声明优先，缺失时采用已知模型能力。
enum AiProcessingSpeed { standard, fast, ultrafast }

List<AiProcessingSpeed> processingSpeedsForModel(
  String model, {
  bool responses = true,
  List<String>? serviceTiers,
}) {
  final id = model.toLowerCase();
  // Codex 的内置模型目录提供这些模型的 Fast 档位；显式目录声明优先。
  final fast = serviceTiers != null
      ? serviceTiers.any((tier) => tier == 'priority' || tier == 'fast')
      : [
          'gpt-6.1-sol',
          'gpt-6-astra',
          'gpt-6.1-terra',
          'gpt-6-luna',
          'gpt-5.6-sol',
        ].any(id.contains);
  // 标准 /models 列表可能只有 id；未声明档位不等于账号不支持。
  final ultra =
      responses &&
      (serviceTiers != null
          ? serviceTiers.contains('ultrafast')
          : ['gpt-6.1-sol', 'gpt-6-astra'].any(id.contains));
  if (!fast && !ultra) return const [];
  return [
    AiProcessingSpeed.standard,
    if (fast) AiProcessingSpeed.fast,
    if (ultra) AiProcessingSpeed.ultrafast,
  ];
}

Map<String, Object?> processingSpeedParameters(
  String model,
  AiProcessingSpeed speed, {
  bool responses = true,
  List<String>? serviceTiers,
}) {
  if (!processingSpeedsForModel(
    model,
    responses: responses,
    serviceTiers: serviceTiers,
  ).contains(speed)) {
    return const {};
  }
  return switch (speed) {
    AiProcessingSpeed.standard => const {'service_tier': 'default'},
    AiProcessingSpeed.fast => const {'service_tier': 'priority'},
    AiProcessingSpeed.ultrafast => const {'service_tier': 'ultrafast'},
  };
}
