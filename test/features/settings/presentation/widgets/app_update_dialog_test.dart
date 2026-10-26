import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/app_info/app_update_service.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/action_button.dart';
import 'package:lilygobox/features/settings/presentation/widgets/about_content.dart';
import 'package:lilygobox/generated/l10n/app_localizations.dart';
import 'package:lilygobox/generated/l10n/app_localizations_zh.dart';

void main() {
  for (final failure in [
    AppUpdateFailureKind.integrity,
    AppUpdateFailureKind.network,
  ]) {
    testWidgets('application failure has one recovery action ($failure)', (
      tester,
    ) async {
      final theme = ThemeProvider();
      addTearDown(theme.dispose);
      final l10n = AppLocalizationsZh();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppUpdateDialog(
            theme: theme.themeData,
            currentVersion: '1.0.0-beta.0',
            initialFailure: failure,
            initialUpdate: AppUpdate(
              version: '1.0.0-beta.1',
              fileName: 'test-missing-update.exe',
              downloadUrl: Uri.https('github.com', '/test.exe'),
              sizeBytes: 3,
              sha256: 'a' * 64,
              releaseNotes: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          failure == AppUpdateFailureKind.integrity
              ? l10n.redownloadUpdate
              : l10n.retry,
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.downloadAppUpdate), findsNothing);
      expect(find.byType(AppActionButton), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
