function [X, Y, twoOmega] = zeroVelocity(mu, xRange, yRange, count)
%ZEROVELOCITY 2Ω on a grid in the plane z = 0. A body with Jacobi
%   constant C can only be where 2Ω ≥ C (its speed² = 2Ω − C); the curve
%   2Ω = C bounds the forbidden region.
if nargin < 4
    count = 300;
end
[X, Y] = meshgrid(linspace(xRange(1), xRange(2), count), linspace(yRange(1), yRange(2), count));
r1 = sqrt((X + mu).^2 + Y.^2);
r2 = sqrt((X - 1 + mu).^2 + Y.^2);
twoOmega = X.^2 + Y.^2 + 2 * (1 - mu) ./ r1 + 2 * mu ./ r2;
end
