function D = maxwellDistance(speeds, mass, kT)
%MAXWELLDISTANCE Kolmogorov–Smirnov distance between SPEEDS and the 2-D
%   Maxwell–Boltzmann distribution f(v) = (m v / kT) exp(−m v² / 2kT),
%   whose cumulative distribution is F(v) = 1 − exp(−m v² / 2kT).
v = sort(speeds(:));
n = numel(v);
if n == 0 || ~(kT > 0)
    D = NaN;
    return
end
F = 1 - exp(-mass * v.^2 / (2 * kT));
D = max(max((1:n)' / n - F), max(F - (0:n - 1)' / n));
end
