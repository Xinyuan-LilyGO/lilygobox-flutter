import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_content_window.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/conversation_scroll_controller.dart';

class _ContentFixture {
  _ContentFixture({
    this.count = 1000,
    this.revision = 1,
    this.segmentHeight = 300,
    this.before = 0,
    this.after = 0,
    this.horizontal = false,
    Object? historyId,
  }) {
    registry = ChatContentRegistry(
      controller: controller,
      followsLatest: () => followsLatest,
      hasSelection: () => selected,
      onChanged: () {
        notifications++;
        onNotified?.call();
      },
      storageId: historyId,
    );
  }

  final controller = ConversationScrollController();
  final window = GlobalKey<ChatContentWindowState>();
  final bucket = PageStorageBucket();
  late final ChatContentRegistry registry;
  int count;
  int revision;
  double segmentHeight;
  double before;
  double after;
  bool horizontal;
  bool followsLatest = false;
  bool selected = false;
  int notifications = 0;
  int builds = 0;
  VoidCallback? onNotified;

  ChatContentWindowState get state => window.currentState!;

  Widget app({
    bool scoped = true,
    ChatContentRegistry? registryOverride,
    Widget? additionalBody,
    IndexedWidgetBuilder? itemBuilder,
  }) {
    Widget body = ChatContentWindow(
      key: window,
      storageId: 'body',
      revision: revision,
      childCount: count,
      itemBuilder: (context, index) {
        builds++;
        return itemBuilder?.call(context, index) ??
            SizedBox(
              key: ValueKey('segment-$index'),
              width: horizontal ? 1200 : 400,
              height: segmentHeight,
              child: Text('Segment $index'),
            );
      },
    );
    if (horizontal) {
      body = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: body,
      );
    }
    Widget viewport = SingleChildScrollView(
      key: const PageStorageKey('content-scroll'),
      controller: controller,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(key: const ValueKey('before-content'), height: before),
          ChatContentMessageScope(messageId: 'message', child: body),
          ?additionalBody,
          SizedBox(height: after),
        ],
      ),
    );
    if (scoped) {
      viewport = ChatContentScope(
        state: registryOverride ?? registry,
        child: viewport,
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 200,
          child: PageStorage(bucket: bucket, child: viewport),
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    registry.dispose();
    controller.dispose();
  }
}

Finder _segment(int index) => find.byKey(ValueKey('segment-$index'));

void main() {
  testWidgets(
    'preloading a lower message preserves a 100px upward wheel step',
    (tester) async {
      final fixture = _ContentFixture(before: 1000);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: ScrollConfiguration(
            behavior: const AppScrollBehavior(scrollbars: false),
            child: fixture.app(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      fixture.controller.jumpTo(980);
      final start = fixture.controller.offset;
      final upper = find.byKey(const ValueKey('before-content'));
      final originalTop = tester.getTopLeft(upper).dy;
      final first = fixture.state.firstChildIndex;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(SingleChildScrollView)),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.state.firstChildIndex, lessThan(first));
      expect(fixture.controller.offset, closeTo(start - 100, .01));
      expect(tester.getTopLeft(upper).dy, closeTo(originalTop + 100, .01));
      expect(fixture.state.loadedChildCount, lessThan(32));
      await fixture.close(tester);
    },
  );

  testWidgets('without a conversation scope all segments remain available', (
    tester,
  ) async {
    final fixture = _ContentFixture(count: 20, revision: 9, segmentHeight: 150);
    await tester.pumpWidget(fixture.app(scoped: false));
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 20);
    expect(_segment(0), findsOneWidget);
    expect(_segment(19), findsOneWidget);
    await fixture.close(tester);
  });

  for (final count in [10000, 100000, 1000000]) {
    testWidgets('$count segments initially build only the tail window', (
      tester,
    ) async {
      final fixture = _ContentFixture(count: count);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 4);
      expect(fixture.builds, 4);
      expect(_segment(count - 1), findsOneWidget);
      expect(_segment(0), findsNothing);
      expect(fixture.registry.hasEarlier, isTrue);
      expect(fixture.registry.hasLater, isFalse);
      expect(fixture.controller.position.extentAfter, 0);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  testWidgets('preloading preserves the visible segment screen position', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.controller.jumpTo(300);
    final anchor = _segment(997);
    final before = tester.getTopLeft(anchor).dy;
    await tester.pumpAndSettle();
    expect(fixture.state.firstChildIndex, 992);
    expect(fixture.state.loadedChildCount, 8);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
    expect(fixture.controller.offset, closeTo(1500, .01));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('scrolling between preload scheduling and layout is preserved', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.controller.jumpTo(300);
    await tester.pump();
    fixture.controller.jumpTo(350);
    await tester.pumpAndSettle();
    expect(fixture.controller.offset, closeTo(1550, .01));
    expect(fixture.state.loadedChildCount, 8);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets(
    'offscreen bodies use their local bounds instead of scroll pixels',
    (tester) async {
      final fixture = _ContentFixture(before: 10000, after: 1000);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 4);
      fixture.controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 4);
      fixture.controller.jumpTo(10300);
      final anchor = _segment(997);
      final before = tester.getTopLeft(anchor).dy;
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 8);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(fixture.controller.offset, closeTo(11500, .01));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'horizontal code scrolling retains the vertical viewport anchor',
    (tester) async {
      final fixture = _ContentFixture(horizontal: true, before: 1000);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 4);
      fixture.controller.jumpTo(1300);
      final anchor = _segment(997);
      final before = tester.getTopLeft(anchor).dy;
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, 8);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets('reading earlier segments unloads distant later segments', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (var batch = 0; batch < 20; batch++) {
      fixture.controller.jumpTo(300);
      await tester.pumpAndSettle();
      expect(fixture.state.loadedChildCount, lessThanOrEqualTo(24));
      expect(tester.takeException(), isNull);
    }
    expect(fixture.registry.hasLater, isTrue);
    expect(_segment(999), findsNothing);
    fixture.registry.showLatest();
    await tester.pumpAndSettle();
    expect(_segment(999), findsOneWidget);
    expect(fixture.registry.hasLater, isFalse);
    expect(fixture.state.loadedChildCount, lessThanOrEqualTo(24));
    await fixture.close(tester);
  });

  testWidgets('an active selection retains all loaded segments until cleared', (
    tester,
  ) async {
    final fixture = _ContentFixture()..selected = true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (var batch = 0; batch < 8; batch++) {
      fixture.controller.jumpTo(300);
      await tester.pumpAndSettle();
    }
    expect(fixture.state.loadedChildCount, 36);
    expect(_segment(999), findsOneWidget);
    fixture.selected = false;
    fixture.registry.selectionChanged();
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, lessThanOrEqualTo(24));
    expect(_segment(999), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'pointer ${cancel ? 'cancel' : 'up'} resumes frozen preloading',
      (tester) async {
        final fixture = _ContentFixture();
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();
        fixture.registry.pointerDown(
          const PointerDownEvent(pointer: 7, buttons: kPrimaryMouseButton),
        );
        fixture.controller.jumpTo(300);
        await tester.pumpAndSettle();
        expect(fixture.state.loadedChildCount, 4);
        if (cancel) {
          fixture.registry.pointerCancel(const PointerCancelEvent(pointer: 7));
        } else {
          fixture.registry.pointerUp(const PointerUpEvent(pointer: 7));
        }
        await tester.pumpAndSettle();
        expect(fixture.state.loadedChildCount, 8);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      },
    );
  }

  testWidgets('streaming follows the tail only when the conversation follows', (
    tester,
  ) async {
    final fixture = _ContentFixture()..followsLatest = true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.count = 1004;
    fixture.revision++;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_segment(1003), findsOneWidget);
    expect(fixture.registry.hasLater, isFalse);
    fixture.followsLatest = false;
    fixture.count = 1008;
    fixture.revision++;
    await tester.pumpWidget(fixture.app());
    expect(fixture.registry.hasLater, isTrue);
    expect(_segment(1007), findsNothing);
    fixture.registry.showLatest();
    await tester.pumpAndSettle();
    expect(_segment(1007), findsOneWidget);
    expect(fixture.registry.hasLater, isFalse);
    await fixture.close(tester);
  });

  testWidgets('streaming during a scrollbar drag waits for release', (
    tester,
  ) async {
    final fixture = _ContentFixture()..followsLatest = true;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.registry.pointerDown(
      const PointerDownEvent(pointer: 7, buttons: kPrimaryMouseButton),
    );
    fixture.count = 1004;
    fixture.revision++;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_segment(1003), findsNothing);
    fixture.registry.pointerUp(const PointerUpEvent(pointer: 7));
    await tester.pumpAndSettle();
    expect(_segment(1003), findsOneWidget);
    expect(fixture.registry.hasLater, isFalse);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('PageStorage restores a content range with its scroll offset', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (var batch = 0; batch < 3; batch++) {
      fixture.controller.jumpTo(300);
      await tester.pumpAndSettle();
    }
    final start = fixture.state.firstChildIndex;
    final end = fixture.state.lastChildIndex;
    final offset = fixture.controller.offset;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.state.firstChildIndex, start);
    expect(fixture.state.lastChildIndex, end);
    expect(fixture.controller.offset, closeTo(offset, .01));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('stored ranges are invalidated when the content is replaced', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.controller.jumpTo(300);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture.revision++;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 4);
    expect(fixture.state.firstChildIndex, 996);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('independent message bodies preserve separate stored ranges', (
    tester,
  ) async {
    final fixture = _ContentFixture(historyId: 'conversation');
    final secondWindow = GlobalKey<ChatContentWindowState>();
    Widget app() => fixture.app(
      additionalBody: ChatContentWindow(
        key: secondWindow,
        storageId: 'another-body',
        revision: fixture.revision,
        childCount: fixture.count,
        itemBuilder: (context, index) => SizedBox(
          key: ValueKey('other-$index'),
          height: fixture.segmentHeight,
          child: Text('Other $index'),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 4);
    expect(secondWindow.currentState!.loadedChildCount, 4);
    fixture.controller.jumpTo(300);
    final anchor = _segment(997);
    final before = tester.getTopLeft(anchor).dy;
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    expect(secondWindow.currentState!.loadedChildCount, 4);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, .01));
    final offset = fixture.controller.offset;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    expect(secondWindow.currentState!.loadedChildCount, 4);
    expect(fixture.controller.offset, closeTo(offset, .01));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('a cloned history does not reuse another history content range', (
    tester,
  ) async {
    final fixture = _ContentFixture(historyId: 'original-history');
    final otherRegistry = ChatContentRegistry(
      controller: fixture.controller,
      followsLatest: () => false,
      hasSelection: () => false,
      onChanged: () {},
      storageId: 'cloned-history',
    );
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app(registryOverride: otherRegistry));
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 4);
    expect(fixture.state.firstChildIndex, 996);
    expect(fixture.registry.hasEarlier, isFalse);
    expect(otherRegistry.hasEarlier, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    expect(otherRegistry.hasEarlier, isFalse);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
    otherRegistry.dispose();
  });

  testWidgets('coalesced registry changes allow a parent setState callback', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          fixture.onNotified = () => setState(() {});
          return fixture.app();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.notifications, 1);
    expect(tester.takeException(), isNull);
    fixture.controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    expect(fixture.notifications, 2);
    expect(tester.takeException(), isNull);
    fixture.onNotified = null;
    await fixture.close(tester);
  });

  testWidgets('replacing a scope moves registration without stale listeners', (
    tester,
  ) async {
    final fixture = _ContentFixture(historyId: 'first');
    var secondNotifications = 0;
    final replacement = ChatContentRegistry(
      controller: fixture.controller,
      followsLatest: () => false,
      hasSelection: () => false,
      onChanged: () => secondNotifications++,
      storageId: 'second',
    );
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.registry.hasEarlier, isTrue);
    await tester.pumpWidget(fixture.app(registryOverride: replacement));
    await tester.pumpAndSettle();
    expect(fixture.registry.hasEarlier, isFalse);
    expect(replacement.hasEarlier, isTrue);
    fixture.registry.dispose();
    fixture.controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(fixture.state.loadedChildCount, 8);
    expect(secondNotifications, 2);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
    replacement.dispose();
  });

  testWidgets('older message tails do not mark the latest message incomplete', (
    tester,
  ) async {
    final fixture = _ContentFixture();
    final latestWindow = GlobalKey<ChatContentWindowState>();
    await tester.pumpWidget(
      fixture.app(
        additionalBody: ChatContentMessageScope(
          messageId: 'latest-message',
          child: ChatContentWindow(
            key: latestWindow,
            storageId: 'latest-body',
            revision: 1,
            childCount: 1000,
            itemBuilder: (context, index) =>
                SizedBox(height: 300, child: Text('Latest $index')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var batch = 0; batch < 8; batch++) {
      fixture.controller.jumpTo(300);
      await tester.pumpAndSettle();
    }
    expect(fixture.registry.hasLater, isTrue);
    expect(fixture.registry.hasLaterFor('message'), isTrue);
    expect(fixture.registry.hasLaterFor('latest-message'), isFalse);
    fixture.controller.jumpTo(fixture.controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(latestWindow.currentState!.hasLater, isFalse);
    expect(fixture.registry.hasLaterFor('latest-message'), isFalse);
    expect(fixture.registry.hasLaterFor('missing-message'), isFalse);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets(
    'only the final nested content branch controls the message tail',
    (tester) async {
      final fixture = _ContentFixture(count: 2);
      final earlierCode = GlobalKey<ChatContentWindowState>();
      final lastCode = GlobalKey<ChatContentWindowState>();
      await tester.pumpWidget(
        fixture.app(
          itemBuilder: (context, index) => ChatContentWindow(
            key: index == 0 ? earlierCode : lastCode,
            storageId: 'code-$index',
            revision: 1,
            childCount: 1000,
            itemBuilder: (context, line) =>
                SizedBox(height: 300, child: Text('Code $index line $line')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var batch = 0; batch < 8; batch++) {
        fixture.controller.jumpTo(300);
        await tester.pumpAndSettle();
      }
      expect(earlierCode.currentState!.hasLater, isTrue);
      expect(fixture.registry.hasLater, isTrue);
      expect(fixture.registry.hasLaterFor('message'), isFalse);
      expect(lastCode.currentState!.hasLater, isFalse);
      for (var batch = 0; batch < 8; batch++) {
        final firstHeight = tester.getSize(find.byKey(earlierCode)).height;
        fixture.controller.jumpTo(firstHeight + 300);
        await tester.pumpAndSettle();
      }
      expect(lastCode.currentState!.hasLater, isTrue);
      expect(fixture.registry.hasLaterFor('message'), isTrue);
      fixture.registry.showLatest();
      await tester.pumpAndSettle();
      expect(fixture.registry.hasLaterFor('message'), isFalse);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
