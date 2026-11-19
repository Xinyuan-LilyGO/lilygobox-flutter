/*
 * @Description: 验证悬停提示在页面隐藏后的清理及再次进入时的正常显示。
 */
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_tooltip.dart';
import 'package:lilygobox/core/widgets/retained_page_stack.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shared route scope preserves idle tooltip widget identities', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTooltipScope(
            child: Wrap(
              children: [
                for (var index = 0; index < 40; index++)
                  AppTooltip(
                    message: 'Scoped hint $index',
                    child: TextButton(
                      onPressed: () {},
                      child: Text('Scoped target $index'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tooltips = find.byType(Tooltip, skipOffstage: false);
    final before = tester.widgetList<Tooltip>(tooltips).toList();
    final beforeStates = tester.stateList<TooltipState>(tooltips).toList();
    final scopeContext = tester.element(find.byType(AppTooltipScope));
    void expectTooltipsReused() {
      final actual = tester.widgetList<Tooltip>(tooltips).toList();
      expect(actual, hasLength(before.length));
      for (var index = 0; index < before.length; index++) {
        expect(actual[index], same(before[index]));
      }
      expect(
        tester.stateList<TooltipState>(tooltips),
        orderedEquals(beforeStates),
      );
    }

    for (var round = 0; round < 3; round++) {
      unawaited(
        showDialog<void>(
          context: scopeContext,
          builder: (context) => const Dialog(child: Text('Scoped modal')),
        ),
      );
      await tester.pumpAndSettle();
      expectTooltipsReused();
      Navigator.of(scopeContext).pop();
      await tester.pumpAndSettle();
      expectTooltipsReused();
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final useScope in [false, true]) {
    for (final visibleBeforeModal in [false, true]) {
      testWidgets(
        '${useScope ? 'shared route scope' : 'route fallback'} clears ${visibleBeforeModal ? 'visible' : 'waiting'} hover and restores the fresh delay',
        (tester) async {
          final hoverTarget = Align(
            alignment: Alignment.topLeft,
            child: AppTooltip(
              message: 'Scoped hover hint',
              child: TextButton(
                key: const ValueKey('scoped-hover-target'),
                onPressed: () {},
                child: const Text('Scoped hover target'),
              ),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: useScope
                    ? AppTooltipScope(child: hoverTarget)
                    : hoverTarget,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final tooltip = find.byType(Tooltip, skipOffstage: false);
          final target = find.byKey(const ValueKey('scoped-hover-target'));
          final tooltipState = tester.state<TooltipState>(tooltip);
          final buttonState = tester.state(target);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: const Offset(700, 500));
          await mouse.moveTo(tester.getCenter(target));
          await tester.pump(
            visibleBeforeModal
                ? AppTooltip.waitDuration
                : const Duration(milliseconds: 200),
          );
          if (visibleBeforeModal) {
            await tester.pumpAndSettle();
            expect(find.text('Scoped hover hint'), findsOneWidget);
          }
          final scopeContext = tester.element(find.byType(AppTooltip));
          unawaited(
            showDialog<void>(
              context: scopeContext,
              builder: (context) => const Dialog(child: Text('Scoped modal')),
            ),
          );
          await tester.pump();
          expect(
            find.text('Scoped hover hint', skipOffstage: false),
            findsNothing,
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(
            find.text('Scoped hover hint', skipOffstage: false),
            findsNothing,
          );
          expect(tester.state<TooltipState>(tooltip), same(tooltipState));
          expect(tester.state(target), same(buttonState));
          await mouse.moveTo(const Offset(700, 500));
          Navigator.of(scopeContext).pop();
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(target));
          await tester.pump(const Duration(milliseconds: 499));
          expect(find.text('Scoped hover hint'), findsNothing);
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pumpAndSettle();
          expect(find.text('Scoped hover hint'), findsOneWidget);
          expect(tester.state<TooltipState>(tooltip), same(tooltipState));
          expect(tester.state(target), same(buttonState));
          await mouse.moveTo(const Offset(700, 500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('tooltip rebinds replaced scopes and the route fallback', (
    tester,
  ) async {
    final scope = ValueNotifier(0);
    addTearDown(scope.dispose);
    final target = AppTooltip(
      key: GlobalKey(),
      message: 'Rebound hint',
      child: TextButton(
        key: const ValueKey('rebound-target'),
        onPressed: () {},
        child: const Text('Rebound target'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<int>(
              valueListenable: scope,
              builder: (context, selected, _) => selected == 2
                  ? target
                  : AppTooltipScope(key: ValueKey(selected), child: target),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tooltip = find.byType(Tooltip, skipOffstage: false);
    final button = find.byKey(const ValueKey('rebound-target'));
    final tooltipState = tester.state<TooltipState>(tooltip);
    final buttonState = tester.state(button);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(700, 500));

    for (final selected in [1, 2, 0]) {
      scope.value = selected;
      await tester.pumpAndSettle();
      expect(tester.state<TooltipState>(tooltip), same(tooltipState));
      expect(tester.state(button), same(buttonState));
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump(AppTooltip.waitDuration);
      await tester.pumpAndSettle();
      expect(find.text('Rebound hint'), findsOneWidget);

      final routeContext = tester.element(find.byType(AppTooltip));
      unawaited(
        showDialog<void>(
          context: routeContext,
          builder: (context) => const Dialog(child: Text('Rebound modal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rebound hint', skipOffstage: false), findsNothing);
      await mouse.moveTo(const Offset(700, 500));
      Navigator.of(routeContext).pop();
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested menu tooltip keeps independent semantics anchors', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MenuAnchor(
              menuChildren: [
                MenuItemButton(onPressed: () {}, child: const Text('Share')),
              ],
              builder: (context, controller, child) => AppTooltip(
                message: 'Collaborate hint',
                child: TextButton(
                  onPressed: controller.open,
                  child: const Text('Collaborate'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menuNode = tester.getSemantics(find.byType(AppTooltip));
    final tooltipNode = tester.getSemantics(find.byType(Tooltip));
    expect(tooltipNode.id, isNot(menuNode.id));
    expect(tooltipNode.getSemanticsData().tooltip, 'Collaborate hint');
    expect(tooltipNode.traversalParentIdentifier, isNotNull);
    expect(menuNode.traversalParentIdentifier, isNotNull);
    expect(
      tooltipNode.traversalParentIdentifier,
      isNot(menuNode.traversalParentIdentifier),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Collaborate')));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Collaborate hint'), findsOneWidget);
    expect(tester.getSemantics(find.byType(Tooltip)).id, tooltipNode.id);
    expect(
      tester.getSemantics(find.byType(Tooltip)).getSemanticsData().tooltip,
      'Collaborate hint',
    );
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('Collaborate hint'), findsNothing);
    expect(tester.getSemantics(find.byType(Tooltip)).id, tooltipNode.id);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  for (final size in [18.0, 30.0, 48.0]) {
    testWidgets('tooltip keeps an 8px edge gap for a ${size}px control', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppTooltip(
                message: 'Hint',
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: size,
                  height: size,
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('target'))),
      );
      await tester.pump(AppTooltip.waitDuration);
      await tester.pumpAndSettle();
      final bubble = find
          .ancestor(of: find.text('Hint'), matching: find.byType(Container))
          .first;
      final bottom = tester
          .getBottomLeft(find.byKey(const ValueKey('target')))
          .dy;
      expect(tester.getTopLeft(bubble).dy - bottom, closeTo(8, .01));
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    });
  }
  testWidgets('hidden retained page removes tooltip and can show it again', (
    tester,
  ) async {
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: page,
            builder: (context, active, _) => RetainedPageStack(
              activeKey: active,
              pages: {
                0: Center(
                  child: AppTooltip(
                    message: 'Back hint',
                    verticalOffset: 16,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: GestureDetector(
                        key: const ValueKey('back-button'),
                        onTap: () => page.value = 1,
                        child: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ),
                1: const Center(child: Text('Home')),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final button = find.byKey(const ValueKey('back-button'));
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsOneWidget);
    page.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Back hint', skipOffstage: false), findsNothing);
    await mouse.moveTo(Offset.zero);
    page.value = 0;
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    await mouse.down(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Back hint', skipOffstage: false), findsNothing);

    await mouse.moveTo(Offset.zero);
    page.value = 0;
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Back hint')).dy -
          tester.getBottomLeft(button).dy,
      greaterThanOrEqualTo(8),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsNothing);

    // 隐藏发生在等待显示期间，也不能稍后向新页面弹出提示。
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    page.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Back hint'), findsNothing);
  });

  testWidgets('idle tooltips retain states across page and viewport changes', (
    tester,
  ) async {
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    const targetCount = 40;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTooltipScope(
            child: ValueListenableBuilder<int>(
              valueListenable: page,
              builder: (context, active, _) => RetainedPageStack(
                animateTransitions: false,
                activeKey: active,
                pages: {
                  0: Wrap(
                    children: [
                      for (var index = 0; index < targetCount; index++)
                        AppTooltip(
                          message: 'Hint $index',
                          child: TextButton(
                            key: ValueKey('target-$index'),
                            onPressed: () {},
                            child: Text('Target $index'),
                          ),
                        ),
                    ],
                  ),
                  1: const Center(child: Text('Other page')),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tooltips = find.byType(Tooltip, skipOffstage: false);
    final rawTooltips = find.byType(RawTooltip, skipOffstage: false);
    final tooltipStates = tester.stateList<TooltipState>(tooltips).toList();
    final rawStates = tester.stateList<RawTooltipState>(rawTooltips).toList();
    final buttonStates = [
      for (var index = 0; index < targetCount; index++)
        tester.state(
          find.byKey(ValueKey('target-$index'), skipOffstage: false),
        ),
    ];
    expect(tooltipStates, hasLength(targetCount));
    expect(rawStates, hasLength(targetCount));

    void expectStatesRetained() {
      expect(
        tester.stateList<TooltipState>(tooltips),
        orderedEquals(tooltipStates),
      );
      expect(
        tester.stateList<RawTooltipState>(rawTooltips),
        orderedEquals(rawStates),
      );
      for (var index = 0; index < targetCount; index++) {
        expect(
          tester.state(
            find.byKey(ValueKey('target-$index'), skipOffstage: false),
          ),
          same(buttonStates[index]),
        );
      }
    }

    page.value = 1;
    await tester.pumpAndSettle();
    expectStatesRetained();
    page.value = 0;
    await tester.pumpAndSettle();
    expectStatesRetained();
    tester.view.physicalSize = const Size(1100, 850);
    await tester.pumpAndSettle();
    expectStatesRetained();
    expect(tester.takeException(), isNull);
  });

  testWidgets('active tooltip resets preserve tooltip and button states', (
    tester,
  ) async {
    final page = ValueNotifier(0);
    final textScale = ValueNotifier(1.0);
    addTearDown(page.dispose);
    addTearDown(textScale.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: textScale,
          builder: (context, scale, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: AppTooltipScope(
            child: ValueListenableBuilder<int>(
              valueListenable: page,
              builder: (context, active, _) => RetainedPageStack(
                animateTransitions: false,
                activeKey: active,
                pages: {
                  0: Align(
                    alignment: Alignment.topLeft,
                    child: AppTooltip(
                      message: 'Retained hint',
                      child: TextButton(
                        key: const ValueKey('retained-target'),
                        onPressed: () {},
                        child: const Text('Retained target'),
                      ),
                    ),
                  ),
                  1: const Center(child: Text('Other page')),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tooltip = find.byType(Tooltip, skipOffstage: false);
    final button = find.byKey(
      const ValueKey('retained-target'),
      skipOffstage: false,
    );
    final tooltipState = tester.state<TooltipState>(tooltip);
    final buttonState = tester.state(button);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(AppTooltip.waitDuration);
    await tester.pumpAndSettle();
    expect(find.text('Retained hint'), findsOneWidget);

    void expectStatesRetained() {
      expect(tester.state<TooltipState>(tooltip), same(tooltipState));
      expect(tester.state(button), same(buttonState));
    }

    Future<void> expectFreshDelay() async {
      await tester.pump();
      await tester.pump();
      expect(find.text('Retained hint'), findsNothing);
      await tester.pump(const Duration(milliseconds: 499));
      expect(find.text('Retained hint'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Retained hint'), findsOneWidget);
      expectStatesRetained();
    }

    page.value = 1;
    await tester.pump();
    expect(find.text('Retained hint', skipOffstage: false), findsNothing);
    expectStatesRetained();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Retained hint', skipOffstage: false), findsNothing);
    page.value = 0;
    await expectFreshDelay();

    tester.view.physicalSize = const Size(1100, 850);
    await expectFreshDelay();
    textScale.value = 1.25;
    await expectFreshDelay();

    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    page.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Retained hint', skipOffstage: false), findsNothing);
    expectStatesRetained();
    page.value = 0;
    await expectFreshDelay();
    expect(tester.takeException(), isNull);
  });
}
