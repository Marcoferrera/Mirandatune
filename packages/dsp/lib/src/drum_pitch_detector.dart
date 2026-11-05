import 'dart:math';
import 'fft.dart';
import 'pitch_detector.dart';

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
  static int _janelaParaTambor(String drum) {
    if (drum == 'Bumbo' || drum == 'Surdo') return 8192;
    return 4096;
  }

  static Map<String, double> _faixaParaTambor(String drum) {
    const faixas = {
      'Bumbo': [40.0, 110.0],
      'Caixa': [140.0, 260.0],
      'Tom 1': [110.0, 220.0],
      'Tom 2': [90.0, 180.0],
      'Surdo': [55.0, 145.0],
    };
    final f = faixas[drum] ?? [40.0, 400.0];
    return {'min': f[0], 'max': f[1]};
  }

  static List<double> _aplicarFiltroPassaBaixa(List<double> audio, double sampleRate, double cutoff) {
    final rc = 1.0 / (2 * pi * cutoff);
    final dt = 1.0 / sampleRate;
    final alpha = dt / (rc + dt);
    
    List<double> filtrado = List.filled(audio.length, 0.0);
    if (audio.isEmpty) return filtrado;
    
    filtrado[0] = audio[0] * alpha;
    for (int i = 1; i < audio.length; i++) {
      filtrado[i] = filtrado[i - 1] + alpha * (audio[i] - filtrado[i - 1]);
    }
    return filtrado;
  }

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
  }) {
    int onsetIndex = 0;
    double maxRms = 0.0;
    for (int i = 0; i <= audioBuffer.length - 512; i += 256) {
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

    if (maxRms < 0.01) {
      return DrumPitchResult(f0: 0.0, isSilent: true);
    }

    final windowSize = _janelaParaTambor(drumType);
    int startIndex = onsetIndex + 1000;
    if (startIndex + windowSize > audioBuffer.length) {
      startIndex = max(0, audioBuffer.length - windowSize);
    }

    List<double> buffer = audioBuffer.sublist(startIndex, startIndex + windowSize);
    if (drumType == 'Caixa') {
      buffer = _aplicarFiltroPassaBaixa(buffer, sampleRate.toDouble(), 350.0);
    }

    List<Complex> complexBuffer = List.generate(windowSize, (i) {
      double hann = 0.5 * (1 - cos(2 * pi * i / (windowSize - 1)));
      return Complex(buffer[i] * hann, 0);
    });

    List<Complex> frequencyDomain = FFT.transform(complexBuffer);
    List<double> magnitudes = frequencyDomain
        .take(windowSize ~/ 2)
        .map((c) => c.magnitude)
        .toList();

    final binWidth = sampleRate / windowSize;
    final faixa = _faixaParaTambor(drumType);
    final minBin = (faixa['min']! / binWidth).ceil();
    final maxBin = (faixa['max']! / binWidth).floor();

    int f0Bin = _encontrarPico(magnitudes, max(1, minBin), maxBin);
    double f0 = f0Bin * binWidth;
    if (f0Bin > 0 && f0Bin < magnitudes.length - 1) {
      f0 = SpectralInterpolation.refine(magnitudes, f0Bin, binWidth);
    }

    final f1MinBin = (1.2 * f0 / binWidth).ceil();
    final f1MaxBin = (2.5 * f0 / binWidth).floor();
    double? f1;
    double? rtf;

    if (f1MinBin < magnitudes.length && f1MaxBin > f1MinBin) {
      int f1Bin = _encontrarPico(magnitudes, f1MinBin, min(f1MaxBin, magnitudes.length - 1));
      
      if (magnitudes[f1Bin] > 0.3 * magnitudes[f0Bin]) {
        f1 = f1Bin * binWidth;
        if (f1Bin > 0 && f1Bin < magnitudes.length - 1) {
          f1 = SpectralInterpolation.refine(magnitudes, f1Bin, binWidth);
        }
        rtf = f1 / f0;
      }
    }

    return DrumPitchResult(
      f0: f0,
      f1: f1,
      rtf: rtf,
      confidence: maxRms,
    );
  }
}