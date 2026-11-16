// Copyright (c) LILYGO. All rights reserved.
import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main(List<String> args) async {
  final root = Platform.script.resolve('../');
  final header = root.resolve('src/codec.h');
  await FfiGenerator(
    input: Input(entryPoints: [header], include: (uri) => uri == header),
    output: Output(
      dart: DartOutput(path: root.resolve('lib/src/third_party/codec.g.dart')),
      style: const NativeExternalBindings(
        assetId: 'package:lilygobox_codecs/src/third_party/codec.g.dart',
      ),
      preamble: '// Copyright (c) LILYGO. All rights reserved.',
    ),
    visitors: [
      Visitor(
        func: (node) {
          if (node.originalName.startsWith('lb_')) node.isIncluded = true;
        },
      ),
    ],
  ).generate(
    libclangDylib: args.isEmpty ? null : File(args.single).absolute.uri,
  );
}
