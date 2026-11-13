import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';

void main() {
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
        'auto/$model',
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
    ]) {
      expect(
        AiReasoningCapabilities.forModel(name).levels,
        isEmpty,
        reason: name,
      );
    }
  });
}
