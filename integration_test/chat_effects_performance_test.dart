import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/navigation/provider.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/data/agent_storage.dart';
import 'package:lilygobox/features/assistant/data/conversation_codec.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/presentation/pages/page.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_bottom_fade.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../test/features/assistant/assistant_test_scope.dart';

Future<Map<String, dynamic>> _conversation() async {
  const fixture = String.fromEnvironment('CHAT_PERF_DATABASE');
  if (fixture.isEmpty) {
    final content = List.generate(
      80,
      (section) =>
          '### Section $section\n\n'
          'A long message with paragraphs, selectable text and tables.\n\n'
          '| Item | Description | Example |\n'
          '| --- | --- | --- |\n'
          '| Paragraph | Text wraps within the available space. | $section |\n'
          '| Table | The layout includes several rows. | Example |\n\n',
    ).join('\n');
    return {
      'messages': [
        ConversationCodec.message(
          AiMessage(
            id: 'chat-effects-long',
            role: 'assistant',
            content: content,
          ),
        ),
      ],
      'history': <Map<String, Object?>>[],
    };
  }
  final original = File(
    '${Platform.environment['LOCALAPPDATA']}/LILYGO/LilygoBox/data/main.db',
  ).absolute.path.toLowerCase();
  final copied = File(fixture).absolute.path;
  if (copied.toLowerCase() == original) {
    throw ArgumentError('Use a database copy for the performance fixture');
  }
  final storage = AgentStorage(path: copied);
  try {
    final workflow = await storage.request('readWorkflowData') as Map;
    final sessions = (workflow['sessions'] as List).cast<Map>().toList();
    int length(Map session) {
      final conversation = session['conversation'] as Map;
      return (conversation['messages'] as List).fold(
        0,
        (total, message) =>
            total + ((message as Map)['content'] as String).length,
      );
    }

    sessions.sort((first, second) => length(second).compareTo(length(first)));
    const title = String.fromEnvironment('CHAT_PERF_TITLE');
    final selected = title.isEmpty
        ? sessions.first
        : sessions.firstWhere(
            (session) => (session['title'] as String).contains(title),
          );
    return Map<String, dynamic>.from(selected['conversation'] as Map);
  } finally {
    await storage.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'compare chat gradients and composer shadows in a native window',
    (tester) async {
      debugPrint('CHAT_EFFECTS_SETUP: window');
      await tester.pumpWidget(const SizedBox.shrink());
      final handle = (await tester.runAsync(
        () =>
            const MethodChannel('lilygobox/window_layout')
                .invokeMethod<int>('getWindowHandle'),
      ))!;
      final isMaximized = ffi.DynamicLibrary.open('user32.dll')
          .lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
            'IsZoomed',
          );
      final theme = ThemeProvider();
      final language = LanguageProvider();
      final shell = AppShellProvider();
      final split = SplitViewProvider();
      final navigation = AppNavigationProvider();
      debugPrint('CHAT_EFFECTS_SETUP: providers');
      final scope = (await tester.runAsync(
        () => createAssistantTestScope(
          theme: theme,
          language: language,
          shell: shell,
          splitView: split,
        ),
      ))!;
      await tester.runAsync(() => scope.provider.initialized);
      debugPrint('CHAT_EFFECTS_SETUP: conversation');
      final snapshot = (await tester.runAsync(_conversation))!;
      debugPrint('CHAT_EFFECTS_SETUP: widgets');
      scope.provider.restoreWorkspaceConversation(snapshot);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: language),
            ChangeNotifierProvider.value(value: navigation),
            ChangeNotifierProvider.value(value: scope.provider),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationDelegates,
            scrollBehavior: const AppScrollBehavior(),
            theme: ThemeData(
              colorScheme: theme.themeData.materialColors,
              scrollbarTheme: const ScrollbarThemeData(
                crossAxisMargin: AppScrollBehavior.scrollbarEdgeInset,
              ),
            ),
            home: const Scaffold(body: AssistantPage()),
          ),
        ),
      );
      Future<void> frames([int count = 20]) async {
        for (var frame = 0; frame < count; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      }

      await frames();
      await tester.runAsync(
        () =>
            const MethodChannel('lilygobox/window_layout')
                .invokeMethod<void>('toggleMaximize'),
      );
      await frames(60);
      expect(isMaximized(handle), isNot(0));
      final scrollFinder = find.byKey(const ValueKey('ai-message-scroll'));
      final scroll = tester
          .widget<SingleChildScrollView>(scrollFinder)
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(5000));
      final start = scroll.position.maxScrollExtent * .45;
      scroll.jumpTo(start);
      await frames();
      final point = tester.getCenter(scrollFinder);
      final timestamp = Stopwatch()..start();
      final paths = <Map<String, double>>[];
      Future<void> wheelPath() async {
        final before = scroll.offset;
        var minimum = before;
        var maximum = before;
        for (var event = 0; event < 96; event++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              viewId: tester.view.viewId,
              position: point,
              scrollDelta: Offset(0, event < 48 ? 48 : -48),
              timeStamp: timestamp.elapsed,
              kind: PointerDeviceKind.mouse,
            ),
          );
          await frames(2);
          if (scroll.offset < minimum) minimum = scroll.offset;
          if (scroll.offset > maximum) maximum = scroll.offset;
        }
        await frames(18);
        paths.add({
          'start': before,
          'minimum': minimum,
          'maximum': maximum,
          'end': scroll.offset,
        });
        expect(maximum - minimum, greaterThan(1000));
        expect(scroll.offset, greaterThan(0));
        expect(scroll.position.extentAfter, greaterThan(120));
      }

      final fades = find.descendant(
        of: find.byType(ChatBottomFade),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient != null,
        ),
      );
      expect(fades, findsNWidgets(2));
      final fadeDecorations = {
        for (final render in tester.renderObjectList<RenderDecoratedBox>(fades))
          render: render.decoration,
      };
      final composer = tester.renderObject<RenderDecoratedBox>(
        find.byKey(const ValueKey('ai-composer-context-layer')),
      );
      final composerDecoration = composer.decoration as BoxDecoration;
      expect(composerDecoration.boxShadow, isNotEmpty);
      final display = tester.view.display;
      final semantics = const bool.fromEnvironment('CHAT_PERF_SEMANTICS')
          ? tester.ensureSemantics()
          : null;
      await frames();
      binding.reportData = {
        'fixture': {
          'real_conversation_copy': const String.fromEnvironment(
            'CHAT_PERF_DATABASE',
          ).isNotEmpty,
          'message_count': scope.provider.messages.length,
          'total_characters': scope.provider.messages.fold<int>(
            0,
            (total, message) => total + message.content.length,
          ),
          'longest_message_characters': scope.provider.messages.fold<int>(
            0,
            (longest, message) => message.content.length > longest
                ? message.content.length
                : longest,
          ),
          'semantics_enabled':
              binding.renderViews.single.owner?.semanticsOwner != null,
          'title_filter': const String.fromEnvironment('CHAT_PERF_TITLE'),
          'max_scroll_extent': scroll.position.maxScrollExtent,
          'physical_width': tester.view.physicalSize.width,
          'physical_height': tester.view.physicalSize.height,
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'refresh_rate': display.refreshRate,
          'native_maximized': isMaximized(handle) != 0,
          'window_scope': 'production_chat_in_opaque_native_test_window',
          'wheel_events_per_run': 96,
          'wheel_delta': 48,
          'event_cadence_ms': 32,
          'summary_budget_ms': 16,
          'display_budget_ms': 1000 / display.refreshRate,
        },
      };
      const variants = [
        (name: 'original', fade: true, shadow: true),
        (name: 'no_fade', fade: false, shadow: true),
        (name: 'no_shadow', fade: true, shadow: false),
        (name: 'neither', fade: false, shadow: false),
      ];
      try {
        for (final round in [0, 1]) {
          for (final variant in round == 0 ? variants : variants.reversed) {
            scroll.jumpTo(start);
            await frames();
            for (final entry in fadeDecorations.entries) {
              entry.key.decoration = variant.fade
                  ? entry.value
                  : const BoxDecoration();
            }
            composer.decoration = variant.shadow
                ? composerDecoration
                : composerDecoration.copyWith(boxShadow: const []);
            await frames();
            await wheelPath();
            scroll.jumpTo(start);
            await frames();
            final key = '${variant.name}_$round';
            debugPrint('CHAT_EFFECTS_MEASURE: $key');
            await binding.watchPerformance(wheelPath, reportKey: key);
            expect(
              (composer.decoration as BoxDecoration).boxShadow?.isNotEmpty,
              variant.shadow,
            );
            for (final render in fadeDecorations.keys) {
              expect(
                (render.decoration as BoxDecoration).gradient != null,
                variant.fade,
              );
            }
          }
        }
        binding.reportData!['scroll_paths'] = paths;
      } finally {
        for (final entry in fadeDecorations.entries) {
          entry.key.decoration = entry.value;
        }
        composer.decoration = composerDecoration;
        await tester.pumpWidget(const SizedBox.shrink());
        semantics?.dispose();
        scope.dispose();
        theme.dispose();
        language.dispose();
        shell.dispose();
        split.dispose();
        navigation.dispose();
      }
    },
  );
}
