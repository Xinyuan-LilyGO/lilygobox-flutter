/*
 * @Description: 定义模型可用的思考强度与不同 API 的参数映射。
 * @Author: LILYGO_L
 * @Date: 2026-11-10 11:58:09
 * @LastEditTime: 2026-11-10 13:53:32
 */
enum AiReasoningEffort { none, minimal, low, medium, high, xhigh, max, ultra }

/// 仅明确支持的模型显示强度面板；未知别名不推测其能力。
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

  static AiReasoningCapabilities forModel(String model) {
    final id = model.toLowerCase();
    const standard = [
      AiReasoningEffort.low,
      AiReasoningEffort.medium,
      AiReasoningEffort.high,
    ];
    if (['deepseek-flash', 'deepseek-v4-pro'].contains(id)) {
      return const AiReasoningCapabilities([
        AiReasoningEffort.none,
        AiReasoningEffort.low,
        AiReasoningEffort.high,
        AiReasoningEffort.max,
      ], deepSeek: true);
    }
    // Codex models-manager catalog: these families advertise the same levels.
    if (RegExp(
      r'^gpt-(6-astra|6-sol|6\.1-sol|6\.1-terra|5\.6-sol|5\.6-terra)$',
    ).hasMatch(id)) {
      return const AiReasoningCapabilities([
        ...standard,
        AiReasoningEffort.xhigh,
        AiReasoningEffort.max,
        AiReasoningEffort.ultra,
      ]);
    }
    if (['gpt-6-luna', 'gpt-5.6-luna'].contains(id)) {
      return const AiReasoningCapabilities([
        ...standard,
        AiReasoningEffort.xhigh,
        AiReasoningEffort.max,
      ]);
    }
    if (RegExp(r'^gpt-5\.5(?:-\d{4}-\d{2}-\d{2})?$').hasMatch(id)) {
      return const AiReasoningCapabilities([
        ...standard,
        AiReasoningEffort.xhigh,
      ]);
    }
    if (RegExp(
      r'^(o1|o3|o3-mini|o4-mini)(?:-\d{4}-\d{2}-\d{2})?$',
    ).hasMatch(id)) {
      return const AiReasoningCapabilities(standard);
    }
    if (RegExp(
      r'^gpt-5(?:-mini|-nano)?(?:-\d{4}-\d{2}-\d{2})?$',
    ).hasMatch(id)) {
      return const AiReasoningCapabilities([
        AiReasoningEffort.minimal,
        ...standard,
      ]);
    }
    if (RegExp(r'^gpt-5\.1(?:-\d{4}-\d{2}-\d{2})?$').hasMatch(id)) {
      return const AiReasoningCapabilities([
        AiReasoningEffort.none,
        ...standard,
      ]);
    }
    if (RegExp(r'^gpt-5\.(2|4)(?:-\d{4}-\d{2}-\d{2})?$').hasMatch(id)) {
      return const AiReasoningCapabilities([
        AiReasoningEffort.none,
        ...standard,
        AiReasoningEffort.xhigh,
      ]);
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
