import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef ProcessAudioC = Double Function(
    Pointer<Double> buffer, Int32 length, Int32 sampleRate, Int32 drumType, Double targetHz);
typedef ProcessAudioDart = double Function(
    Pointer<Double> buffer, int length, int sampleRate, int drumType, double targetHz);

// Nova assinatura para o Debug
typedef ProcessAudioDebugC = Void Function(
    Pointer<Double> buffer, Int32 length, Int32 sampleRate, Int32 drumType, Double targetHz, Pointer<Double> out);
typedef ProcessAudioDebugDart = void Function(
    Pointer<Double> buffer, int length, int sampleRate, int drumType, double targetHz, Pointer<Double> out);

class NativeDsp {
  late final DynamicLibrary _lib;
  late final ProcessAudioDart _processAudio;
  late final ProcessAudioDebugDart _processAudioDebug;

  NativeDsp() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libdsp_engine.so');
    } else {
      throw UnsupportedError('Apenas Android configurado');
    }

    _processAudio = _lib.lookup<NativeFunction<ProcessAudioC>>('processAudioBuffer').asFunction();
    _processAudioDebug = _lib.lookup<NativeFunction<ProcessAudioDebugC>>('processAudioDebug').asFunction();
  }

  double processarAudio(List<double> audio, int sampleRate, int drumType, double targetHz) {
    final ptr = calloc<Double>(audio.length);
    try {
      for (int i = 0; i < audio.length; i++) ptr[i] = audio[i];
      return _processAudio(ptr, audio.length, sampleRate, drumType, targetHz);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Retorna lista com 8 valores: [f0Filt, f0Raw, rms, onset, start, ratio, secondPeak, length]
  List<double> processarAudioDebug(List<double> audio, int sampleRate, int drumType, double targetHz) {
    final ptr = calloc<Double>(audio.length);
    final out = calloc<Double>(8);
    try {
      for (int i = 0; i < audio.length; i++) ptr[i] = audio[i];
      _processAudioDebug(ptr, audio.length, sampleRate, drumType, targetHz, out);
      return List<double>.generate(8, (i) => out[i]);
    } finally {
      calloc.free(ptr);
      calloc.free(out);
    }
  }
}