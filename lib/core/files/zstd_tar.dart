import 'package:archive/archive_io.dart';

import 'zstd_file.dart';

abstract final class ZstdTar {
  static const suffix = '.tar.${ZstdFile.extension}';

  static String withSuffix(String name) => ZstdFile.withSuffix(name, suffix);

  static Future<String> exportPath(String requested) =>
      ZstdFile.exportPath(requested, suffix);

  static TarChunkedEncoder writer(OutputStream output) => TarChunkedEncoder(
    const ZstdEncoderConverter(level: 3)
        .startChunkedConversion(_ArchiveSink(output)),
  );
}

class _ArchiveSink implements Sink<List<int>> {
  const _ArchiveSink(this.output);

  final OutputStream output;

  @override
  void add(List<int> bytes) => output.writeBytes(bytes);

  @override
  void close() => output.flush();
}
