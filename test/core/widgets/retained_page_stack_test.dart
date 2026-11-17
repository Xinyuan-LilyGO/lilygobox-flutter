/*
 * @Description: 验证保留页面仅布局可见页，并保持状态、滚动、焦点和无障碍隔离。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/retained_page_stack.dart';
import 'package:material_ui/material_ui.dart';

class _LayoutLog {
  var layouts = 0;
  Size? size;
}

class _LayoutProbe extends LeafRenderObjectWidget {
  const _LayoutProbe(this.log);

  final _LayoutLog log;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutProbe(log);
}

class _RenderLayoutProbe extends RenderBox {
  _RenderLayoutProbe(this.log);

  final _LayoutLog log;

  @override
  void performLayout() {
    log.layouts++;
    size = constraints.biggest;
    log.size = size;
  }
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({super.key});

  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage> {
  final scroll = ScrollController();
  final draft = TextEditingController();
  final focus = FocusNode();
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    scroll.dispose();
    draft.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: scroll,
    child: Column(
      children: [
        TextField(controller: draft, focusNode: focus),
        const SizedBox(height: 1800),
      ],
    ),
  );
}

Widget _app(Widget child) => MaterialApp(
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: navigator!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'resize lays out only the active page and activation synchronizes size',
    (tester) async {
      final first = _LayoutLog();
      final second = _LayoutLog();
      final pages = {
        'first': _LayoutProbe(first),
        'second': _LayoutProbe(second),
      };
      var active = 'first';
      var viewport = const Size(400, 300);
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox.fromSize(
                size: viewport,
                child: RetainedPageStack(pages: pages, activeKey: active),
              );
            },
          ),
        ),
      );
      expect(first.size, viewport);
      expect(second.layouts, 0);
      rebuild(() => active = 'second');
      await tester.pumpAndSettle();
      final hiddenLayouts = first.layouts;
      final activeLayouts = second.layouts;
      rebuild(() => viewport = const Size(600, 450));
      await tester.pumpAndSettle();
      expect(first.layouts, hiddenLayouts);
      expect(first.size, const Size(400, 300));
      expect(second.layouts, greaterThan(activeLayouts));
      expect(second.size, viewport);
      rebuild(() => active = 'first');
      await tester.pumpAndSettle();
      expect(first.layouts, greaterThan(hiddenLayouts));
      expect(first.size, viewport);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden page retains draft and scroll but cannot receive focus', (
    tester,
  ) async {
    final pageKey = GlobalKey<_RetainedPageState>();
    final pages = <Object, Widget>{
      'first': _RetainedPage(key: pageKey),
      'second': const Text('Second page'),
    };
    var active = 'first';
    var viewport = const Size(400, 300);
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SizedBox.fromSize(
              size: viewport,
              child: RetainedPageStack(pages: pages, activeKey: active),
            );
          },
        ),
      ),
    );
    final retained = pageKey.currentState!;
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    retained.scroll.jumpTo(420);
    await tester.pumpAndSettle();
    final offset = retained.scroll.offset;
    rebuild(() => active = 'second');
    await tester.pumpAndSettle();
    expect(find.byType(_RetainedPage), findsNothing);
    expect(pageKey.currentState, same(retained));
    expect(retained.focus.canRequestFocus, isFalse);
    retained.focus.requestFocus();
    await tester.pump();
    expect(retained.focus.hasFocus, isFalse);
    rebuild(() => viewport = const Size(550, 400));
    await tester.pumpAndSettle();
    rebuild(() => active = 'first');
    await tester.pumpAndSettle();
    expect(pageKey.currentState, same(retained));
    expect(retained.draft.text, 'Keep my draft');
    expect(retained.scroll.offset, closeTo(offset, .01));
    expect(retained.focus.canRequestFocus, isTrue);
    expect(retained.disposed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(retained.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'only active page exposes semantics visibility and enabled tickers',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final modes = <String, (bool, bool)>{};
      Widget page(String name) => Builder(
        builder: (context) {
          modes[name] = (
            TickerMode.valuesOf(context).enabled,
            Visibility.of(context),
          );
          return Semantics(
            container: true,
            label: name,
            child: const SizedBox.expand(),
          );
        },
      );
      final pages = {'first': page('first'), 'second': page('second')};
      var active = 'first';
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 400,
                height: 300,
                child: RetainedPageStack(pages: pages, activeKey: active),
              );
            },
          ),
        ),
      );
      expect(find.bySemanticsLabel('first'), findsOneWidget);
      expect(find.bySemanticsLabel('second'), findsNothing);
      rebuild(() => active = 'second');
      await tester.pumpAndSettle();
      expect(modes['first'], (false, false));
      expect(modes['second'], (true, true));
      expect(find.bySemanticsLabel('first'), findsNothing);
      expect(find.bySemanticsLabel('second'), findsOneWidget);
      rebuild(() => active = 'first');
      await tester.pumpAndSettle();
      expect(modes['first'], (true, true));
      expect(modes['second'], (false, false));
      expect(find.bySemanticsLabel('first'), findsOneWidget);
      expect(find.bySemanticsLabel('second'), findsNothing);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
