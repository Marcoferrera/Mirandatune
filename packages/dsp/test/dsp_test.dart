import 'package:dsp/dsp.dart';
import 'package:test/test.dart';
import 'dart:math';

List<double> generateSineWave(double frequency, int sampleRate, double durationSeconds) {
  final int numSamples = (sampleRate * durationSeconds).toInt();
  final List<double> samples = [];
  for (int i = 0; i < numSamples; i++) {
    final double t = i / sampleRate;
    samples.add(sin(2 * pi * frequency * t));
  }
  return samples;
}

void main() {
  group('Fase 1 - Testes do Motor DSP', () {
    const int sampleRate = 22050;
    const int windowSize = 2048;

    test('Deve detectar A4 (440 Hz) com erro aceitável', () {
      final buffer = generateSineWave(440.0, sampleRate, windowSize / sampleRate);
      final result = PitchDetector.detect(buffer, sampleRate);

      expect(result.isSilent, isFalse);
      expect(result.frequency, closeTo(440.0, 0.5));
      
      final note = NoteConverter.frequencyToNote(result.frequency);
      expect(note.note, equals('A'));
      expect(note.octave, equals(4));
      expect(note.cents.abs(), lessThan(3.0));
    });

    test('Deve detectar E2 (82.4 Hz) com erro aceitável', () {
      final buffer = generateSineWave(82.4, sampleRate, windowSize / sampleRate);
      final result = PitchDetector.detect(buffer, sampleRate);

      expect(result.isSilent, isFalse);
      expect(result.frequency, closeTo(82.4, 0.5));
      
      final note = NoteConverter.frequencyToNote(result.frequency);
      expect(note.note, equals('E'));
      expect(note.octave, equals(2));
      expect(note.cents.abs(), lessThan(3.0));
    });

    test('Deve detectar silêncio quando o buffer é apenas zeros', () {
      final buffer = List<double>.filled(windowSize, 0.0);
      final result = PitchDetector.detect(buffer, sampleRate);

      expect(result.isSilent, isTrue);
      expect(result.frequency, equals(0.0));
    });

    // Teste de Performance pedido pelo Qwen
    test('Performance: Processar buffer de 2048 amostras em menos de 50ms', () {
      final buffer = generateSineWave(440.0, sampleRate, windowSize / sampleRate);
      
      // Inicia o cronômetro
      final stopwatch = Stopwatch()..start();
      
      // Processa 100 vezes para tirar uma média (evita cache do processador)
      for (int i = 0; i < 100; i++) {
        PitchDetector.detect(buffer, sampleRate);
      }
      
      stopwatch.stop();
      
      final double averageMs = stopwatch.elapsedMilliseconds / 100;
      print('Tempo médio de processamento: ${averageMs.toStringAsFixed(2)}ms');
      
      // Verifica se é menor que os 50ms exigidos
      expect(averageMs, lessThan(50.0));
    });
  });
}