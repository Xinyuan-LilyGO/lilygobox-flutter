// Copyright (c) LILYGO. All rights reserved.
import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final root = input.packageRoot;
    final sources = <String>[
      'src/codec.c',
      for (final name in [
        'Alloc',
        'CpuArch',
        'LzFind',
        'LzmaEnc',
        'LzmaDec',
        'Lzma2Enc',
        'Lzma2Dec',
      ])
        'src/lzma/$name.c',
      for (final dir in ['common', 'compress', 'decompress'])
        for (final file in Directory.fromUri(
          root.resolve('src/zstd/$dir/'),
        ).listSync().whereType<File>())
          if (file.path.endsWith('.c'))
            file.uri.path.substring(root.path.length),
    ];
    await CBuilder.library(
      name: 'lilygobox_codecs',
      assetName: 'src/third_party/codec.g.dart',
      sources: sources,
      includes: ['src/lzma', 'src/zstd'],
      defines: {'Z7_ST': null, 'ZSTD_DISABLE_ASM': null},
    ).run(input: input, output: output);
  });
}
