import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/clipboard/image_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lilygobox/image_clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Uint8List bitmap() {
    final bytes = ByteData(58);
    bytes.setUint16(0, 0x4d42, Endian.little);
    bytes.setUint32(2, 58, Endian.little);
    bytes.setUint32(10, 54, Endian.little);
    bytes.setUint32(14, 40, Endian.little);
    bytes.setInt32(18, 1, Endian.little);
    bytes.setInt32(22, -1, Endian.little);
    bytes.setUint16(26, 1, Endian.little);
    bytes.setUint16(28, 32, Endian.little);
    bytes.setUint32(34, 4, Endian.little);
    bytes.setUint8(56, 255); // BGRA: opaque red.
    bytes.setUint8(57, 255);
    return bytes.buffer.asUint8List();
  }

  test('Windows DIB bytes are decoded into a PNG attachment', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readImage');
      return bitmap();
    });
    final bytes = await ImageClipboard.readPng();
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1);
    expect(frame.image.height, 1);
    frame.image.dispose();
    codec.dispose();
  });

  test(
    'Windows writes both PNG and decoded pixels to the native bridge',
    () async {
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'writeImage');
        sent = call.arguments as Map<Object?, Object?>;
        return null;
      });
      await ImageClipboard.writeImage(bitmap());
      expect(sent!['width'], 1);
      expect(sent!['height'], 1);
      expect(sent!['rgba'], Uint8List.fromList([255, 0, 0, 255]));
      expect((sent!['png'] as Uint8List).take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    },
  );

  test('a busy clipboard retries before delivering the image', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (++attempts < 3) throw PlatformException(code: 'clipboard_busy');
      return bitmap();
    });
    expect(await ImageClipboard.readPng(), isNotNull);
    expect(attempts, 3);
  });

  test(
    'native clipboard errors propagate instead of returning fake success',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'clipboard_write_failed');
      });
      await expectLater(
        ImageClipboard.writeImage(bitmap()),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
