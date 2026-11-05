#include <jni.h>
#include <string>
#include <vector>
#include <cmath>
#include <complex>
#include <algorithm>

class BiquadBandpass {
private:
    double b0, b1, b2, a1, a2;
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

public:
    void configure(double centerFreq, double sampleRate, double Q = 1.5) {
        double omega = 2.0 * M_PI * centerFreq / sampleRate;
        double alpha = std::sin(omega) / (2.0 * Q);
        double cosOmega = std::cos(omega);
        b0 = alpha; b1 = 0.0; b2 = -alpha;
        double a0 = 1.0 + alpha;
        a1 = -2.0 * cosOmega; a2 = 1.0 - alpha;
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;
    }

    double process(double input) {
        double output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = input; y2 = y1; y1 = output;
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

    int fftSize = 4096;
    int startIndex = onsetIndex;
    if (startIndex + fftSize > length) startIndex = std::max(0, length - fftSize);

    BiquadBandpass filter;
    filter.configure(targetHz, sampleRate, 1.5);

    std::vector<std::complex<double>> fftData(fftSize);
    for (int i = 0; i < fftSize; i++) {
        double rawSample = buffer[startIndex + i];
        double filteredSample = filter.process(rawSample);
        double hann = 0.5 * (1.0 - std::cos(2.0 * M_PI * i / (fftSize - 1)));
        fftData[i] = std::complex<double>(filteredSample * hann, 0.0);
    }

    fft(fftData);

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

// ============================================================================
// ✅ NOVA FUNÇÃO: processAudioDebug (RODA COM E SEM FILTRO)
// ============================================================================
extern "C" __attribute__((visibility("default"))) void processAudioDebug(
    double* buffer, 
    int length, 
    int sampleRate,
    int drumType,
    double targetHz,
    double* out
) {
    out[7] = (double)length;
    if (length < 2048) {
        for (int i = 0; i < 7; i++) out[i] = 0.0;
        return;
    }

    // Onset
    int onsetIndex = 0;
    double maxRms = 0.0;
    int hopSize = 512;
    for (int i = 0; i <= length - hopSize; i += hopSize) {
        double sum = 0.0;
        for (int j = 0; j < hopSize; j++) sum += buffer[i + j] * buffer[i + j];
        double rms = std::sqrt(sum / hopSize);
        if (rms > maxRms) { maxRms = rms; onsetIndex = i; }
    }

    int fftSize = 4096;
    int startIndex = onsetIndex;
    if (startIndex + fftSize > length) startIndex = std::max(0, length - fftSize);

    BiquadBandpass filter;
    filter.configure(targetHz, sampleRate, 1.5);

    // COM FILTRO
    std::vector<std::complex<double>> fftFilt(fftSize);
    for (int i = 0; i < fftSize; i++) {
        double filtered = filter.process(buffer[startIndex + i]);
        double hann = 0.5 * (1.0 - std::cos(2.0 * M_PI * i / (fftSize - 1)));
        fftFilt[i] = std::complex<double>(filtered * hann, 0.0);
    }
    fft(fftFilt);

    // SEM FILTRO
    std::vector<std::complex<double>> fftRaw(fftSize);
    for (int i = 0; i < fftSize; i++) {
        double hann = 0.5 * (1.0 - std::cos(2.0 * M_PI * i / (fftSize - 1)));
        fftRaw[i] = std::complex<double>(buffer[startIndex + i] * hann, 0.0);
    }
    fft(fftRaw);

    double minFreq = 40.0, maxFreq = 300.0;
    if (drumType == 0) { minFreq = 140.0; maxFreq = 260.0; }
    if (drumType == 1) { minFreq = 40.0;  maxFreq = 110.0; }
    if (drumType == 2) { minFreq = 110.0; maxFreq = 220.0; }
    if (drumType == 3) { minFreq = 90.0;  maxFreq = 180.0; }
    if (drumType == 4) { minFreq = 55.0;  maxFreq = 145.0; }

    double binWidth = (double)sampleRate / fftSize;
    int minBin = (int)(minFreq / binWidth);
    int maxBin = (int)(maxFreq / binWidth);

    // Pico filtrado
    double maxMagFilt = 0.0;
    int peakBinFilt = minBin;
    double sumMagFilt = 0.0;
    int countMagFilt = 0;
    for (int i = minBin; i <= maxBin && i < fftSize / 2; i++) {
        double m = std::abs(fftFilt[i]);
        sumMagFilt += m; countMagFilt++;
        if (m > maxMagFilt) { maxMagFilt = m; peakBinFilt = i; }
    }
    double refinedFilt = peakBinFilt;
    if (peakBinFilt > 0 && peakBinFilt < fftSize / 2 - 1) {
        double a = std::abs(fftFilt[peakBinFilt - 1]);
        double b = std::abs(fftFilt[peakBinFilt]);
        double c = std::abs(fftFilt[peakBinFilt + 1]);
        double d = 2 * (2 * b - c - a);
        if (d != 0) refinedFilt = peakBinFilt + (c - a) / d;
    }

    // Pico sem filtro
    double maxMagRaw = 0.0;
    int peakBinRaw = minBin;
    for (int i = minBin; i <= maxBin && i < fftSize / 2; i++) {
        double m = std::abs(fftRaw[i]);
        if (m > maxMagRaw) { maxMagRaw = m; peakBinRaw = i; }
    }
    double refinedRaw = peakBinRaw;
    if (peakBinRaw > 0 && peakBinRaw < fftSize / 2 - 1) {
        double a = std::abs(fftRaw[peakBinRaw - 1]);
        double b = std::abs(fftRaw[peakBinRaw]);
        double c = std::abs(fftRaw[peakBinRaw + 1]);
        double d = 2 * (2 * b - c - a);
        if (d != 0) refinedRaw = peakBinRaw + (c - a) / d;
    }

    // Razão pico/média (com filtro)
    double meanMag = (countMagFilt > 0) ? sumMagFilt / countMagFilt : 0.0;
    double ratio = (meanMag > 0) ? maxMagFilt / meanMag : 0.0;

    // Segundo pico (filtrado, fora de ±2 bins do pico)
    double maxMagSecond = 0.0;
    int secondBin = peakBinFilt;
    for (int i = minBin; i <= maxBin && i < fftSize / 2; i++) {
        if (std::abs(i - peakBinFilt) <= 2) continue;
        double m = std::abs(fftFilt[i]);
        if (m > maxMagSecond) { maxMagSecond = m; secondBin = i; }
    }

    out[0] = refinedFilt * binWidth;
    out[1] = refinedRaw * binWidth;
    out[2] = maxRms;
    out[3] = (double)onsetIndex;
    out[4] = (double)startIndex;
    out[5] = ratio;
    out[6] = secondBin * binWidth;
}