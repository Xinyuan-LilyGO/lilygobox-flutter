import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lilygobox/app/bootstrap/window_bootstrap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('custom desktop frame disables duplicate native shadow', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    await configureDesktopWindow();
    final window = WindowManager.instance.getCurrent();
    expect(window, isNotNull);
    expect(window!.hasShadow, isFalse);
    // Reconfiguring a window must not restore the native shadow.
    await configureDesktopWindow();
    expect(window.hasShadow, isFalse);
  });
}
