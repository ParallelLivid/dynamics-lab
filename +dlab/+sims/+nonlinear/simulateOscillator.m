function result = simulateOscillator(p)
%SIMULATEOSCILLATOR Driven nonlinear oscillators, with Poincaré sections.
%   result = simulateOscillator(p) integrates one of
%
%     'duffing'     x'' + δ x' + α x + β x³ = A cos ωt
%     'vanderpol'   x'' − μ (1 − x²) x' + x = A cos ωt
%     'pendulum'    θ'' + θ'/q + sin θ = A cos ωt
%
%   Fields: model; delta, alpha, beta (Duffing); mu (Van der Pol); q
%   (pendulum); A, omega (forcing); x0, v0; periods (duration in forcing
%   periods) or tspan (duration when unforced, A = 0); transient (fraction
%   of the run left out of the section and spectrum, 0–0.95);
%   samplesPerPeriod (output samples per forcing period, or per 2π time
%   units when unforced); optional progressFcn (@(fraction) stop).
%
%   The Poincaré section is stroboscopic when forced (the state once per
%   forcing period, θ wrapped to (−π, π]); when unforced, it is the state at
%   each maximum of x (where v crosses zero from above).
%
%   result: t, x, v, forced, period (forcing period, NaN unforced), steady
%   (logical, after the transient), poincare ([x v] rows), poincareTimes,
%   distinct (clusters among the section points, tolerance 1e-3 of the
%   motion's size), spread (largest range of the section coordinates),
%   amplitude ((max − min)/2 of x after the transient; NaN for a pendulum
%   that turns over the top), overTheTop (pendulum: θ covers more than a
%   full turn after the transient, so it runs on), atRest (the
%   motion after the transient is smaller than 10⁻⁶ of the run's size:
%   it has settled), cyclePeriod (unforced: mean time between maxima),
%   spectrum (omega in rad/s, magnitude; of θ' for the pendulum),
%   dominantFrequency (rad/s; NaN at rest), energy (Duffing and pendulum:
%   v²/2 + V(x)), potential (@(x) V(x), empty for Van der Pol), and
%   complete (false when cancelled).
%
%   Integration: classical Runge–Kutta, with substeps between output
%   times so that step × local rate ≤ 0.1.
validate(p);
model = lower(p.model);
forced = p.A ~= 0 && p.omega > 0;
if forced
    period = 2 * pi / p.omega;
    t = (0:round(p.periods) * p.samplesPerPeriod)' * period / p.samplesPerPeriod;
else
    period = NaN;
    dt = 2 * pi / p.samplesPerPeriod;
    t = (0:dt:p.tspan)';
    if t(end) < p.tspan
        t(end + 1) = p.tspan;
    end
end
planned = t(end);
[t, y] = integrate(p, model, t);
x = y(:, 1);
v = y(:, 2);
f = @(time, state) rhs(time, state, p, model);

result.t = t;
result.x = x;
result.v = v;
result.forced = forced;
result.period = period;
result.steady = t >= p.transient * t(end);
result.cyclePeriod = NaN;
if forced
    first = ceil(p.transient * p.periods);
    index = (first * p.samplesPerPeriod + 1:p.samplesPerPeriod:numel(t))';
    section = [x(index), v(index)];
    sectionTimes = t(index);
else
    c = [p.delta p.alpha p.beta p.mu p.q p.A p.omega];
    id = find(strcmp(model, {'duffing', 'vanderpol', 'pendulum'}));
    [section, sectionTimes] = maxima(t, x, v, f, @(state) rate(id, state, c), result.steady);
    if numel(sectionTimes) >= 2
        result.cyclePeriod = mean(diff(sectionTimes));
    end
end
if strcmp(model, 'pendulum') && ~isempty(section)
    section(:, 1) = wrapAngle(section(:, 1));
end
result.poincare = section;
result.poincareTimes = sectionTimes;
result.complete = t(end) >= planned;
isPendulum = strcmp(model, 'pendulum');
steadyX = x(result.steady);
steadyV = v(result.steady);
if isPendulum
    scale = max([pi; max(abs(steadyV))]);           % θ is wrapped in the section
else
    scale = max([1; max(abs(steadyX)); max(abs(steadyV))]);
end
result.distinct = clusters(section, 1e-3 * scale, isPendulum);
result.spread = spreadOf(section, isPendulum);
result.amplitude = (max(steadyX) - min(steadyX)) / 2;
% Settled: what is left after the transient is tiny beside the whole run.
extent = max([1; abs(x); abs(v)]);
result.atRest = ~isempty(steadyX) && ...
    max(max(steadyX) - min(steadyX), max(steadyV) - min(steadyV)) <= 1e-6 * extent;
% (A swing that just passes the inverted position and falls back, as at
% A = 1.07, still has an amplitude.)
result.overTheTop = isPendulum && ~isempty(steadyX) && max(steadyX) - min(steadyX) > 2 * pi;
if result.overTheTop
    result.amplitude = NaN;                          % θ runs on: no amplitude
end
if isPendulum
    % θ drifts when the pendulum goes over the top: use the rate θ'.
    [result.spectrum, result.dominantFrequency] = spectrumOf(t(result.steady), steadyV);
else
    [result.spectrum, result.dominantFrequency] = spectrumOf(t(result.steady), steadyX);
end
if result.atRest
    result.dominantFrequency = NaN;                  % only rounding noise is left
end
[result.potential, result.energy] = energyOf(p, model, x, v);
end

% ------------------------------------------------------------ integrator
function [t, y] = integrate(p, model, t)
% Classical Runge–Kutta between output times, with as many substeps as
% the local rate needs (step × rate ≤ 0.1), so the stroboscopic samples
% fall exactly on the output times. A cancel ends the run early (the
% third column marks the samples reached).
id = find(strcmp(model, {'duffing', 'vanderpol', 'pendulum'}));
c = [p.delta p.alpha p.beta p.mu p.q p.A p.omega];
y = zeros(numel(t), 3);
state = [p.x0, p.v0];
y(1, :) = [state 1];
hasProgress = isfield(p, 'progressFcn') && ~isempty(p.progressFcn);
nextReport = 0.02;
for k = 1:numel(t) - 1
    span = t(k + 1) - t(k);
    n = max(1, ceil(span * rate(id, state, c) / 0.1));
    h = span / n;
    for j = 1:n
        tau = t(k) + (j - 1) * h;
        x = state(1);
        v = state(2);
        a1 = acceleration(id, tau, x, v, c);
        a2 = acceleration(id, tau + h / 2, x + h / 2 * v, v + h / 2 * a1, c);
        v2 = v + h / 2 * a1;
        a3 = acceleration(id, tau + h / 2, x + h / 2 * v2, v + h / 2 * a2, c);
        v3 = v + h / 2 * a2;
        a4 = acceleration(id, tau + h, x + h * v3, v + h * a3, c);
        v4 = v + h * a3;
        state = [x + h / 6 * (v + 2 * v2 + 2 * v3 + v4), v + h / 6 * (a1 + 2 * a2 + 2 * a3 + a4)];
    end
    if ~all(isfinite(state))
        error('nonlinear:Diverged', 'The motion grew without bound at t = %.4g.', t(k + 1));
    end
    y(k + 1, :) = [state 1];
    % Every 2 % of the run: a report costs more than a sample.
    if hasProgress && t(k + 1) >= nextReport * t(end)
        nextReport = nextReport + 0.02;
        if p.progressFcn(t(k + 1) / t(end))
            t = t(1:k + 1);
            y = y(1:k + 1, :);
            return
        end
    end
end
end

function r = rate(id, state, c)
% How fast the motion changes near STATE (1/time).
x = state(1);
v = state(2);
switch id
    case 1
        r = sqrt(abs(c(2) + 3 * c(3) * x^2)) + c(1);
    case 2
        r = sqrt(abs(1 + 2 * c(4) * x * v)) + c(4) * abs(1 - x^2);
    otherwise
        r = 1 + 1 / c(5) + abs(v);
end
r = max(r + c(7), 0.5);
end

function a = acceleration(id, time, x, v, c)
drive = c(6) * cos(c(7) * time);
switch id
    case 1
        a = drive - c(1) * v - c(2) * x - c(3) * x^3;
    case 2
        a = drive + c(4) * (1 - x^2) * v - x;
    otherwise
        a = drive - v / c(5) - sin(x);
end
end

% ------------------------------------------------------------------ model
function dy = rhs(time, y, p, model)
x = y(1);
v = y(2);
drive = p.A * cos(p.omega * time);
switch model
    case 'duffing'
        a = drive - p.delta * v - p.alpha * x - p.beta * x^3;
    case 'vanderpol'
        a = drive + p.mu * (1 - x^2) * v - x;
    otherwise
        a = drive - v / p.q - sin(x);
end
dy = [v; a];
end

function [V, E] = energyOf(p, model, x, v)
% V captures only its coefficients (not p, whose progress callback holds
% the app: a saved result would carry it).
switch model
    case 'duffing'
        alpha = p.alpha;
        beta = p.beta;
        V = @(s) alpha * s.^2 / 2 + beta * s.^4 / 4;
    case 'pendulum'
        V = @(s) 1 - cos(s);
    otherwise
        V = [];
end
if isempty(V)
    E = [];
else
    E = v.^2 / 2 + V(x);
end
end

% -------------------------------------------------------------- analysis
function [section, times] = maxima(t, x, v, f, rateOf, steady)
% States where v crosses zero from above. The output interval holding the
% crossing is integrated again in fine Runge–Kutta substeps (at least 32,
% and step × rate ≤ 0.05: a relaxation oscillation's jump can be much
% shorter than an output step); in the substep holding it, cubic Hermite
% interpolation of v (with the acceleration as its slope), refined by
% Newton's method.
k = find(steady(1:end-1) & v(1:end-1) > 0 & v(2:end) <= 0);
section = zeros(numel(k), 2);
times = zeros(numel(k), 1);
for j = 1:numel(k)
    i = k(j);
    span = t(i + 1) - t(i);
    fastest = max(rateOf([x(i), v(i)]), rateOf([x(i + 1), v(i + 1)]));
    substeps = max(32, ceil(span * fastest / 0.05));
    h = span / substeps;
    t0 = t(i);
    y0 = [x(i); v(i)];
    d0 = f(t0, y0);
    for m = 1:substeps
        y1 = rk4(f, t0, y0, h);
        d1 = f(t0 + h, y1);
        if y1(2) <= 0 || m == substeps
            break
        end
        [t0, y0, d0] = deal(t0 + h, y1, d1);
    end
    s = y0(2) / max(y0(2) - y1(2), realmin);           % linear guess
    for iteration = 1:8
        [vs, dvs] = hermite(s, y0(2), y1(2), h * d0(2), h * d1(2));
        if dvs == 0
            break
        end
        s = min(max(s - vs / dvs, 0), 1);
    end
    times(j) = t0 + s * h;
    section(j, 1) = hermite(s, y0(1), y1(1), h * y0(2), h * y1(2));
end
end

function y = rk4(f, t, y, h)
k1 = f(t, y);
k2 = f(t + h / 2, y + h / 2 * k1);
k3 = f(t + h / 2, y + h / 2 * k2);
k4 = f(t + h, y + h * k3);
y = y + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
end

function [value, slope] = hermite(s, y0, y1, m0, m1)
% Cubic Hermite on [0, 1] with end slopes m0, m1 (already scaled by h).
h00 = 2 * s^3 - 3 * s^2 + 1;
h10 = s^3 - 2 * s^2 + s;
h01 = -2 * s^3 + 3 * s^2;
h11 = s^3 - s^2;
value = h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1;
slope = (6 * s^2 - 6 * s) * y0 + (3 * s^2 - 4 * s + 1) * m0 + (-6 * s^2 + 6 * s) * y1 + (3 * s^2 - 2 * s) * m1;
end

function s = spreadOf(points, periodic)
% The largest range of the section coordinates (θ as an arc on the circle).
s = 0;
if size(points, 1) < 2
    return
end
ranges = max(points, [], 1) - min(points, [], 1);
if periodic
    sorted = sort(points(:, 1));
    gaps = [diff(sorted); sorted(1) + 2 * pi - sorted(end)];
    ranges(1) = 2 * pi - max(gaps);
end
s = max(ranges);
end

function count = clusters(points, tolerance, periodic)
% Greedy clustering: a point joins the first cluster within TOLERANCE.
count = 0;
if isempty(points)
    return
end
centers = zeros(0, 2);
for k = 1:size(points, 1)
    if isempty(centers)
        centers = points(k, :);
        continue
    end
    d = abs(centers - points(k, :));
    if periodic
        d(:, 1) = min(d(:, 1), 2 * pi - d(:, 1));
    end
    if ~any(max(d, [], 2) <= tolerance)
        centers(end + 1, :) = points(k, :); %#ok<AGROW>
        if size(centers, 1) > 1000
            break
        end
    end
end
count = size(centers, 1);
end

function [spectrum, dominant] = spectrumOf(t, x)
% The amplitude spectrum and its refined peak, in rad/s; none for fewer
% than 16 samples.
spectrum = struct('omega', zeros(0, 1), 'magnitude', zeros(0, 1));
dominant = NaN;
if numel(x) < 16
    return
end
[frequency, spectrum.magnitude, peak] = dlab.physics.amplitudeSpectrum(t, x);
spectrum.omega = 2 * pi * frequency;
dominant = 2 * pi * peak;
end

function a = wrapAngle(a)
a = mod(a + pi, 2 * pi) - pi;
a(a == -pi) = pi;
end

function validate(p)
switch lower(p.model)
    case 'duffing'
        ok = p.delta >= 0;
    case 'vanderpol'
        ok = p.mu >= 0;
    case 'pendulum'
        ok = p.q > 0;
    otherwise
        error('nonlinear:InvalidParameter', 'Unknown model "%s".', p.model);
end
if ~ok
    error('nonlinear:InvalidParameter', 'Damping must not be negative (q must be positive).');
end
if ~(p.omega >= 0 && p.samplesPerPeriod >= 8 && p.transient >= 0 && p.transient <= 0.95)
    error('nonlinear:InvalidParameter', 'Check the forcing frequency, samples per period, and transient.');
end
if p.A ~= 0 && p.omega > 0
    if ~(p.periods >= 1)
        error('nonlinear:InvalidParameter', 'Run at least one forcing period.');
    end
    if round(p.periods) * p.samplesPerPeriod > 2e6
        error('nonlinear:InvalidParameter', 'Too many samples: use fewer periods or samples per period.');
    end
elseif ~(p.tspan > 0)
    error('nonlinear:InvalidParameter', 'The duration must be positive.');
elseif p.tspan / (2 * pi / p.samplesPerPeriod) > 2e6
    error('nonlinear:InvalidParameter', 'Too many samples: use a shorter duration or fewer samples per period.');
end
end
