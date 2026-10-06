function L = lagrangePoints(mu)
%LAGRANGEPOINTS The five equilibrium points of the circular restricted
%   three-body problem, as rows [x y z] of L (5×3), in the rotating frame
%   with the primaries at (−μ, 0) (mass 1 − μ) and (1 − μ, 0) (mass μ).
%   L1–L3 solve the collinear equation x − (1 − μ)(x + μ)/|x + μ|³ −
%   μ (x − 1 + μ)/|x − 1 + μ|³ = 0 (fzero, bracketed between and beyond
%   the primaries); L4 and L5 are at (½ − μ, ±√3/2).
if ~(mu > 0 && mu <= 0.5)
    error('threebody:InvalidParameter', 'The mass ratio must be in (0, 0.5].');
end
f = @(x) x - (1 - mu) * (x + mu) ./ abs(x + mu).^3 - mu * (x - 1 + mu) ./ abs(x - 1 + mu).^3;
gap = 1e-9;
x1 = fzero(f, [-mu + gap, 1 - mu - gap]);
x2 = fzero(f, [1 - mu + gap, 2]);
x3 = fzero(f, [-2, -mu - gap]);
L = [x1 0 0; x2 0 0; x3 0 0; 0.5 - mu, sqrt(3) / 2, 0; 0.5 - mu, -sqrt(3) / 2, 0];
end
