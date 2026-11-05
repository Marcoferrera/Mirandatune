import 'dart:math';

class FFT {
  // Executa a Transformada Rápida de Fourier (Radix-2 Cooley-Tukey)
  static List<Complex> transform(List<Complex> input) {
    int n = input.length;
    if (n <= 1) return input;
    
    if ((n & (n - 1)) != 0) {
      throw ArgumentError("O tamanho do vetor deve ser uma potência de 2");
    }

    List<Complex> even = List.generate(n ~/ 2, (i) => input[i * 2]);
    List<Complex> odd = List.generate(n ~/ 2, (i) => input[i * 2 + 1]);

    even = transform(even);
    odd = transform(odd);

    List<Complex> result = List.filled(n, Complex(0, 0));
    for (int k = 0; k < n ~/ 2; k++) {
      double angle = -2 * pi * k / n;
      Complex t = Complex(cos(angle) * odd[k].r - sin(angle) * odd[k].i,
                          sin(angle) * odd[k].r + cos(angle) * odd[k].i);
      result[k] = even[k] + t;
      result[k + n ~/ 2] = even[k] - t;
    }
    return result;
  }
}

class Complex {
  final double r;
  final double i;
  Complex(this.r, this.i);
  
  Complex operator +(Complex other) => Complex(r + other.r, i + other.i);
  Complex operator -(Complex other) => Complex(r - other.r, i - other.i);
  
  double get magnitude => sqrt(r * r + i * i);
}

class SpectralInterpolation {
  // Interpolação Parabólica para precisão sub-bin
  static double refine(List<double> magnitudes, int peakIndex, double binWidth) {
    if (peakIndex <= 0 || peakIndex >= magnitudes.length - 1) {
      return peakIndex * binWidth;
    }
    double alpha = magnitudes[peakIndex - 1];
    double beta = magnitudes[peakIndex];
    double gamma = magnitudes[peakIndex + 1];

    double denominator = alpha - 2 * beta + gamma;
    if (denominator.abs() < 1e-10) return peakIndex * binWidth;

    double delta = 0.5 * (alpha - gamma) / denominator;
    return (peakIndex + delta) * binWidth;
  }
}