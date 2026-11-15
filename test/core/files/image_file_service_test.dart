import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/files/image_file_service.dart';

class _SaveDialog extends FileSelectorPlatform {
  String? path;
  String? suggestedName;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    suggestedName = options.suggestedName;
    return path == null ? null : FileSaveLocation(path!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'save preserves original image bytes and suggests matching extension',
    () async {
      final original = FileSelectorPlatform.instance;
      final dialog = _SaveDialog();
      FileSelectorPlatform.instance = dialog;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final directory = await Directory.systemTemp.createTemp(
        'image-save-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(directory.path + Platform.pathSeparator + 'saved.jpg');
      dialog.path = file.path;
      final bytes = Uint8List.fromList([255, 216, 255, 224, 0, 1, 2, 3]);
      await ImageFileService.saveAs(bytes, label: 'Save image as');
      expect(dialog.suggestedName, 'image.jpg');
      expect(await file.readAsBytes(), orderedEquals(bytes));
    },
  );

  test('canceling the save dialog completes without writing a file', () async {
    final original = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _SaveDialog();
    addTearDown(() => FileSelectorPlatform.instance = original);
    await expectLater(
      ImageFileService.saveAs(
        Uint8List.fromList([255, 216, 255]),
        label: 'Save image as',
      ),
      completes,
    );
  });
}
