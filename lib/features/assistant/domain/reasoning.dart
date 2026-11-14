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
      levels.contains(AiReasoningEffort.medium)
      ? AiReasoningEffort.medium
      : levels.contains(AiReasoningEffort.high)
      ? AiReasoningEffort.high
      : levels.firstOrNull;

  static const _standard = [
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
  ];
  static const _extended = AiReasoningCapabilities([
    ..._standard,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
    AiReasoningEffort.ultra,
  ]);
  static const _upToMax = AiReasoningCapabilities([
    ..._standard,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
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
    'gpt-6-sol': _extended,
    'gpt-6.1-sol': _extended,
    'gpt-6.1-terra': _extended,
    'gpt-5.6-sol': _extended,
    'gpt-5.6-terra': _extended,
    // 当前 gpt-6-astra 接口拒绝 ultra，带前后缀时也保持最高 max。
    'gpt-6-astra': _upToMax,
    'gpt-6-luna': _upToMax,
    'gpt-5.6-luna': _upToMax,
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

  /// 连续子字符串匹配；前缀、后缀和大小写不改变能力，长标识优先。
  static AiReasoningCapabilities forModel(String model) {
    final id = model.toLowerCase();
    for (final identifier in _modelIdentifiers) {
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
