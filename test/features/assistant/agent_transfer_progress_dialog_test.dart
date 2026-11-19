import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/l10n/delegates.dart';
import 'package:lilygobox/core/theme/definition.dart';
import 'package:lilygobox/core/theme/material_palette.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/features/assistant/domain/agent_package_progress.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/agent_transfer_progress_dialog.dart';
import 'package:lilygobox/features/assistant/state/storage_controller.dart';
import 'package:material_ui/material_ui.dart';

class _Controller extends ChangeNotifier implements AgentStorageController {
  @override
  AgentPackageProgress? transferProgress = const AgentPackageProgress(
    AgentPackageStage.reading,
  );
  int cancellations = 0;

  @override
  void cancelTransfer() {
    cancellations++;
  }

  @override
  Future<T> runTransfer<T>(Future<T> Function() operation) => operation();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'package dialog shows byte progress and disables cancel at commit',
    (tester) async {
      final progress = ValueNotifier(
        const AgentPackageProgress(
          AgentPackageStage.compressing,
          completed: 68,
          total: 100,
        ),
      );
      addTearDown(progress.dispose);
      var cancellations = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: Scaffold(
            body: AgentTransferProgressDialog(
              theme: MaterialPalette.create(ThemeType.light),
              progress: progress,
              readProgress: () => progress.value,
              onCancel: () => cancellations++,
            ),
          ),
        ),
      );
      expect(find.text('68%'), findsOneWidget);
      expect(find.text('正在压缩数据'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('storage-transfer-progress-bar')),
            )
            .value,
        .68,
      );
      progress.value = const AgentPackageProgress(
        AgentPackageStage.checksumming,
        completed: 524288,
        total: 1048576,
      );
      await tester.pump();
      expect(find.text('正在校验数据完整性'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      progress.value = const AgentPackageProgress(
        AgentPackageStage.committing,
        canCancel: false,
      );
      await tester.pump();
      expect(find.text('正在完成导入'), findsOneWidget);
      expect(find.text('68%'), findsNothing);
      expect(find.text('50%'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('storage-transfer-progress-bar')),
            )
            .value,
        isNull,
      );
      expect(
        tester
            .widget<AppActionButton>(
              find.byKey(const ValueKey('storage-transfer-cancel')),
            )
            .onPressed,
        isNull,
      );
      expect(cancellations, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancel waits for operation cleanup and prevents repeated requests',
    (tester) async {
      final progress = ValueNotifier(
        const AgentPackageProgress(AgentPackageStage.reading),
      );
      addTearDown(progress.dispose);
      var cancellations = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: Scaffold(
            body: AgentTransferProgressDialog(
              theme: MaterialPalette.create(ThemeType.dark),
              progress: progress,
              readProgress: () => progress.value,
              onCancel: () => cancellations++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('storage-transfer-cancel')));
      await tester.pump();
      expect(cancellations, 1);
      expect(find.text('正在取消'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('storage-transfer-progress-dialog')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppActionButton>(
              find.byKey(const ValueKey('storage-transfer-cancel')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('progress helper closes its own route after operation cleanup', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    final operation = Completer<String>();
    Future<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showAgentTransferProgress<String>(
                context: context,
                theme: MaterialPalette.create(ThemeType.light),
                controller: controller,
                work: () => operation.future,
              );
            },
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('storage-transfer-progress-dialog')),
      findsOneWidget,
    );
    expect(controller.cancellations, 0);
    await tester.tap(find.byKey(const ValueKey('storage-transfer-cancel')));
    await tester.pump();
    expect(controller.cancellations, 1);
    expect(
      find.byKey(const ValueKey('storage-transfer-progress-dialog')),
      findsOneWidget,
    );
    operation.complete('cleaned up');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await result!, 'cleaned up');
    expect(
      find.byKey(const ValueKey('storage-transfer-progress-dialog')),
      findsNothing,
    );
    expect(find.text('start'), findsOneWidget);
  });

  testWidgets('commit hides the dialog while retaining the modal barrier', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    final operation = Completer<void>();
    Future<void>? transfer;
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => transfer = showAgentTransferProgress<void>(
                context: context,
                theme: MaterialPalette.create(ThemeType.light),
                controller: controller,
                work: () => operation.future,
                onCommit: () => commits++,
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final cancel = find.byKey(const ValueKey('storage-transfer-cancel'));
    expect(tester.widget<AppActionButton>(cancel).onPressed, isNotNull);
    controller.transferProgress = const AgentPackageProgress(
      AgentPackageStage.committing,
      canCancel: false,
    );
    controller.notifyListeners();
    await tester.pump();
    expect(commits, 1);
    expect(cancel, findsNothing);
    expect(find.text('start').hitTestable(), findsNothing);
    operation.complete();
    await tester.pumpAndSettle();
    await transfer;
    expect(find.text('start').hitTestable(), findsOneWidget);
  });

  testWidgets('progress dialog fits narrow window at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = ValueNotifier(
      const AgentPackageProgress(AgentPackageStage.decompressing),
    );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: AgentTransferProgressDialog(
            theme: MaterialPalette.create(ThemeType.dark),
            progress: progress,
            readProgress: () => progress.value,
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Decompressing data'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final cancelled in [false, true]) {
    testWidgets(
      'helper removes progress route on ${cancelled ? 'cancellation' : 'failure'}',
      (tester) async {
        final controller = _Controller();
        addTearDown(controller.dispose);
        final operation = Completer<void>();
        Future<void>? checked;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: Builder(
              builder: (context) => TextButton(
                child: const Text('start'),
                onPressed: () {
                  final result = showAgentTransferProgress<void>(
                    context: context,
                    theme: MaterialPalette.create(ThemeType.light),
                    controller: controller,
                    work: () => operation.future,
                  );
                  checked = expectLater(
                    result,
                    cancelled
                        ? throwsA(isA<AgentPackageCancelled>())
                        : throwsStateError,
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        operation.completeError(
          cancelled ? const AgentPackageCancelled() : StateError('failed'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await checked;
        expect(
          find.byKey(const ValueKey('storage-transfer-progress-dialog')),
          findsNothing,
        );
        expect(find.text('start'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
