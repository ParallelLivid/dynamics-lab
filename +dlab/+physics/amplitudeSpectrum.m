function [frequency, amplitude, peak] = amplitudeSpectrum(t, y)
%AMPLITUDESPECTRUM One-sided amplitude spectrum of a uniformly sampled signal.
%   [f, A] = dlab.physics.amplitudeSpectrum(t, y) for samples y at the
%   uniformly spaced times t (s). The mean is removed and a Hann window
%   applied; A is scaled by twice the window's sum, so a sinusoid that
%   falls on a frequency bin shows its own amplitude. f (Hz) runs from 0
%   in steps of 1/(n dt) up to below the Nyquist frequency; f and A are
%   columns, empty for fewer than 8 samples.
%   [f, A, peak] = ... also returns the dominant frequency (Hz): the
%   largest bin above zero, refined by a parabola through the logarithms
%   of it and its neighbours (exact for a Gaussian peak, and close for the
%   Hann window's). NaN for fewer than 8 samples.
frequency = zeros(0, 1);
amplitude = zeros(0, 1);
peak = NaN;
n = numel(y);
if n < 8
    return
end
y = y(:);
dt = (t(end) - t(1)) / (n - 1);
window = 0.5 - 0.5 * cos(2 * pi * (0:n - 1)' / (n - 1));
Y = abs(fft((y - mean(y)) .* window)) / sum(window) * 2;
half = (1:floor(n / 2))';
frequency = (half - 1) / (n * dt);
amplitude = Y(half);
if nargout < 3
    return
end
[~, k] = max(amplitude(2:end));
k = k + 1;
peak = frequency(k);
if k < numel(half)
    L = log(max(amplitude(k - 1:k + 1), realmin));
    offset = (L(1) - L(3)) / (2 * (L(1) - 2 * L(2) + L(3)));
    if isfinite(offset)
        peak = peak + offset * frequency(2);
    end
end
end
