@DefaultAsset('package:lilygobox_codecs/src/third_party/codec.g.dart')
library;

import 'dart:ffi';

typedef CodecProgressNative = Void Function(Uint64, Uint64);

@Native<Pointer<Void> Function()>()
external Pointer<Void> lb_cancel_create();
@Native<Void Function(Pointer<Void>)>()
external void lb_cancel_set(Pointer<Void> state);
@Native<Int Function(Pointer<Void>)>()
external int lb_cancel_get(Pointer<Void> state);
@Native<Void Function(Pointer<Void>)>()
external void lb_cancel_free(Pointer<Void> state);
@Native<
  Int Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Pointer<Size>,
    Pointer<Uint8>,
    Pointer<NativeFunction<CodecProgressNative>>,
    Pointer<Void>,
  )
>()
external int lb_lzma2_encode_progress(
  Pointer<Uint8> input,
  int size,
  Pointer<Uint8> output,
  Pointer<Size> outputSize,
  Pointer<Uint8> property,
  Pointer<NativeFunction<CodecProgressNative>> progress,
  Pointer<Void> cancel,
);
@Native<
  Int Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Pointer<Size>,
    Uint8,
    Pointer<NativeFunction<CodecProgressNative>>,
    Pointer<Void>,
  )
>()
external int lb_lzma2_decode_progress(
  Pointer<Uint8> input,
  int size,
  Pointer<Uint8> output,
  Pointer<Size> outputSize,
  int property,
  Pointer<NativeFunction<CodecProgressNative>> progress,
  Pointer<Void> cancel,
);
