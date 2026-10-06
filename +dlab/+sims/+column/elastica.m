function sol = elastica(options)
%ELASTICA Euler's elastica: a pinned–pinned column bent far past buckling.
%   sol = dlab.sims.column.elastica(Ratio=rho) finds the shape at the load
%   P = rho · P_cr by shooting; sol = dlab.sims.column.elastica(Alpha=a)
%   finds the load that turns the ends by the angle a (rad).
%
%   The column is inextensible, of unit length (lengths are in units of
%   the column's length), and pinned at both ends with the load along the
%   line through them. With θ(s) the angle of the centreline to that line
%   and s the arc length, the bending moment P·w gives
%
%       θ'' + μ sin θ = 0,   μ = P L² / EI = π² rho,   θ(0) = α, θ'(0) = 0
%
%   and the shape follows from x' = cos θ, w' = sin θ. Symmetry puts the
%   crest at mid-length: θ(1/2) = 0. Shooting: for a load rho, fzero finds
%   the end rotation α at which ode45, started at the end, first reaches
%   θ = 0 at exactly s = 1/2 (that distance grows with α, so the root is
%   unique). For a given α the same integration with μ = 1 gives the
%   quarter length T, and μ = (2T)².
%
%   Below the Euler load (rho <= 1) the only shape is straight (α = 0).
%
%   Options:
%     Span      arc length to integrate the shape over (default 1; the
%               periodic continuation beyond 1 gives the fixed–free and
%               fixed–fixed elastica as pieces of the same curve)
%     Points    samples of the shape (default 201)
%
%   Fields of SOL: alpha (rad), ratio (P/P_cr), mu, k = sin(α/2), the
%   samples s, theta, x, w (columns), deflection (w at s = 1/2), and
%   shortening (1 − x at s = 1). Known result for checks:
%   rho = (2 K(k) / π)², with K the complete elliptic integral of the
%   first kind (ellipke(k²)).
arguments
    options.Alpha (1,1) double = NaN
    options.Ratio (1,1) double = NaN
    options.Span (1,1) double {mustBePositive} = 1
    options.Points (1,1) double {mustBeInteger, mustBeGreaterThan(options.Points, 2)} = 201
end
if isnan(options.Alpha) == isnan(options.Ratio)
    error("column:InvalidParameter", "Give the elastica either Alpha or Ratio.");
end
if ~isnan(options.Ratio)
    rho = options.Ratio;
    if ~(isfinite(rho) && rho >= 0)
        error("column:InvalidParameter", "The load ratio must be a finite number >= 0.");
    end
    alpha = shoot(rho);
else
    alpha = options.Alpha;
    if ~(alpha >= 0 && alpha < pi)
        error("column:InvalidParameter", "The end rotation must be in [0, π).");
    end
    if alpha == 0
        rho = 1;
    else
        rho = (2 * quarterLength(alpha, 1) / pi)^2;
    end
end

mu = pi^2 * max(rho, 1);
sol.alpha = alpha;
sol.ratio = rho;
sol.mu = mu;
sol.k = sin(alpha / 2);
s = linspace(0, options.Span, options.Points)';
s = unique([s; 0.5; 1]);
s = s(s <= options.Span);
if alpha == 0
    [theta, x, w] = deal(zeros(size(s)), s, zeros(size(s)));
else
    opts = odeset("RelTol", 1e-11, "AbsTol", 1e-13);
    if numel(s) == 2
        s = [s(1); mean(s); s(2)];
    end
    [~, y] = ode45(@(~, y) [y(2); -mu * sin(y(1)); cos(y(1)); sin(y(1))], s, [alpha; 0; 0; 0], opts);
    [theta, x, w] = deal(y(:, 1), y(:, 3), y(:, 4));
end
sol.s = s;
sol.theta = theta;
sol.x = x;
sol.w = w;
sol.deflection = NaN;
sol.shortening = NaN;
if any(s == 0.5)
    sol.deflection = w(s == 0.5);
end
if any(s == 1)
    sol.shortening = 1 - x(s == 1);
end
end

function alpha = shoot(rho)
% The end rotation at which the crest falls at mid-length, for load RHO.
if rho <= 1
    alpha = 0;
    return
end
mu = pi^2 * rho;
miss = @(a) quarterLength(a, mu) - 0.5;
low = 1e-7;
high = pi * (1 - 1e-6);
if miss(low) >= 0
    alpha = 2 * asin(min(sqrt(2 * (rho - 1)), 1));   % just past buckling: ρ ≈ 1 + k²/2
    return
end
if miss(high) <= 0
    error("column:InvalidParameter", "The load is too far past buckling for the elastica (P/P_cr = %.4g).", rho);
end
alpha = fzero(miss, [low high], optimset("TolX", 1e-15));
end

function T = quarterLength(alpha, mu)
% Arc length from the end (θ = α, θ' = 0) to the first θ = 0.
opts = odeset("RelTol", 1e-11, "AbsTol", 1e-13 * [alpha, alpha * sqrt(mu)], "Events", @crossing);
[~, ~, te] = ode45(@(~, y) [y(2); -mu * sin(y(1))], [0 60 / sqrt(mu)], [alpha; 0], opts);
if isempty(te)
    T = Inf;
else
    T = te(1);
end
end

function [value, terminal, direction] = crossing(~, y)
value = y(1);
terminal = true;
direction = -1;
end
