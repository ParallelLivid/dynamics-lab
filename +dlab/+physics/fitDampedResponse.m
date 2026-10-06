function [poles, amplitudes, fitted, rSquared] = fitDampedResponse(t, y, nPoles)
%FITDAMPEDRESPONSE Fit a sum of damped exponentials to a response.
%   [poles, amplitudes, fitted, R2] = dlab.physics.fitDampedResponse(t, y, n)
%   models y(t) ≈ Σ a_k exp(λ_k (t − t(1))) with n continuous-time poles
%   λ_k (complex conjugate pairs for oscillations, real for decays), by the
%   matrix pencil method (Hua and Sarkar, 1990).
%
%   An oscillatory mode needs n = 2: then ω_n = |λ|, ζ = −Re λ / |λ|, and
%   the damped period is 2π / |Im λ|. A first-order decay needs n = 1:
%   the time constant is −1 / λ. Remove any steady offset from y first.
%
%   POLES (n×1), AMPLITUDES (n×1, complex), FITTED (real, at the samples
%   t), and R2 (coefficient of determination of the fit).
t = t(:);
y = y(:);
if numel(t) ~= numel(y) || numel(t) < 4 * nPoles + 4
    error("dlab:physics:fit", "Need at least %d samples to fit %d poles.", 4 * nPoles + 4, nPoles);
end
% A uniform grid (the method assumes one) of at most 2000 points.
count = min(numel(t), 2000);
grid = linspace(t(1), t(end), count)';
samples = interp1(t, y, grid);
dt = grid(2) - grid(1);

pencil = floor(count / 3);
data = hankel(samples(1:count - pencil), samples(count - pencil:count));
[~, ~, V] = svd(data, 0);
V = V(:, 1:nPoles);
z = eig(V(1:end-1, :) \ V(2:end, :));
poles = log(z) / dt;

basis = exp((grid - grid(1)) * poles.');
amplitudes = basis \ samples;
fitted = real(exp((t - t(1)) * poles.') * amplitudes);

total = sum((y - mean(y)).^2);
rSquared = 1 - sum((y - fitted).^2) / max(total, realmin);
[~, order] = sort(imag(poles));
poles = poles(order);
amplitudes = amplitudes(order);
end
