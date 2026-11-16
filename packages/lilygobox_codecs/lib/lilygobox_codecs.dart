import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/third_party/codec.g.dart' as native;
import 'src/codec_progress_bindings.dart' as progress;

abstract final class LilygoBoxCodecs {
  static Uint8List lzma2(
    Uint8List bytes, {
    void Function(int input, int output)? onProgress,
    CodecCancellation? cancellation,
  }) {
    final input = calloc<Uint8>(bytes.length);
    final capacity = bytes.length + bytes.length ~/ 8 + 65536;
    final output = calloc<Uint8>(capacity);
    final length = calloc<Size>();
    final property = calloc<Uint8>();
    final callback = onProgress == null
        ? null
        : NativeCallable<progress.CodecProgressNative>.isolateLocal(onProgress);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      length.value = capacity;
      final code = progress.lb_lzma2_encode_progress(
        input,
        bytes.length,
        output,
        length,
        property,
        callback?.nativeFunction ?? nullptr,
        cancellation?._pointer ?? nullptr,
      );
      if (cancellation?.isCancelled ?? false) throw const CodecCancelled();
      if (code != 0) throw StateError('LZMA2 encode error: $code');
      final result = Uint8List(length.value + 9);
      final header = ByteData.sublistView(result);
      header.setUint64(0, bytes.length, Endian.little);
      result[8] = property.value;
      result.setRange(9, result.length, output.asTypedList(length.value));
      return result;
    } finally {
      calloc.free(input);
      calloc.free(output);
      calloc.free(length);
      calloc.free(property);
      callback?.close();
    }
  }

  static Uint8List unlzma2(
    Uint8List bytes, {
    void Function(int input, int output)? onProgress,
    CodecCancellation? cancellation,
  }) {
    if (bytes.length < 9 || bytes[8] > 28)
      throw const FormatException('Invalid LZMA2 frame');
    final size = ByteData.sublistView(bytes).getUint64(0, Endian.little);
    if (size > 512 * 1024 * 1024)
      throw const FormatException('Package exceeds import memory budget');
    final input = calloc<Uint8>(bytes.length - 9);
    final output = calloc<Uint8>(size);
    final length = calloc<Size>();
    final callback = onProgress == null
        ? null
        : NativeCallable<progress.CodecProgressNative>.isolateLocal(onProgress);
    try {
      input.asTypedList(bytes.length - 9).setAll(0, bytes.sublist(9));
      length.value = size;
      final code = progress.lb_lzma2_decode_progress(
        input,
        bytes.length - 9,
        output,
        length,
        bytes[8],
        callback?.nativeFunction ?? nullptr,
        cancellation?._pointer ?? nullptr,
      );
      if (cancellation?.isCancelled ?? false) throw const CodecCancelled();
      if (code != 0 || length.value != size)
        throw const FormatException('Corrupt LZMA2 frame');
      return Uint8List.fromList(output.asTypedList(size));
    } finally {
      calloc.free(input);
      calloc.free(output);
      calloc.free(length);
      callback?.close();
    }
  }

  static Uint8List zstd(Uint8List bytes) {
    final capacity = native.lb_zstd_bound(bytes.length);
    final input = calloc<Uint8>(bytes.length);
    final output = calloc<Uint8>(capacity);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final size = native.lb_zstd_encode(
        input,
        bytes.length,
        output,
        capacity,
        3,
      );
      if (native.lb_zstd_error(size) != 0)
        throw StateError('Zstd encode failed');
      final result = Uint8List(size + 8);
      ByteData.sublistView(result).setUint64(0, bytes.length, Endian.little);
      result.setRange(8, result.length, output.asTypedList(size));
      return result;
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  static Uint8List unzstd(Uint8List bytes) {
    if (bytes.length < 8) throw const FormatException('Invalid Zstd frame');
    final size = ByteData.sublistView(bytes).getUint64(0, Endian.little);
    if (size > 512 * 1024 * 1024)
      throw const FormatException('Object exceeds memory budget');
    final input = calloc<Uint8>(bytes.length - 8);
    final output = calloc<Uint8>(size);
    try {
      input.asTypedList(bytes.length - 8).setAll(0, bytes.sublist(8));
      final decoded = native.lb_zstd_decode(
        input,
        bytes.length - 8,
        output,
        size,
      );
      if (native.lb_zstd_error(decoded) != 0 || decoded != size)
        throw const FormatException('Corrupt Zstd object');
      return Uint8List.fromList(output.asTypedList(size));
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }
}

class CodecCancelled implements Exception {
  const CodecCancelled();
}

/// Shared atomic native cancellation flag; the creator disposes after workers stop.
class CodecCancellation {
  CodecCancellation() : _pointer = progress.lb_cancel_create() {
    if (_pointer == nullptr)
      throw StateError('Unable to allocate cancellation state');
  }
  CodecCancellation.borrowed(int address)
    : _pointer = Pointer<Void>.fromAddress(address);
  final Pointer<Void> _pointer;
  int get address => _pointer.address;
  bool get isCancelled => progress.lb_cancel_get(_pointer) != 0;
  void cancel() => progress.lb_cancel_set(_pointer);
  void dispose() => progress.lb_cancel_free(_pointer);
}
