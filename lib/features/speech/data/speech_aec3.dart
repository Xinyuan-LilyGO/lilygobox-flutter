/*
 * @Description: 通过 Dart FFI 加载本机 Google WebRTC AEC3 动态库并暴露实时回声消除接口。
 */

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../domain/speech_model.dart';

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
typedef _Aec3LiveStartDevicesNative =
    Pointer<Void> Function(
      Int32 sampleRateHz,
      Pointer<Uint8> captureDeviceId,
      Pointer<Uint8> playbackDeviceId,
    );
typedef _Aec3LiveReadNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Int16> outPcm,
      Int32 maxSamples,
    );
typedef _Aec3LiveStopNative = Void Function(Pointer<Void> handle);
typedef _Aec3ListAudioDevicesNative =
    Int32 Function(Int32 isCapture, Pointer<Uint8> outJson, Int32 maxBytes);
typedef _Aec3PlayStartNative =
    Pointer<Void> Function(
      Pointer<Uint8> playbackDeviceId,
      Int32 sampleRateHz,
      Int32 channels,
    );
typedef _Aec3PlayWriteNative =
    Int32 Function(Pointer<Void> handle, Pointer<Int16> pcm, Int32 numSamples);
typedef _Aec3PlayFinishNative = Void Function(Pointer<Void> handle);
typedef _Aec3PlayIsFinishedNative = Int32 Function(Pointer<Void> handle);
typedef _Aec3PlayStopNative = Void Function(Pointer<Void> handle);
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
typedef Aec3LiveStartDevicesFn =
    Pointer<Void> Function(
      int sampleRateHz,
      Pointer<Uint8> captureDeviceId,
      Pointer<Uint8> playbackDeviceId,
    );
typedef Aec3LiveReadFn =
    int Function(Pointer<Void> handle, Pointer<Int16> outPcm, int maxSamples);
typedef Aec3LiveStopFn = void Function(Pointer<Void> handle);
typedef Aec3ListAudioDevicesFn =
    int Function(int isCapture, Pointer<Uint8> outJson, int maxBytes);
typedef Aec3PlayStartFn =
    Pointer<Void> Function(
      Pointer<Uint8> playbackDeviceId,
      int sampleRateHz,
      int channels,
    );
typedef Aec3PlayWriteFn =
    int Function(Pointer<Void> handle, Pointer<Int16> pcm, int numSamples);
typedef Aec3PlayFinishFn = void Function(Pointer<Void> handle);
typedef Aec3PlayIsFinishedFn = int Function(Pointer<Void> handle);
typedef Aec3PlayStopFn = void Function(Pointer<Void> handle);
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
      liveStartDevices = _tryLookup(
        () => lib
            .lookupFunction<_Aec3LiveStartDevicesNative, Aec3LiveStartDevicesFn>(
              'aec3_live_start_devices',
            ),
      ),
      liveRead = lib.lookupFunction<_Aec3LiveReadNative, Aec3LiveReadFn>(
        'aec3_live_read',
      ),
      liveStop = lib.lookupFunction<_Aec3LiveStopNative, Aec3LiveStopFn>(
        'aec3_live_stop',
      ),
      listAudioDevicesRaw = _tryLookup(
        () => lib
            .lookupFunction<_Aec3ListAudioDevicesNative, Aec3ListAudioDevicesFn>(
              'aec3_list_audio_devices',
            ),
      ),
      playStart = _tryLookup(
        () => lib.lookupFunction<_Aec3PlayStartNative, Aec3PlayStartFn>(
          'aec3_play_start',
        ),
      ),
      playWrite = _tryLookup(
        () => lib.lookupFunction<_Aec3PlayWriteNative, Aec3PlayWriteFn>(
          'aec3_play_write',
        ),
      ),
      playFinish = _tryLookup(
        () => lib.lookupFunction<_Aec3PlayFinishNative, Aec3PlayFinishFn>(
          'aec3_play_finish',
        ),
      ),
      playIsFinished = _tryLookup(
        () => lib
            .lookupFunction<_Aec3PlayIsFinishedNative, Aec3PlayIsFinishedFn>(
              'aec3_play_is_finished',
            ),
      ),
      playStop = _tryLookup(
        () => lib.lookupFunction<_Aec3PlayStopNative, Aec3PlayStopFn>(
          'aec3_play_stop',
        ),
      ),
      allocI16 = lib.lookupFunction<_Aec3AllocI16Native, Aec3AllocI16Fn>(
        'aec3_alloc_i16',
      ),
      freePtr = lib.lookupFunction<_Aec3FreeNative, Aec3FreeFn>('aec3_free');

  static F? _tryLookup<F>(F Function() lookup) {
    try {
      return lookup();
    } catch (_) {
      return null;
    }
  }

  final Aec3CreateFn create;
  final Aec3DestroyFn destroy;
  final Aec3ProcessRenderFn processRender;
  final Aec3ProcessCaptureFn processCapture;
  final Aec3LiveStartFn liveStart;
  final Aec3LiveStartDevicesFn? liveStartDevices;
  final Aec3LiveReadFn liveRead;
  final Aec3LiveStopFn liveStop;
  final Aec3ListAudioDevicesFn? listAudioDevicesRaw;
  final Aec3PlayStartFn? playStart;
  final Aec3PlayWriteFn? playWrite;
  final Aec3PlayFinishFn? playFinish;
  final Aec3PlayIsFinishedFn? playIsFinished;
  final Aec3PlayStopFn? playStop;
  final Aec3AllocI16Fn allocI16;
  final Aec3FreeFn freePtr;

  Pointer<Uint8> _allocUtf8(String value) {
    final encoded = utf8.encode(value);
    final i16Count = (encoded.length + 2) ~/ 2;
    final ptr = allocI16(i16Count).cast<Uint8>();
    if (ptr == nullptr) return nullptr;
    final view = ptr.asTypedList(encoded.length + 1);
    view.setRange(0, encoded.length, encoded);
    view[encoded.length] = 0;
    return ptr;
  }

  static List<SpeechAudioDevice> listAudioDevices({required bool isCapture}) {
    final lib = tryLoad();
    final fn = lib?.listAudioDevicesRaw;
    if (lib == null || fn == null) return const [];
    var capacity = 16384;
    for (var attempt = 0; attempt < 2; attempt++) {
      final ptr = lib.allocI16((capacity + 1) ~/ 2).cast<Uint8>();
      if (ptr == nullptr) return const [];
      try {
        final written = fn(isCapture ? 1 : 0, ptr, capacity);
        if (written < -1) {
          capacity = (-written) + 256;
          continue;
        }
        if (written <= 0) return const [];
        final jsonText = utf8.decode(ptr.asTypedList(written));
        final decoded = jsonDecode(jsonText) as List;
        return [
          for (final item in decoded.cast<Map>())
            if (item case {
              'id': final String id,
              'name': final String name,
              'isDefault': final bool isDefault,
            })
              (id: id, name: name, isDefault: isDefault),
        ];
      } catch (_) {
        return const [];
      } finally {
        lib.freePtr(ptr.cast<Void>());
      }
    }
    return const [];
  }

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

  static WebRtcAec3LiveCapture? start(
    int sampleRateHz, {
    String? captureDeviceId,
    String? playbackDeviceId,
  }) {
    final lib = WebRtcAec3Library.tryLoad();
    if (lib == null) return null;
    final Pointer<Void> session;
    final startDevices = lib.liveStartDevices;
    if (startDevices != null &&
        ((captureDeviceId != null && captureDeviceId.isNotEmpty) ||
            (playbackDeviceId != null && playbackDeviceId.isNotEmpty))) {
      final capPtr = captureDeviceId == null || captureDeviceId.isEmpty
          ? nullptr.cast<Uint8>()
          : lib._allocUtf8(captureDeviceId);
      final playPtr = playbackDeviceId == null || playbackDeviceId.isEmpty
          ? nullptr.cast<Uint8>()
          : lib._allocUtf8(playbackDeviceId);
      try {
        session = startDevices(sampleRateHz, capPtr, playPtr);
      } finally {
        if (capPtr != nullptr) lib.freePtr(capPtr.cast<Void>());
        if (playPtr != nullptr) lib.freePtr(playPtr.cast<Void>());
      }
    } else {
      session = lib.liveStart(sampleRateHz);
    }
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

class WebRtcAec3Playback {
  WebRtcAec3Playback._(this._lib, this._session);

  final WebRtcAec3Library _lib;
  final Pointer<Void> _session;
  bool _closed = false;

  static WebRtcAec3Playback? start({
    String? playbackDeviceId,
    required int sampleRateHz,
    required int channels,
  }) {
    final lib = WebRtcAec3Library.tryLoad();
    final startFn = lib?.playStart;
    if (lib == null ||
        startFn == null ||
        lib.playWrite == null ||
        lib.playFinish == null ||
        lib.playIsFinished == null ||
        lib.playStop == null) {
      return null;
    }
    final devPtr = playbackDeviceId == null || playbackDeviceId.isEmpty
        ? nullptr.cast<Uint8>()
        : lib._allocUtf8(playbackDeviceId);
    final Pointer<Void> session;
    try {
      session = startFn(devPtr, sampleRateHz, channels);
    } finally {
      if (devPtr != nullptr) lib.freePtr(devPtr.cast<Void>());
    }
    if (session == nullptr) return null;
    return WebRtcAec3Playback._(lib, session);
  }

  void writePcm16Bytes(Uint8List pcmBytes) {
    if (_closed || pcmBytes.length < 2) return;
    final samples = pcmBytes.length ~/ 2;
    final ptr = _lib.allocI16(samples);
    if (ptr == nullptr) return;
    try {
      ptr.cast<Uint8>().asTypedList(samples * 2).setRange(
        0,
        samples * 2,
        pcmBytes,
      );
      _lib.playWrite!(_session, ptr, samples);
    } finally {
      _lib.freePtr(ptr.cast<Void>());
    }
  }

  void finish() {
    if (!_closed) _lib.playFinish!(_session);
  }

  bool get isFinished => _closed || _lib.playIsFinished!(_session) != 0;

  void stop() {
    if (_closed) return;
    _closed = true;
    _lib.playStop!(_session);
  }
}
