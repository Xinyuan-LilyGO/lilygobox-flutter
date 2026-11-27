import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/speech/data/speech_aec3.dart';

void main() {
  test('WebRTC AEC3 cancels simulated speaker echo on 16kHz PCM frames', () {
    final dll = File('build/aec3_check/Release/lilygo_aec3.dll');
    if (!Platform.isWindows || !dll.existsSync()) {
      markTestSkipped('lilygo_aec3.dll is not built in this environment');
      return;
    }
    final lib = WebRtcAec3Library.tryLoad(explicitPath: dll.absolute.path);
    expect(lib, isNotNull);

    const sampleRate = 16000;
    const frameSamples = 160;
    final aec = lib!.create(sampleRate, 1);
    expect(aec, isNot(equals(nullptr)));

    final refPtr = lib.allocI16(frameSamples);
    final micPtr = lib.allocI16(frameSamples);
    final outPtr = lib.allocI16(frameSamples);
    try {
      final ref = refPtr.asTypedList(frameSamples);
      final mic = micPtr.asTypedList(frameSamples);
      final out = outPtr.asTypedList(frameSamples);

      final rng = math.Random(42);
      var rawMicEnergy = 0.0;
      var convergedOutEnergy = 0.0;

      // Feed 250 frames (2.5 seconds) of broadband speech-like signal + echo.
      for (var frame = 0; frame < 250; frame++) {
        final envelope = (frame % 40) < 30 ? 1.0 : 0.15;
        for (var i = 0; i < frameSamples; i++) {
          final t = (frame * frameSamples + i) / sampleRate;
          final broadband =
              (rng.nextDouble() * 2 - 1) * 5000 +
              math.sin(2 * math.pi * 320 * t) * 2500 +
              math.sin(2 * math.pi * 680 * t) * 1800;
          final signal = (broadband * envelope).round();
          ref[i] = signal;
          // Simulated room echo at ~50% amplitude.
          mic[i] = (signal * 0.5).round();
        }
        lib.processRender(aec, refPtr, frameSamples);
        lib.processCapture(aec, micPtr, outPtr, frameSamples, 0);

        if (frame >= 180) {
          for (var i = 0; i < frameSamples; i++) {
            rawMicEnergy += mic[i] * mic[i];
            convergedOutEnergy += out[i] * out[i];
          }
        }
      }

      // After convergence, AEC3 should suppress the simulated broadband echo by >10 dB.
      expect(convergedOutEnergy, lessThan(rawMicEnergy * 0.1));
    } finally {
      lib.freePtr(refPtr.cast<Void>());
      lib.freePtr(micPtr.cast<Void>());
      lib.freePtr(outPtr.cast<Void>());
      lib.destroy(aec);
    }
  });
}
