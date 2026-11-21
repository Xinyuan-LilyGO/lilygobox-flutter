import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';

void main() {
  test('models default to the second slider position including off', () {
    for (final model in [
      'gpt-6.1-sol',
      'gpt-6.2-astra',
      'gpt-6.2-sol',
      'gpt-6-astra',
      'gpt-5.5',
      'o1',
      'o3',
      'o3-mini',
      'o4-mini',
    ]) {
      expect(
        AiReasoningCapabilities.forModel(model).initialEffort,
        AiReasoningEffort.medium,
        reason: model,
      );
    }
    for (final model in ['deepseek-flash', 'deepseek-v4-pro']) {
      final capabilities = AiReasoningCapabilities.forModel(model);
      expect(capabilities.initialEffort, AiReasoningEffort.low, reason: model);
      expect(capabilities.levels, [
        AiReasoningEffort.none,
        AiReasoningEffort.low,
        AiReasoningEffort.high,
        AiReasoningEffort.max,
      ]);
    }
    for (final model in [
      'gpt-5',
      'gpt-5-mini',
      'gpt-5-nano',
      'gpt-5.1',
      'gpt-5.2',
      'gpt-5.4',
      'gpt-5.6',
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-6-sol',
      'gpt-6-luna',
      'gpt-6.1-terra',
      'magicai/gpt-6',
    ]) {
      expect(
        AiReasoningCapabilities.forModel(model).initialEffort,
        AiReasoningEffort.low,
        reason: model,
      );
    }
  });

  test('default handles empty and single slider position capabilities', () {
    expect(const AiReasoningCapabilities([]).initialEffort, isNull);
    expect(
      const AiReasoningCapabilities([AiReasoningEffort.none]).initialEffort,
      AiReasoningEffort.none,
    );
    expect(
      const AiReasoningCapabilities([
        AiReasoningEffort.none,
        AiReasoningEffort.high,
      ]).initialEffort,
      AiReasoningEffort.high,
    );
    expect(
      const AiReasoningCapabilities([AiReasoningEffort.low]).initialEffort,
      AiReasoningEffort.low,
    );
  });

  for (final model in [
    'deepseek-flash',
    'deepseek-v4-pro',
    'gpt-6-sol',
    'gpt-6.1-sol',
    'gpt-6.1-terra',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'gpt-6-astra',
    'gpt-6-luna',
    'gpt-5.6-luna',
    'gpt-5.5',
    'o1',
    'o3',
    'o3-mini',
    'o4-mini',
    'gpt-5',
    'gpt-5-mini',
    'gpt-5-nano',
    'gpt-5.1',
    'gpt-5.2',
    'gpt-5.4',
  ]) {
    test('continuous identifier retains capabilities and encoding: $model', () {
      final original = AiReasoningCapabilities.forModel(model);
      for (final alias in [
        'ai-apizn/$model',
        'custom-$model-test',
        'CUSTOM-${model.toUpperCase()}-TEST',
        '$model-2026-11-13',
      ]) {
        final actual = AiReasoningCapabilities.forModel(alias);
        expect(actual.levels, original.levels, reason: alias);
        expect(actual.deepSeek, original.deepSeek, reason: alias);
        for (final effort in AiReasoningEffort.values) {
          for (final responses in [false, true]) {
            expect(
              actual.requestParameters(effort, responses: responses),
              original.requestParameters(effort, responses: responses),
              reason: alias,
            );
          }
        }
      }
    });
  }

  test('GPT-6.2 has no off level and only known routes offer ultra', () {
    const standard = [
      AiReasoningEffort.low,
      AiReasoningEffort.medium,
      AiReasoningEffort.high,
      AiReasoningEffort.xhigh,
      AiReasoningEffort.max,
    ];
    for (final model in ['gpt-6.2-astra', 'gpt-6.2-sol']) {
      for (final id in [model, '$model-2026-11-19', 'custom-$model-test']) {
        final capabilities = AiReasoningCapabilities.forModel(id);
        expect(capabilities.levels, standard, reason: id);
        expect(capabilities.initialEffort, AiReasoningEffort.medium);
        expect(
          capabilities.requestParameters(
            AiReasoningEffort.none,
            responses: true,
          ),
          isEmpty,
        );
      }
      for (final route in ['auto', 'group', 'magicai']) {
        final id = '$route/${model.toUpperCase()}';
        expect(AiReasoningCapabilities.forModel(id).levels, [
          ...standard,
          AiReasoningEffort.ultra,
        ], reason: id);
      }
    }
  });
  test('longest continuous identifier wins over the generic GPT-5 rule', () {
    expect(
      AiReasoningCapabilities.forModel('custom-gpt-5.6-sol-test').levels.last,
      AiReasoningEffort.ultra,
    );
    expect(
      AiReasoningCapabilities.forModel('custom-gpt-5.6-luna-test').levels.last,
      AiReasoningEffort.max,
    );
    expect(
      AiReasoningCapabilities.forModel('auto/gpt-5.2').levels.first,
      AiReasoningEffort.none,
    );
    expect(
      AiReasoningCapabilities.forModel('custom-gpt-6-astra-test').levels.last,
      AiReasoningEffort.max,
    );
    expect(
      AiReasoningCapabilities.forModel('o1-pro').levels,
      AiReasoningCapabilities.forModel('o1').levels,
    );
  });
  test('only a complete continuous known identifier enables reasoning', () {
    for (final name in [
      'custom-gpt-6.1-xxx-sol-test',
      'auto/best',
      'unknown',
      'deepseek-chat',
      'deepseek-reasoner',
      'gpt-4o',
      'gpt-6.1-so',
      'gpt-6.2',
      'gpt-5.9',
    ]) {
      expect(
        AiReasoningCapabilities.forModel(name).levels,
        isEmpty,
        reason: name,
      );
    }
  });
}
