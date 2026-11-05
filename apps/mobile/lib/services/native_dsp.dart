import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// 1. Assinatura C++ (O C++ atual só tem essa função)
typedef ProcessAudioC = Double Function(
    Pointer<Double> buffer, 
    Int32 length, 
    Int32 sampleRate, 
    Int32 drumType, 
    Double targetHz);

// 2. Assinatura Dart equivalente
typedef ProcessAudioDart = double Function(
    Pointer<Double> buffer, 
    int length, 
    int sampleRate, 
    int drumType, 
    double targetHz);

class NativeDsp {
  late final DynamicLibrary _lib;
  late final ProcessAudioDart _processAudio;

  NativeDsp() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libdsp_engine.so');
    } else {
      throw UnsupportedError('Apenas Android configurado por enquanto');
    }

    _processAudio = _lib
        .lookup<NativeFunction<ProcessAudioC>>('processAudioBuffer')
        .asFunction();
  }

  /// Envia o áudio, sample rate, tipo de tambor e alvo em Hz para o C++
  double processarAudio(
    List<double> audio, 
    int sampleRate, 
    int drumType, 
    double targetHz
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
}