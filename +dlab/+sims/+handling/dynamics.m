function [dx, f] = dynamics(x, delta, p)
%DYNAMICS Single-track (bicycle) model at constant forward speed.
%   [dx, f] = dynamics(x, delta, p) for states X = [v; r] (lateral
%   velocity, m/s, positive to the left; yaw rate, rad/s, positive
%   turning left) and the road-wheel steering angle DELTA (rad). X may be
%   2×N with DELTA 1×N (one column per sample).
%
%     α_f = (v + a r)/V − δ        α_r = (v − b r)/V
%     m (v' + V r) = F_f + F_r     I_z r' = a F_f − b F_r
%
%   Tyre force per axle (p.tyre):
%     'linear'      F = −C α
%     'saturating'  F = −μ F_z tanh(C α / (μ F_z)), with the static axle
%                   loads F_zf = m g b / L and F_zr = m g a / L
%
%   P: m, Iz, a, b, Cf, Cr (N/rad, per axle), V (m/s), tyre, mu, g.
%   F: alphaF, alphaR (rad), Ff, Fr (N), ay (m/s², the lateral
%   acceleration v' + V r), all 1×N.
v = x(1, :);
r = x(2, :);
alphaF = (v + p.a * r) / p.V - delta;
alphaR = (v - p.b * r) / p.V;
if strcmpi(p.tyre, 'saturating')
    L = p.a + p.b;
    Fzf = p.m * p.g * p.b / L;
    Fzr = p.m * p.g * p.a / L;
    Ff = -p.mu * Fzf * tanh(p.Cf * alphaF / (p.mu * Fzf));
    Fr = -p.mu * Fzr * tanh(p.Cr * alphaR / (p.mu * Fzr));
else
    Ff = -p.Cf * alphaF;
    Fr = -p.Cr * alphaR;
end
ay = (Ff + Fr) / p.m;
dx = [ay - p.V * r; (p.a * Ff - p.b * Fr) / p.Iz];
f = struct('alphaF', alphaF, 'alphaR', alphaR, 'Ff', Ff, 'Fr', Fr, 'ay', ay);
end
