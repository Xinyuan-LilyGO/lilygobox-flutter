/*
 * @Description: 逐帧校验模型菜单发送给原生端的增量语义树，捕捉悬空节点和重复父节点。
 */
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'model_selector_semantics_scenario.dart';

class _SemanticsGraphBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, List<int>>{};
  var updates = 0;

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _GraphUpdateBuilder(this);
}

class _GraphUpdateBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  _GraphUpdateBuilder(this.binding);
  final _SemanticsGraphBinding binding;
  final changes = <int, List<int>>{};
  final builder = ui.SemanticsUpdateBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final arguments = invocation.namedArguments;
      changes[arguments[#id] as int] = List<int>.from(
        arguments[#childrenInTraversalOrder] as Iterable<int>,
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    binding.nodes.addAll(changes);
    final reachable = <int>{};
    void visit(int id) {
      expect(reachable.add(id), isTrue, reason: '语义节点 $id 不应拥有重复父节点或循环引用');
      expect(
        binding.nodes.containsKey(id),
        isTrue,
        reason: '语义父节点不能引用尚未提交的子节点 $id',
      );
      for (final child in binding.nodes[id]!) {
        visit(child);
      }
    }

    if (binding.nodes.containsKey(0)) visit(0);
    for (final id in changes.keys) {
      expect(
        reachable.contains(id),
        isTrue,
        reason: '已提交节点 $id 不属于最终语义树，与原生 AXTree 错误一致',
      );
    }
    binding.nodes.removeWhere((id, _) => !reachable.contains(id));
    binding.updates++;
    return builder.build();
  }
}

void main() {
  final binding = _SemanticsGraphBinding();
  testWidgets('model menu incremental semantics remain a connected tree', (
    tester,
  ) async {
    await runModelSelectorSemanticsScenario(tester);
    expect(binding.updates, greaterThan(10));
  });
}
