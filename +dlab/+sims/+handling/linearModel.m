function [A, B, info] = linearModel(p)
%LINEARMODEL The linear single-track model x' = A x + B δ, x = [v; r].
%   [A, B, info] = linearModel(p) with the fields of dynamics (the tyres
%   linear, F = −C α, whatever p.tyre says). INFO:
%
%     understeerGradient   K = (m/L)(b/Cf − a/Cr), rad per m/s²
%                          (> 0 understeer, < 0 oversteer, 0 neutral)
%     yawGain              steady-state r/δ (1/s), from the steady state
%                          of the linear model, −A⁻¹B; it equals
%                          V / (L + K V²). NaN when the model is unstable.
%     characteristicSpeed  √(L/K) (m/s) when K > 0, where r/δ peaks; else NaN
%     criticalSpeed        √(−L/K) (m/s) when K < 0, above which the car
%                          is unstable; else NaN
%     poles                eig(A)
%     stable               all poles in the left half plane
m = p.m;
V = p.V;
a = p.a;
b = p.b;
Cf = p.Cf;
Cr = p.Cr;
L = a + b;
A = [-(Cf + Cr) / (m * V), -(a * Cf - b * Cr) / (m * V) - V
     -(a * Cf - b * Cr) / (p.Iz * V), -(a^2 * Cf + b^2 * Cr) / (p.Iz * V)];
B = [Cf / m; a * Cf / p.Iz];

K = m / L * (b / Cf - a / Cr);
if abs(K) < 1e-12 * m / L * (b / Cf + a / Cr)
    K = 0;                                        % neutral steer, to rounding
end
info.understeerGradient = K;
info.poles = eig(A);
info.stable = all(real(info.poles) < 0);
info.yawGain = NaN;
if info.stable
    % r of −A⁻¹B, by the 2×2 inverse (no warning when det A is tiny)
    info.yawGain = (A(2, 1) * B(1) - A(1, 1) * B(2)) / det(A);
end
info.characteristicSpeed = NaN;
info.criticalSpeed = NaN;
if K > 0
    info.characteristicSpeed = sqrt(L / K);
elseif K < 0
    info.criticalSpeed = sqrt(-L / K);
end
end
