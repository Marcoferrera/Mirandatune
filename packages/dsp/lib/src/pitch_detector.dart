import 'dart:math';

class PitchResult {
  final double frequency;
  final double confidence;
  final bool isSilent;

  PitchResult(this.frequency, this.confidence, {this.isSilent = false});
}

class PitchDetector {
  static PitchResult detect(
    List<double> audioBuffer, 
    int sampleRate, {
    double threshold = 0.15,
  }) {
    final int bufferSize = audioBuffer.length;
    final int halfBuffer = bufferSize ~/ 2;

    double sumSquares = 0;
    for (double val in audioBuffer) {
      sumSquares += val * val;
    }
    final double rms = sqrt(sumSquares / bufferSize);
    
    if (rms < 0.01) {
      return PitchResult(0.0, 0.0, isSilent: true);
    }

    final List<double> windowedBuffer = List.filled(bufferSize, 0.0);
    for (int i = 0; i < bufferSize; i++) {
      final double multiplier = 0.5 * (1 - cos(2 * pi * i / (bufferSize - 1)));
      windowedBuffer[i] = audioBuffer[i] * multiplier;
    }

    final List<double> yinBuffer = List.filled(halfBuffer, 0.0);
    for (int tau = 0; tau < halfBuffer; tau++) {
      for (int i = 0; i < halfBuffer; i++) {
        final double delta = windowedBuffer[i] - windowedBuffer[i + tau];
        yinBuffer[tau] += delta * delta;
      }
    }

    yinBuffer[0] = 1.0;
    double runningSum = 0.0;
    for (int tau = 1; tau < halfBuffer; tau++) {
      runningSum += yinBuffer[tau];
      if (runningSum == 0) runningSum = 1e-10;
      yinBuffer[tau] *= tau / runningSum;
    }

    int tauEstimate = -1;
    for (int tau = 2; tau < halfBuffer; tau++) {
      if (yinBuffer[tau] < threshold) {
        while (tau + 1 < halfBuffer && yinBuffer[tau + 1] < yinBuffer[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }

    if (tauEstimate == -1) {
      return PitchResult(0.0, 0.0, isSilent: true);
    }

    double betterTau;
    final int x0 = (tauEstimate < 1) ? tauEstimate : tauEstimate - 1;
    final int x2 = (tauEstimate + 1 < halfBuffer) ? tauEstimate + 1 : tauEstimate;
    
    if (x0 == tauEstimate) {
      betterTau = (yinBuffer[tauEstimate] <= yinBuffer[x2]) ? tauEstimate.toDouble() : x2.toDouble();
    } else if (x2 == tauEstimate) {
      betterTau = (yinBuffer[tauEstimate] <= yinBuffer[x0]) ? tauEstimate.toDouble() : x0.toDouble();
    } else {
      final double s0 = yinBuffer[x0];
      final double s1 = yinBuffer[tauEstimate];
      final double s2 = yinBuffer[x2];
      final double denominator = 2 * (2 * s1 - s2 - s0);
      
      if (denominator == 0) {
        betterTau = tauEstimate.toDouble();
      } else {
        betterTau = tauEstimate + (s2 - s0) / denominator;
      }
    }

    if (betterTau <= 0) return PitchResult(0.0, 0.0, isSilent: true);
    
    final double frequency = sampleRate / betterTau;
    final double confidence = 1.0 - yinBuffer[tauEstimate];

    return PitchResult(frequency, confidence);
  }
}