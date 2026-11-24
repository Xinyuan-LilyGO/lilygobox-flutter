import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lilygobox/features/speech/domain/speech_model.dart';
import 'package:path/path.dart' as path;

Future<String> speechArchiveFixture(
  Directory root,
  String name,
  SpeechModelFormat format, {
  String? modelFolder,
  String? missing,
  Map<String, String> extra = const {},
}) async {
  final entries = {
    for (final relative in format.files)
      if (relative != missing) relative: relative,
    ...extra,
  };
  final archive = Archive();
  for (final MapEntry(key: relative, value: text) in entries.entries) {
    final bytes = utf8.encode(text);
    archive.addFile(
      ArchiveFile(
        modelFolder == null ? relative : '$modelFolder/$relative',
        bytes.length,
        bytes,
      ),
    );
  }
  final file = File(path.join(root.path, '$name.tar.bz2'));
  await file.writeAsBytes(BZip2Encoder().encode(TarEncoder().encode(archive)));
  return file.path;
}
