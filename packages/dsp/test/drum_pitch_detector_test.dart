import 'dart:math';
import 'package:dsp/dsp.dart';
import 'package:test/test.dart';

/// Gera uma onda com fundamental F0 + primeiro sobretom F1 (modo 1,1)
List<double> gerarTomComSobretom({
  required double f0,
  required double f1,
  required double amplF1, // Amplitude relativa do sobretom (0-1)
  required int sampleRate,
  required int numSamples,
}) {
  final samples = List<double>.filled(numSamples, 0.0);
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    samples[i] = sin(2 * pi * f0 * t) + amplF1 * sin(2 * pi * f1 * t);
  }
  // Normaliza para evitar clipping
  final maxAbs = samples.map((s) => s.abs()).reduce(max);
  return samples.map((s) => s / maxAbs * 0.8).toList();
}

void main() {
  group('DrumPitchDetector - Análise RTF', () {
    const sampleRate = 22050;
    const windowSize = 4096;

    test('Detecta F0 corretamente (Tom a 160 Hz)', () {
      final buffer = gerarTomComSobretom(
        f0: 160.0, f1: 240.0, amplF1: 0.5,
        sampleRate: sampleRate, numSamples: windowSize,
      );
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Tom 1');
      
      expect(result.isSilent, isFalse);
      expect(result.f0, closeTo(160.0, 5.0)); // Tolerância ±5 Hz
    });

    test('Detecta F1 (modo 1,1) corretamente', () {
      final buffer = gerarTomComSobretom(
        f0: 160.0, f1: 240.0, amplF1: 0.5,
        sampleRate: sampleRate, numSamples: windowSize,
      );
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Tom 1');
      
      expect(result.f1, isNotNull);
      expect(result.f1!, closeTo(240.0, 10.0));
    });

    test('Calcula RTF correto (F1/F0 = 1.5)', () {
      final buffer = gerarTomComSobretom(
        f0: 160.0, f1: 240.0, amplF1: 0.5,
        sampleRate: sampleRate, numSamples: windowSize,
      );
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Tom 1');
      
      expect(result.rtf, isNotNull);
      expect(result.rtf!, closeTo(1.5, 0.1));
    });

    test('Ignora F1 quando amplitude é insuficiente (<30%)', () {
      final buffer = gerarTomComSobretom(
        f0: 160.0, f1: 240.0, amplF1: 0.1, // Só 10% de sobretom
        sampleRate: sampleRate, numSamples: windowSize,
      );
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Tom 1');
      
      expect(result.f1, isNull); // Não deve detectar F1
      expect(result.rtf, isNull);
    });

    test('Silêncio retorna isSilent=true', () {
      final buffer = List<double>.filled(windowSize, 0.0);
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Tom 1');
      
      expect(result.isSilent, isTrue);
      expect(result.f0, equals(0.0));
    });

    test('Bumbo usa janela 8192 (frequências graves)', () {
      final buffer = gerarTomComSobretom(
        f0: 60.0, f1: 90.0, amplF1: 0.6,
        sampleRate: sampleRate, numSamples: 8192,
      );
      final result = DrumPitchDetector.detect(buffer, sampleRate, drumType: 'Bumbo');
      
      expect(result.f0, closeTo(60.0, 3.0)); // Tolerância maior para graves
    });
  });
}