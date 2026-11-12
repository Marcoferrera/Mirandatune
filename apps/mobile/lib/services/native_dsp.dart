import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Bateria
typedef ProcessAudioC = Double Function(
    Pointer<Double> buffer,
    Int32 length,
    Int32 sampleRate,
    Int32 drumType,
    Double targetHz);

typedef ProcessAudioDart = double Function(
    Pointer<Double> buffer,
    int length,
    int sampleRate,
    int drumType,
    double targetHz);

// Cordas (YIN em C++)
typedef ProcessStringC = Double Function(
    Pointer<Double> buffer,
    Int32 length,
    Int32 sampleRate);

typedef ProcessStringDart = double Function(
    Pointer<Double> buffer,
    int length,
    int sampleRate);

class NativeDsp {
  late final DynamicLibrary _lib;
  late final ProcessAudioDart _processAudio;
  late final ProcessStringDart _processString;

  NativeDsp() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libdsp_engine.so');
    } else {
      throw UnsupportedError('Apenas Android configurado por enquanto');
    }

    _processAudio = _lib
        .lookup<NativeFunction<ProcessAudioC>>('processAudioBuffer')
        .asFunction();
    _processString = _lib
        .lookup<NativeFunction<ProcessStringC>>('processStringBuffer')
        .asFunction();
  }

  /// Bateria
  double processarAudio(
    List<double> audio,
    int sampleRate,
    int drumType,
    double targetHz,
  ) {
    final Pointer<Double> bufferPtr = calloc<Double>(audio.length);
    try {
      for (int i = 0; i < audio.length; i++) {
        bufferPtr[i] = audio[i];
      }
      return _processAudio(bufferPtr, audio.length, sampleRate, drumType, targetHz);
    } finally {
      calloc.free(bufferPtr);
    }
  }

  /// Cordas (YIN). Retorna 0.0 se silêncio ou sem pitch.
  double processarString(List<double> audio, int sampleRate) {
    final Pointer<Double> bufferPtr = calloc<Double>(audio.length);
    try {
      for (int i = 0; i < audio.length; i++) {
        bufferPtr[i] = audio[i];
      }
      return _processString(bufferPtr, audio.length, sampleRate);
    } finally {
      calloc.free(bufferPtr);
    }
  }
}