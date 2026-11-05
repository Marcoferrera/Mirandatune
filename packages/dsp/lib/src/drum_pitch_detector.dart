import 'dart:math';
import 'fft.dart';

class DrumPitchResult {
  final double f0;          
  final double? f1;         
  final double? rtf;        
  final double confidence;
  final bool isSilent;

  DrumPitchResult({
    required this.f0,
    this.f1,
    this.rtf,
    this.confidence = 1.0,
    this.isSilent = false,
  });
}

class DrumPitchDetector {
  static int _encontrarPico(List<double> magnitudes, int binInicio, int binFim) {
    int pico = binInicio;
    double maxMag = 0.0;
    for (int i = binInicio; i <= binFim && i < magnitudes.length; i++) {
      if (magnitudes[i] > maxMag) {
        maxMag = magnitudes[i];
        pico = i;
      }
    }
    return pico;
  }

  static DrumPitchResult detect(
    List<double> audioBuffer,
    int sampleRate, {
    required String drumType,
    double? customTargetHz,
  }) {
    // Garante que o tamanho seja potência de 2
    int windowSize = 1;
    while (windowSize * 2 <= audioBuffer.length) {
      windowSize *= 2;
    }
    
    if (windowSize < 2048) {
      return DrumPitchResult(f0: 0.0, isSilent: true);
    }

    // === ETAPA 1: Detecção de Onset (Encontrar a batida) ===
    int onsetIndex = 0;
    double maxRms = 0.0;
    for (int i = 0; i <= windowSize - 512; i += 256) {
      double sumSquares = 0;
      for (int j = 0; j < 512; j++) {
        sumSquares += audioBuffer[i + j] * audioBuffer[i + j];
      }
      final rms = sqrt(sumSquares / 512);
      if (rms > maxRms) {
        maxRms = rms;
        onsetIndex = i;
      }
    }

    if (maxRms < 0.005) {
      return DrumPitchResult(f0: 0.0, isSilent: true);
    }

    // === ETAPA 2: Fatiar exatamente a partir do Onset ===
    // Pega um pedaço do ataque, ignorando o silêncio antes ou o eco depois
    int sliceSize = 2048; // Tamanho ideal para análise de tambor
    int startIndex = onsetIndex;
    
    // Se o ataque foi muito no final do buffer, ajusta para pegar o final
    if (startIndex + sliceSize > audioBuffer.length) {
      startIndex = max(0, audioBuffer.length - sliceSize);
    }

    List<double> slicedBuffer = audioBuffer.sublist(startIndex, startIndex + sliceSize);
    
    // Ajusta windowSize para o tamanho fatiado
    windowSize = 2048;

    // === ETAPA 3: Aplicar Janela de Hann ===
    List<Complex> complexBuffer = List.generate(windowSize, (i) {
      double hann = 0.5 * (1 - cos(2 * pi * i / (windowSize - 1)));
      return Complex(slicedBuffer[i] * hann, 0);
    });

    // === ETAPA 4: FFT ===
    List<Complex> frequencyDomain = FFT.transform(complexBuffer);
    List<double> magnitudes = frequencyDomain
        .take(windowSize ~/ 2)
        .map((c) => c.magnitude)
        .toList();

    final binWidth = sampleRate / windowSize;

    // === ETAPA 5: TARGET FILTER ===
    double minFreq;
    double maxFreq;

    if (customTargetHz != null && customTargetHz > 0) {
      minFreq = customTargetHz * 0.85;
      maxFreq = customTargetHz * 1.15;
    } else {
      final faixas = {
        'Bumbo': [40.0, 110.0],
        'Caixa': [140.0, 260.0],
        'Tom 1': [110.0, 220.0],
        'Tom 2': [90.0, 180.0],
        'Surdo': [55.0, 145.0],
      };
      final f = faixas[drumType] ?? [40.0, 400.0];
      minFreq = f[0];
      maxFreq = f[1];
    }

    final minBin = (minFreq / binWidth).ceil();
    final maxBin = (maxFreq / binWidth).floor();

    // === ETAPA 6: Identificar F0 ===
    int f0Bin = _encontrarPico(magnitudes, max(1, minBin), maxBin);
    double f0 = f0Bin * binWidth;
    
    // Refinamento sub-bin
    if (f0Bin > 0 && f0Bin < magnitudes.length - 1) {
      double s0 = magnitudes[f0Bin - 1];
      double s1 = magnitudes[f0Bin];
      double s2 = magnitudes[f0Bin + 1];
      double denominator = 2 * (2 * s1 - s2 - s0);
      if (denominator != 0) {
        f0 = (f0Bin + (s2 - s0) / denominator) * binWidth;
      }
    }

    // Ignora leituras absurdamente baixas (ruído)
    if (f0 < minFreq || f0 > maxFreq) {
       return DrumPitchResult(f0: 0.0, isSilent: true);
    }

    return DrumPitchResult(
      f0: f0,
      confidence: maxRms,
    );
  }
}