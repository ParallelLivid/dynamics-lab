function result = simulateAttractor(p)
%SIMULATEATTRACTOR Lorenz, Rössler, and Chua systems: a trajectory, a twin
%   started a tiny distance away, and the largest Lyapunov exponent.
%
%     'lorenz'   x' = σ (y − x),  y' = x (ρ − z) − y,  z' = x y − β z
%     'rossler'  x' = −y − z,  y' = x + a y,  z' = b + z (x − c)
%     'chua'     x' = α (y − x − f(x)),  y' = x − y + z,  z' = −βc y
%                f(x) = m1 x + ½ (m0 − m1)(|x + 1| − |x − 1|)
%
%   Fields: model; sigma, rho, beta (Lorenz); a, b, c (Rössler); alpha,
%   betaChua, m0, m1 (Chua); x0, y0, z0; delta (the twin starts at
%   x0 + delta); tspan, dt (output step); transient (fraction of the run
%   left out of the maxima and the exponent, 0–0.9); optional progressFcn
%   (@(fraction) stop).
%
%   The tangent equations v' = J(x) v are integrated along the trajectory
%   and renormalized every 10 time units (Benettin's method), so the
%   exponent is the mean exponential growth rate of an infinitesimal
%   separation, independent of the twin (which saturates at the size of
%   the attractor).
%
%   result: t, X (n×3), twin (n×3), separation (|X − twin|), lambda (the
%   largest Lyapunov exponent after the transient, 1/time), lambdaT and
%   lambdaHistory (its running estimate), divergenceTime (the twins 10 %
%   of the attractor's size apart; NaN if never), growthAmplitude (A in the
%   line A·e^{λt} fitted through the twins' exponential growth; NaN when
%   λ ≤ 0.01), extent (largest range of x, y, z after the transient),
%   maxima (values of the section variable at its successive maxima after
%   the transient, located by the solver's event detection), maximaTimes,
%   sectionName ("z" for Lorenz, "x" otherwise), distinct (clusters among
%   the maxima, tolerance 10⁻³ of max(1, the attractor's size): 1 for a simple
%   cycle, 2 after a period doubling, many for chaos; 0 when settled),
%   settled (true when the run ends at rest on an equilibrium),
%   equilibria (k×3), steady (logical, after the transient), complete
%   (false when cancelled).
validate(p);
f = rhsFor(p);
J = jacobianFor(p);

t = (0:p.dt:p.tspan)';
if t(end) < p.tspan - 1e-12 * p.tspan
    t(end + 1) = p.tspan;
end
n = numel(t);
start = [p.x0; p.y0; p.z0];
twinStart = start + [p.delta; 0; 0];
v = [1; 1; 1] / sqrt(3);
state = [start; twinStart; v];
augmented = @(~, s) [f(s(1:3)); f(s(4:6)); J(s(1:3)) * s(7:9)];
% Successive maxima of the section variable (z for Lorenz, x otherwise):
% located by the solver itself, where its rate falls through zero, so they
% do not depend on the output step.
column = 1;
result.sectionName = "x";
if strcmpi(p.model, 'lorenz')
    column = 3;
    result.sectionName = "z";
end
options = odeset('RelTol', 1e-10, 'AbsTol', 1e-12, 'Events', @(~, s) peakEvent(f, s, column));
peakTimes = zeros(0, 1);
peakValues = zeros(0, 1);

X = zeros(n, 3);
twin = zeros(n, 3);
logGrowth = zeros(n, 1);         % log |v| accumulated through the renormalizations
X(1, :) = start';
twin(1, :) = twinStart';
accumulated = 0;
chunk = max(1, round(10 / p.dt));  % output samples per renormalization
complete = true;
last = 1;
while last < n
    stop = min(last + chunk, n);
    span = t(last:stop);
    if numel(span) == 2
        span = [span(1); mean(span); span(2)];
        [~, s, te, ye] = ode45(augmented, span, state, options);
        s = s([1 3], :);
    else
        [~, s, te, ye] = ode45(augmented, span, state, options);
    end
    if ~isempty(te)
        peakTimes = [peakTimes; te(:)]; %#ok<AGROW>
        peakValues = [peakValues; ye(:, column)]; %#ok<AGROW>
    end
    X(last:stop, :) = s(:, 1:3);
    twin(last:stop, :) = s(:, 4:6);
    logGrowth(last:stop) = accumulated + log(vecnorm(s(:, 7:9), 2, 2));
    state = s(end, :)';
    growth = norm(state(7:9));
    accumulated = accumulated + log(growth);
    state(7:9) = state(7:9) / growth;
    last = stop;
    if ~all(isfinite(state(1:3))) || max(abs(state(1:3))) > 1e6
        error('attractors:Diverged', 'The trajectory ran off to infinity at t = %.4g.', t(stop));
    end
    if isfield(p, 'progressFcn') && ~isempty(p.progressFcn) && p.progressFcn(t(stop) / t(end))
        complete = stop == n;
        [t, X, twin, logGrowth] = deal(t(1:stop), X(1:stop, :), twin(1:stop, :), logGrowth(1:stop));
        break
    end
end

steady = t >= p.transient * t(end);
first = find(steady, 1);
result.t = t;
result.X = X;
result.twin = twin;
result.separation = vecnorm(X - twin, 2, 2);
result.steady = steady;
result.complete = complete;

% The exponent: growth of the tangent vector after the transient. The
% running estimate is left out over its first moments (at most 2 time
% units), where it divides by almost nothing and would swamp the plot.
elapsed = t - t(first);
result.lambdaT = t(steady);
result.lambdaHistory = (logGrowth(steady) - logGrowth(first)) ./ max(elapsed(steady), eps);
result.lambdaHistory(elapsed(steady) < min(2, 0.1 * (t(end) - t(first)))) = NaN;
result.lambdaHistory(1) = NaN;
result.lambda = NaN;
if t(end) > t(first)
    result.lambda = (logGrowth(end) - logGrowth(first)) / (t(end) - t(first));
end

extent = max(max(X(steady, :), [], 1) - min(X(steady, :), [], 1));
result.extent = extent;
apart = find(result.separation > 0.1 * extent, 1);
result.divergenceTime = NaN;
if ~isempty(apart)
    result.divergenceTime = t(apart);
end
result.growthAmplitude = growthFit(t, result.separation, result.lambda, extent);

% The maxima after the transient (a peak on a chunk's boundary is found
% by both chunks: once is enough).
keep = peakTimes >= t(first) & peakTimes <= t(end);
[peakTimes, order] = sort(peakTimes(keep));
peakValues = peakValues(keep);
peakValues = peakValues(order);
repeated = diff([-Inf; peakTimes]) < 1e-9 * max(1, t(end));
result.maxima = peakValues(~repeated);
result.maximaTimes = peakTimes(~repeated);
result.equilibria = equilibriaOf(p);
% Settled: at the end, resting on an equilibrium (a decaying spiral's
% maxima all differ, but it is not chaos).
scale = max(1, extent);
gaps = vecnorm(result.equilibria - X(end, :), 2, 2);
result.settled = ~isempty(gaps) && min(gaps) < 1e-3 * scale && norm(f(X(end, :)')) < 1e-3 * scale;
result.distinct = 0;
if ~result.settled
    result.distinct = clusters(result.maxima, 1e-3 * scale);   % relative to the attractor's size
end
end

% ------------------------------------------------------------------ models
function f = rhsFor(p)
switch lower(p.model)
    case 'lorenz'
        [s, r, b] = deal(p.sigma, p.rho, p.beta);
        f = @(x) [s * (x(2) - x(1)); x(1) * (r - x(3)) - x(2); x(1) * x(2) - b * x(3)];
    case 'rossler'
        [a, b, c] = deal(p.a, p.b, p.c);
        f = @(x) [-x(2) - x(3); x(1) + a * x(2); b + x(3) * (x(1) - c)];
    otherwise
        [al, be, m0, m1] = deal(p.alpha, p.betaChua, p.m0, p.m1);
        f = @(x) [al * (x(2) - x(1) - chuaDiode(x(1), m0, m1)); x(1) - x(2) + x(3); -be * x(2)];
end
end

function J = jacobianFor(p)
switch lower(p.model)
    case 'lorenz'
        [s, r, b] = deal(p.sigma, p.rho, p.beta);
        J = @(x) [-s, s, 0; r - x(3), -1, -x(1); x(2), x(1), -b];
    case 'rossler'
        [a, c] = deal(p.a, p.c);
        J = @(x) [0, -1, -1; 1, a, 0; x(3), 0, x(1) - c];
    otherwise
        [al, be, m0, m1] = deal(p.alpha, p.betaChua, p.m0, p.m1);
        J = @(x) [-al * (1 + chuaSlope(x(1), m0, m1)), al, 0; 1, -1, 1; 0, -be, 0];
end
end

function y = chuaDiode(x, m0, m1)
y = m1 * x + 0.5 * (m0 - m1) * (abs(x + 1) - abs(x - 1));
end

function d = chuaSlope(x, m0, m1)
% The diode's slope: m0 inside |x| < 1, m1 outside.
d = m1 + (m0 - m1) * (abs(x) < 1);
end

function E = equilibriaOf(p)
switch lower(p.model)
    case 'lorenz'
        E = [0 0 0];
        if p.rho > 1
            k = sqrt(p.beta * (p.rho - 1));
            E = [E; k k p.rho - 1; -k -k p.rho - 1];
        end
    case 'rossler'
        disc = p.c^2 - 4 * p.a * p.b;
        E = zeros(0, 3);
        if disc >= 0
            for x = (p.c + [-1 1] * sqrt(disc)) / 2
                E(end + 1, :) = [x, -x / p.a, x / p.a]; %#ok<AGROW>
            end
        end
    otherwise
        % Outer equilibria: x + f(x) = 0 with |x| > 1 gives x = ±k, which
        % lies in the outer region only when k = (m1 − m0)/(m1 + 1) ≥ 1.
        E = [0 0 0];
        if p.m1 ~= -1
            k = (p.m1 - p.m0) / (p.m1 + 1);
            if k >= 1
                E = [E; k 0 -k; -k 0 k];
            end
        end
end
end

% ---------------------------------------------------------------- analysis
function [value, isterminal, direction] = peakEvent(f, s, column)
% A maximum of the section variable: its rate falls through zero.
rate = f(s(1:3));
value = rate(column);
isterminal = 0;
direction = -1;
end

function A = growthFit(t, separation, lambda, extent)
% The line A·e^{λt} through the twins' exponential growth: λ is the
% exponent; A puts the line through the samples between ten times the
% starting distance and a hundredth of the attractor's size (least squares
% in log). NaN when there is no growth to fit.
A = NaN;
if ~(isfinite(lambda) && lambda > 0.01) || ~(separation(1) > 0)
    return
end
growing = separation > 10 * separation(1) & separation < 0.01 * extent;
first = find(growing, 1);
last = find(separation >= 0.01 * extent, 1) - 1;
if isempty(last)
    last = numel(t);
end
window = false(size(t));
if ~isempty(first) && last > first
    window(first:last) = growing(first:last);
end
if nnz(window) >= 10
    A = exp(mean(log(separation(window)) - lambda * t(window)));
end
end

function count = clusters(values, tolerance)
% Distinct values (greedy clustering), up to 1000.
centers = zeros(0, 1);
for v = values(:)'
    if isempty(centers) || all(abs(centers - v) > tolerance)
        centers(end + 1) = v; %#ok<AGROW>
        if numel(centers) > 1000
            break
        end
    end
end
count = numel(centers);
end

function validate(p)
if ~any(strcmpi(p.model, {'lorenz', 'rossler', 'chua'}))
    error('attractors:InvalidParameter', 'Unknown model "%s".', p.model);
end
if ~(p.tspan > 0 && p.dt > 0 && p.dt < p.tspan)
    error('attractors:InvalidParameter', 'The duration and output step must be positive, the step the shorter.');
end
if p.tspan / p.dt > 2e6
    error('attractors:InvalidParameter', 'Too many samples: increase the output step.');
end
if ~(p.transient >= 0 && p.transient <= 0.9)
    error('attractors:InvalidParameter', 'The transient must be between 0 and 90 %% of the run.');
end
if strcmpi(p.model, 'rossler') && p.a == 0
    error('attractors:InvalidParameter', 'Rössler: a must not be zero.');
end
end
