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