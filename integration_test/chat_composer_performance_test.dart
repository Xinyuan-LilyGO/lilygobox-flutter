import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/shell/state/provider.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/l10n/language_provider.dart';
import 'package:lilygobox/core/layout/split_view_provider.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/app_scroll_behavior.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/chat_composer.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../test/features/assistant/assistant_test_scope.dart';

Future<List<({String name, String text})>> _inputs() async {
  final synthetic = (
    name: 'synthetic',
    text: List.generate(
      2000,
      (index) => '$index 中文输入 English 🌿 é العربية 文本保持完整。\n\n',
    ).join(),
  );
  const path = String.fromEnvironment('COMPOSER_PERF_PAYLOAD');
  if (path.isEmpty) return [synthetic];
  final payload = jsonDecode(await File(path).readAsString()) as Map;
  final workflow = payload['workflow'] as Map;
  final sessions = (workflow['sessions'] as List).cast<Map>();
  final session = sessions.firstWhere(
    (candidate) => candidate['id'] == workflow['selectedId'],
    orElse: () => sessions.first,
  );
  final conversation = session['conversation'] as Map;
  final messages = (conversation['messages'] as List).cast<Map>();
  final contents = [
    for (final message in messages) message['content'] as String,
  ];
  return [
    (
      name: 'longest_message',
      text: contents.reduce(
        (first, second) => first.length >= second.length ? first : second,
      ),
    ),
    (name: 'complete_conversation', text: contents.join('\n\n')),
    synthetic,
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile complete long input in a maximized native window', (
    tester,
  ) async {
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
    final input = TextEditingController();
    final focus = FocusNode();
    final scroll = ScrollController();
    final scope = (await tester.runAsync(
      () => createAssistantTestScope(
        theme: theme,
        language: language,
        shell: shell,
        splitView: split,
      ),
    ))!;
    await tester.runAsync(() => scope.provider.initialized);
    final inputs = (await tester.runAsync(_inputs))!;
    final semantics = const bool.fromEnvironment('COMPOSER_PERF_SEMANTICS')
        ? tester.ensureSemantics()
        : null;
    Future<void> frames([int count = 16]) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
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
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 820,
                child: ChatComposer(
                  input: input,
                  focusNode: focus,
                  scrollController: scroll,
                  theme: theme.themeData,
                  assistant: scope.provider,
                  ready: true,
                  onSend: (_) {},
                  attachments: const [],
                  onAttachmentsChanged: (_) {},
                  readClipboardImage: () async => null,
                ),
              ),
            ),
          ),
        ),
      );
      await frames();
      if (isMaximized(handle) == 0) {
        await tester.runAsync(
          () =>
              const MethodChannel('lilygobox/window_layout')
                  .invokeMethod<void>('toggleMaximize'),
        );
      }
      await frames(60);
      expect(isMaximized(handle), isNot(0));
      final viewport = find.byKey(const ValueKey('ai-input-scrollbar'));
      focus.requestFocus();
      await frames();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final paths = <Map<String, Object?>>[];
      binding.reportData = {
        'fixture': {
          'real_payload_copy': const String.fromEnvironment(
            'COMPOSER_PERF_PAYLOAD',
          ).isNotEmpty,
          'input_source': 'complete_controller_value',
          'inputs': [
            for (final entry in inputs)
              {'name': entry.name, 'characters': entry.text.length},
          ],
          'physical_width': tester.view.physicalSize.width,
          'physical_height': tester.view.physicalSize.height,
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'refresh_rate': tester.view.display.refreshRate,
          'native_maximized': isMaximized(handle) != 0,
          'semantics_enabled':
              binding.renderViews.single.owner?.semanticsOwner != null,
          'wheel_events_per_run': 48,
          'wheel_delta': 48,
          'event_cadence_ms': 32,
        },
      };
      final time = Stopwatch()..start();
      for (final entry in inputs) {
        for (final selected in [false, true]) {
          input.value = TextEditingValue(
            text: entry.text,
            selection: selected
                ? TextSelection(baseOffset: 0, extentOffset: entry.text.length)
                : const TextSelection.collapsed(offset: 0),
          );
          await frames();
          final start = scroll.position.maxScrollExtent * .45;
          scroll.jumpTo(start);
          await frames();
          final point = tester.getCenter(viewport);
          final key = '${entry.name}_${selected ? 'selected' : 'caret'}';
          debugPrint('COMPOSER_PROFILE_MEASURE: $key');
          await binding.watchPerformance(() async {
            var minimum = scroll.offset;
            var maximum = minimum;
            final wheelStart = time.elapsed;
            for (var event = 0; event < 48; event++) {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  viewId: tester.view.viewId,
                  position: point,
                  scrollDelta: Offset(0, event < 24 ? 48 : -48),
                  timeStamp: wheelStart + Duration(milliseconds: event * 32),
                  kind: PointerDeviceKind.mouse,
                ),
              );
              await frames(2);
              if (scroll.offset < minimum) minimum = scroll.offset;
              if (scroll.offset > maximum) maximum = scroll.offset;
            }
            await frames(18);
            paths.add({
              'key': key,
              'start': start,
              'minimum': minimum,
              'maximum': maximum,
              'end': scroll.offset,
              'renderer_selection_enabled': editable.selection != null,
              'sdk_selection_color_enabled': editable.selectionColor != null,
              'editable_scroll_offset': editable.offset.pixels,
            });
            expect(maximum - minimum, greaterThan(500));
            expect(editable.offset.pixels, 0);
            expect(input.text, entry.text);
            expect(
              input.selection,
              selected
                  ? TextSelection(
                      baseOffset: 0,
                      extentOffset: entry.text.length,
                    )
                  : const TextSelection.collapsed(offset: 0),
            );
          }, reportKey: key);
        }
      }
      binding.reportData!['scroll_paths'] = paths;
      final synthetic = inputs.firstWhere((entry) => entry.name == 'synthetic');
      input.clear();
      await frames();
      final pasteWatch = Stopwatch();
      int? valueApplied;
      int? firstLayoutComplete;
      void pasteListener() {
        if (input.text != synthetic.text || valueApplied != null) return;
        valueApplied = pasteWatch.elapsedMicroseconds;
        binding.addPostFrameCallback((_) {
          firstLayoutComplete = pasteWatch.elapsedMicroseconds;
        });
      }

      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => {'text': synthetic.text},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        },
      );
      input.addListener(pasteListener);
      try {
        await binding.watchPerformance(() async {
          pasteWatch.start();
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
          await tester.sendKeyEvent(
            LogicalKeyboardKey.keyV,
            physicalKey: PhysicalKeyboardKey.keyV,
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
          await frames(20);
          expect(input.text, synthetic.text);
          expect(input.selection.extentOffset, synthetic.text.length);
          expect(valueApplied, isNotNull);
          expect(firstLayoutComplete, isNotNull);
          expect(scroll.offset, greaterThan(1000));
          expect(find.byType(Scrollbar), findsOneWidget);
        }, reportKey: 'synthetic_clipboard_paste');
      } finally {
        input.removeListener(pasteListener);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      }
      binding.reportData!['paste_latency'] = {
        'characters': synthetic.text.length,
        'controller_applied_microseconds': valueApplied,
        'first_layout_complete_microseconds': firstLayoutComplete,
      };
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final editingLatency = <int>[];
      await binding.watchPerformance(() async {
        for (var edit = 0; edit < 10; edit++) {
          final watch = Stopwatch()..start();
          final end = input.text.length;
          editor.updateEditingValue(
            TextEditingValue(
              text: '${input.text}中',
              selection: TextSelection.collapsed(offset: end + 1),
              composing: TextRange(start: end, end: end + 1),
            ),
          );
          await tester.pump();
          editingLatency.add(watch.elapsedMicroseconds);
          expect(input.value.composing, TextRange(start: end, end: end + 1));
          await frames(1);
          watch.reset();
          editor.updateEditingValue(
            TextEditingValue(
              text: synthetic.text,
              selection: TextSelection.collapsed(offset: end),
            ),
          );
          await tester.pump();
          editingLatency.add(watch.elapsedMicroseconds);
          await frames(1);
        }
        await frames(18);
        expect(input.text, synthetic.text);
        expect(input.value.composing, TextRange.empty);
      }, reportKey: 'synthetic_end_editing');
      binding.reportData!['editing_latency'] = {
        'characters': synthetic.text.length,
        'composition_append_then_remove_cycles': 10,
        'update_through_layout_microseconds': editingLatency,
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics?.dispose();
      input.dispose();
      focus.dispose();
      scroll.dispose();
      scope.dispose();
      theme.dispose();
      language.dispose();
      shell.dispose();
      split.dispose();
    }
  });
}
