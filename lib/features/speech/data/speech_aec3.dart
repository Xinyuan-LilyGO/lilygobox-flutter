/*
 * @Description: 通过 Dart FFI 加载本机 Google WebRTC AEC3 动态库并暴露实时回声消除接口。
 */

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef _Aec3CreateNative =
    Pointer<Void> Function(Int32 sampleRateHz, Int32 numChannels);
typedef _Aec3DestroyNative = Void Function(Pointer<Void> handle);
typedef _Aec3ProcessRenderNative =
    Void Function(Pointer<Void> handle, Pointer<Int16> pcm, Int32 numSamples);
typedef _Aec3ProcessCaptureNative =
    Void Function(
      Pointer<Void> handle,
      Pointer<Int16> micPcm,
      Pointer<Int16> outPcm,
      Int32 numSamples,
      Int32 delayMs,
    );
typedef _Aec3LiveStartNative = Pointer<Void> Function(Int32 sampleRateHz);
typedef _Aec3LiveReadNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Int16> outPcm,
      Int32 maxSamples,
    );
typedef _Aec3LiveStopNative = Void Function(Pointer<Void> handle);
typedef _Aec3AllocI16Native = Pointer<Int16> Function(Int32 count);
typedef _Aec3FreeNative = Void Function(Pointer<Void> ptr);

typedef Aec3CreateFn = Pointer<Void> Function(int sampleRateHz, int numChannels);
typedef Aec3DestroyFn = void Function(Pointer<Void> handle);
typedef Aec3ProcessRenderFn =
    void Function(Pointer<Void> handle, Pointer<Int16> pcm, int numSamples);
typedef Aec3ProcessCaptureFn =
    void Function(
      Pointer<Void> handle,
      Pointer<Int16> micPcm,
      Pointer<Int16> outPcm,
      int numSamples,
      int delayMs,
    );
typedef Aec3LiveStartFn = Pointer<Void> Function(int sampleRateHz);
typedef Aec3LiveReadFn =
    int Function(Pointer<Void> handle, Pointer<Int16> outPcm, int maxSamples);
typedef Aec3LiveStopFn = void Function(Pointer<Void> handle);
typedef Aec3AllocI16Fn = Pointer<Int16> Function(int count);
typedef Aec3FreeFn = void Function(Pointer<Void> ptr);

class WebRtcAec3Library {
  WebRtcAec3Library._(DynamicLibrary lib)
    : create = lib.lookupFunction<_Aec3CreateNative, Aec3CreateFn>(
        'aec3_create',
      ),
      destroy = lib.lookupFunction<_Aec3DestroyNative, Aec3DestroyFn>(
        'aec3_destroy',
      ),
      processRender = lib
          .lookupFunction<_Aec3ProcessRenderNative, Aec3ProcessRenderFn>(
            'aec3_process_render',
          ),
      processCapture = lib
          .lookupFunction<_Aec3ProcessCaptureNative, Aec3ProcessCaptureFn>(
            'aec3_process_capture',
          ),
      liveStart = lib.lookupFunction<_Aec3LiveStartNative, Aec3LiveStartFn>(
        'aec3_live_start',
      ),
      liveRead = lib.lookupFunction<_Aec3LiveReadNative, Aec3LiveReadFn>(
        'aec3_live_read',
      ),
      liveStop = lib.lookupFunction<_Aec3LiveStopNative, Aec3LiveStopFn>(
        'aec3_live_stop',
      ),
      allocI16 = lib.lookupFunction<_Aec3AllocI16Native, Aec3AllocI16Fn>(
        'aec3_alloc_i16',
      ),
      freePtr = lib.lookupFunction<_Aec3FreeNative, Aec3FreeFn>('aec3_free');

  final Aec3CreateFn create;
  final Aec3DestroyFn destroy;
  final Aec3ProcessRenderFn processRender;
  final Aec3ProcessCaptureFn processCapture;
  final Aec3LiveStartFn liveStart;
  final Aec3LiveReadFn liveRead;
  final Aec3LiveStopFn liveStop;
  final Aec3AllocI16Fn allocI16;
  final Aec3FreeFn freePtr;

  static WebRtcAec3Library? _cached;
  static bool _attempted = false;

  static WebRtcAec3Library? tryLoad({String? explicitPath}) {
    if (explicitPath != null) {
      try {
        return WebRtcAec3Library._(DynamicLibrary.open(explicitPath));
      } catch (_) {
        return null;
      }
    }
    if (_attempted) return _cached;
    _attempted = true;
    if (!Platform.isWindows) return null;
    try {
      _cached = WebRtcAec3Library._(DynamicLibrary.open('lilygo_aec3.dll'));
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }
}

class WebRtcAec3LiveCapture {
  WebRtcAec3LiveCapture._(this._lib, this._session, this._buffer, this._capacity);

  static const _bufferSamples = 1600;

  final WebRtcAec3Library _lib;
  final Pointer<Void> _session;
  final Pointer<Int16> _buffer;
  final int _capacity;
  bool _closed = false;

  static WebRtcAec3LiveCapture? start(int sampleRateHz) {
    final lib = WebRtcAec3Library.tryLoad();
    if (lib == null) return null;
    final session = lib.liveStart(sampleRateHz);
    if (session == nullptr) return null;
    final buffer = lib.allocI16(_bufferSamples);
    if (buffer == nullptr) {
      lib.liveStop(session);
      return null;
    }
    return WebRtcAec3LiveCapture._(lib, session, buffer, _bufferSamples);
  }

  /// 读取当前可用的回声消除后 PCM16 字节；流出错时返回 null。
  Uint8List? readAvailablePcm() {
    if (_closed) return null;
    final samples = _lib.liveRead(_session, _buffer, _capacity);
    if (samples < 0) return null;
    if (samples == 0) return Uint8List(0);
    final view = _buffer.cast<Uint8>().asTypedList(samples * 2);
    return Uint8List.fromList(view);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _lib.liveStop(_session);
    _lib.freePtr(_buffer.cast<Void>());
  }
}
