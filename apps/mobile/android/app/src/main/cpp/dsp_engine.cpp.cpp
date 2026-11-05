#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <complex>
#include <algorithm>

// ============================================================================
// MOTOR DSP NATIVO C++ (Filtro Biquad + FFT + Hann + Interpolação)
// ============================================================================

class BiquadBandpass {
private:
    double b0, b1, b2, a1, a2;
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

public:
    void configure(double centerFreq, double sampleRate, double Q = 1.5) {
        double omega = 2.0 * M_PI * centerFreq / sampleRate;
        double alpha = std::sin(omega) / (2.0 * Q);
        double cosOmega = std::cos(omega);

        b0 = alpha;
        b1 = 0.0;
        b2 = -alpha;
        double a0 = 1.0 + alpha;
        a1 = -2.0 * cosOmega;
        a2 = 1.0 - alpha;

        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;
    }

    double process(double input) {
        double output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = input;
        y2 = y1; y1 = output;
        return output;
    }
};

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

    // 1. Onset
    int onsetIndex = 0;
    double maxRms = 0.0;
    int hopSize = 512;
    for (int i = 0; i <= length - hopSize; i += hopSize) {
        double sum = 0.0;
        for (int j = 0; j < hopSize; j++) sum += buffer[i + j] * buffer[i + j];
        double rms = std::sqrt(sum / hopSize);
        if (rms > maxRms) { maxRms = rms; onsetIndex = i; }
    }
    if (maxRms < 0.005) return 0.0;

    // 2. Janela
    int fftSize = 4096;
    int startIndex = onsetIndex;
    if (startIndex + fftSize > length) startIndex = std::max(0, length - fftSize);

    // 3. Filtro Biquad
    BiquadBandpass filter;
    filter.configure(targetHz, sampleRate, 1.5);

    std::vector<std::complex<double>> fftData(fftSize);
    for (int i = 0; i < fftSize; i++) {
        double rawSample = buffer[startIndex + i];
        double filteredSample = filter.process(rawSample);
        double hann = 0.5 * (1.0 - std::cos(2.0 * M_PI * i / (fftSize - 1)));
        fftData[i] = std::complex<double>(filteredSample * hann, 0.0);
    }

    // 4. FFT
    fft(fftData);

    // 5. Pico
    double maxMag = 0.0;
    int peakBin = 0;
    double minFreq = 40.0, maxFreq = 300.0;
    if (drumType == 0) { minFreq = 140.0; maxFreq = 260.0; }
    if (drumType == 1) { minFreq = 40.0;  maxFreq = 110.0; }
    if (drumType == 2) { minFreq = 110.0; maxFreq = 220.0; }
    if (drumType == 3) { minFreq = 90.0;  maxFreq = 180.0; }
    if (drumType == 4) { minFreq = 55.0;  maxFreq = 145.0; }

    double binWidth = (double)sampleRate / fftSize;
    int minBin = (int)(minFreq / binWidth);
    int maxBin = (int)(maxFreq / binWidth);

    for (int i = minBin; i <= maxBin && i < fftSize / 2; i++) {
        double mag = std::abs(fftData[i]);
        if (mag > maxMag) { maxMag = mag; peakBin = i; }
    }

    // 6. Interpolação
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