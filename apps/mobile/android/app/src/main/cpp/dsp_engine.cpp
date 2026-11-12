#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <complex>
#include <algorithm>

void fft(std::vector<std::complex<double>>& a) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (int len = 2; len <= n; len <<= 1) {
        double ang = 2 * M_PI / len * -1;
        std::complex<double> wlen(cos(ang), sin(ang));
        for (int i = 0; i < n; i += len) {
            std::complex<double> w(1);
            for (int j = 0; j < len / 2; j++) {
                std::complex<double> u = a[i + j];
                std::complex<double> v = a[i + j + len / 2] * w;
                a[i + j] = u + v;
                a[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
}

extern "C" __attribute__((visibility("default"))) double processAudioBuffer(
    double* buffer, 
    int length, 
    int sampleRate,
    int drumType,
    double targetHz
) {
    if (length < 2048) return 0.0;

    // 1. Achar o Onset (janela de 256 amostras para precisão)
    int onsetIndex = 0;
    double maxRms = 0.0;
    int hopSize = 256;
    for (int i = 0; i <= length - hopSize; i += hopSize) {
        double sum = 0.0;
        for (int j = 0; j < hopSize; j++) sum += buffer[i + j] * buffer[i + j];
        double rms = std::sqrt(sum / hopSize);
        if (rms > maxRms) { maxRms = rms; onsetIndex = i; }
    }
    if (maxRms < 0.01) return 0.0;

    // 2. Pular o estalo inicial e pegar exatamente 2048 amostras (com zero-padding)
    int fftSize = 2048;
    int startIndex = onsetIndex + 128; // Pula o transiente de 128 amostras (aprox 6ms)

    std::vector<std::complex<double>> fftData(fftSize);
    for (int i = 0; i < fftSize; i++) {
        double val = 0.0;
        if (startIndex + i < length) {
            val = buffer[startIndex + i];
        }
        double hann = 0.5 * (1.0 - std::cos(2.0 * M_PI * i / (fftSize - 1)));
        fftData[i] = std::complex<double>(val * hann, 0.0);
    }

    // 3. FFT
    fft(fftData);

    // 4. Faixa de busca fixa (Independente do alvo)
    double minFreq = 40.0, maxFreq = 300.0;
    if (drumType == 0) { minFreq = 140.0; maxFreq = 260.0; }
    if (drumType == 1) { minFreq = 40.0;  maxFreq = 110.0; }
    if (drumType == 2) { minFreq = 110.0; maxFreq = 220.0; }
    if (drumType == 3) { minFreq = 90.0;  maxFreq = 180.0; }
    if (drumType == 4) { minFreq = 55.0;  maxFreq = 145.0; }

    double binWidth = (double)sampleRate / fftSize;
    int minBin = (int)(minFreq / binWidth);
    int maxBin = (int)(maxFreq / binWidth);

    double maxMag = 0.0;
    int peakBin = minBin;
    for (int i = minBin; i <= maxBin && i < fftSize / 2; i++) {
        double m = std::abs(fftData[i]);
        if (m > maxMag) { maxMag = m; peakBin = i; }
    }

    // 5. Interpolação Parabólica
    double refinedBin = peakBin;
    if (peakBin > 0 && peakBin < fftSize / 2 - 1) {
        double alpha = std::abs(fftData[peakBin - 1]);
        double beta = std::abs(fftData[peakBin]);
        double gamma = std::abs(fftData[peakBin + 1]);
        double denominator = 2 * (2 * beta - gamma - alpha);
        if (denominator != 0) refinedBin = peakBin + (gamma - alpha) / denominator;
    }

    return refinedBin * binWidth;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
double processStringBuffer(const double* buffer, int length, int sampleRate) {
    if (buffer == nullptr || length <= 0 || sampleRate <= 0) return 0.0;

    // RMS para detectar silêncio
    double sumSq = 0.0;
    for (int i = 0; i < length; i++) sumSq += buffer[i] * buffer[i];
    double rms = std::sqrt(sumSq / (double)length);
    if (rms < 0.01) return 0.0;

    // Limites dinâmicos de frequência
    const double minFreq = 30.0;
    const double maxFreq = 1700.0;
    int tauMin = (int)std::floor((double)sampleRate / maxFreq);
    int tauMax = (int)std::ceil((double)sampleRate / minFreq);
    if (tauMin < 1) tauMin = 1;
    if (tauMax >= length / 2) tauMax = length / 2 - 1;
    if (tauMax <= tauMin) return 0.0;

    const int windowSize = length - tauMax;
    if (windowSize <= 0) return 0.0;

    // (a) Função de Diferença
    std::vector<double> diff(tauMax + 1, 0.0);
    for (int tau = tauMin; tau <= tauMax; tau++) {
        double sum = 0.0;
        for (int j = 0; j < windowSize; j++) {
            double d = buffer[j] - buffer[j + tau];
            sum += d * d;
        }
        diff[tau] = sum;
    }

    // (b) CMNDF
    std::vector<double> cmndf(tauMax + 1, 0.0);
    cmndf[0] = 1.0;
    double running = 0.0;
    for (int tau = 1; tau <= tauMax; tau++) {
        running += diff[tau];
        if (running <= 0.0) {
            cmndf[tau] = 1.0;
        } else {
            cmndf[tau] = diff[tau] * (double)tau / running;
        }
    }

    // (c) Limiar absoluto: primeiro mínimo local abaixo de 0.15
    const double threshold = 0.15;
    int tauEstimate = -1;
    for (int tau = tauMin; tau <= tauMax; tau++) {
        if (cmndf[tau] < threshold) {
            while (tau + 1 <= tauMax && cmndf[tau + 1] < cmndf[tau]) tau++;
            tauEstimate = tau;
            break;
        }
    }
    if (tauEstimate < 0) return 0.0;

    // (d) Interpolação parabólica
    double betterTau = (double)tauEstimate;
    if (tauEstimate > 0 && tauEstimate < tauMax) {
        double x0 = cmndf[tauEstimate - 1];
        double x1 = cmndf[tauEstimate];
        double x2 = cmndf[tauEstimate + 1];
        double denom = 2.0 * (2.0 * x1 - x2 - x0);
        if (denom != 0.0) {
            betterTau = (double)tauEstimate + (x2 - x0) / denom;
        }
    }
    if (betterTau <= 0.0) return 0.0;

    return (double)sampleRate / betterTau;
}