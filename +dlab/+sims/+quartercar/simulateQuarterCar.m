function result = simulateQuarterCar(p)
%SIMULATEQUARTERCAR Quarter-car suspension driving over a road.
%   result = simulateQuarterCar(p): a body (sprung mass ms) on a spring ks
%   and damper cs above a wheel (unsprung mass mu) on a tire (spring kt,
%   damper ct), driving at speed V (m/s) over p.road (see roadProfile).
%   Displacements are from static equilibrium:
%
%     ms zs'' = −ks (zs − zu) − cs (zs' − zu')
%     mu zu'' =  ks (zs − zu) + cs (zs' − zu') + (F − W)
%     F = W − kt (zu − zr) − ct (zu' − zr')     tire contact force, W the static load
%
%   With p.liftoff, the tire cannot pull the road (F ≥ 0) and the wheel
%   can leave it. Fields: ms mu ks cs kt ct (SI), V, road, liftoff,
%   tspan, dt, g, optional progressFcn.
%
%   result: t, zs, zu, zr, zsd, zud, bodyAccel, travel (zs − zu),
%   tireForce (F), staticLoad (W), airborne (logical: lifted off, only
%   with p.liftoff), pulling (logical: a negative tire load, only without
%   p.liftoff), frequencies (Hz,
%   undamped body bounce and wheel hop), and response (the linear
%   frequency responses to road height: f, body, travel, tire, accel).
validate(p);
W = (p.ms + p.mu) * p.g;
if p.tspan / p.dt > 2e6
    error('quartercar:TooManySamples', ...
        'This run asks for %.3g samples; lengthen the output step or shorten the run (at most 2 million).', ...
        p.tspan / p.dt);
end
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan - 1e-12 * p.tspan
    t(end + 1) = p.tspan;
end
progressFcn = [];
if isfield(p, 'progressFcn')
    progressFcn = p.progressFcn;
end
[t, x] = integrate(p, W, t, progressFcn);
[zr, zrd] = roadState(p.road, p.V, t);
[d, F] = rhsAll(x, p, W, zr, zrd);

result.t = t;
result.zs = x(:, 1);
result.zsd = x(:, 2);
result.zu = x(:, 3);
result.zud = x(:, 4);
result.zr = zr;
result.bodyAccel = d(:, 2);
result.travel = x(:, 1) - x(:, 3);
result.tireForce = F;
result.staticLoad = W;
result.airborne = p.liftoff & F <= 0;
result.pulling = ~p.liftoff & F < 0;
[result.frequencies, result.response] = linearAnalysis(p);
end

function [t, x] = integrate(p, W, t, progressFcn)
% Classical Runge–Kutta with a fixed step that divides every output
% interval. The road is evaluated at all stage times at once (it is known
% in advance), so each step is plain arithmetic. A cancel (progressFcn
% returning true) ends the run early.
x = zeros(numel(t), 4);
y = zeros(1, 4);
hMax = maxStep(p);
reported = 0;
for k = 1:numel(t) - 1
    span = t(k + 1) - t(k);
    n = ceil(span / hMax - 1e-9);
    h = span / n;
    times = t(k) + h * (0:2 * n)' / 2;           % steps and half steps
    [zr, zrd] = roadState(p.road, p.V, times);
    for j = 1:n
        a = 2 * j - 1;                            % index of the step's start
        k1 = rhsAll(y, p, W, zr(a), zrd(a));
        k2 = rhsAll(y + h / 2 * k1, p, W, zr(a + 1), zrd(a + 1));
        k3 = rhsAll(y + h / 2 * k2, p, W, zr(a + 1), zrd(a + 1));
        k4 = rhsAll(y + h * k3, p, W, zr(a + 2), zrd(a + 2));
        y = y + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
    end
    x(k + 1, :) = y;
    % Every 2 % of the run: a report costs about as much as a sample.
    if ~isempty(progressFcn) && t(k + 1) >= reported + 0.02 * t(end)
        reported = t(k + 1);
        if progressFcn(t(k + 1) / t(end))
            t = t(1:k + 1);
            x = x(1:k + 1, :);
            return
        end
    end
end
end

function [d, F] = rhsAll(x, p, W, zr, zrd)
% Derivatives for rows of states X (and the tire force).
zs = x(:, 1); zsd = x(:, 2); zu = x(:, 3); zud = x(:, 4);
F = W - p.kt * (zu - zr) - p.ct * (zud - zrd);
if p.liftoff
    F = max(F, 0);
end
suspension = p.ks * (zs - zu) + p.cs * (zsd - zud);
d = [zsd, -suspension / p.ms, zud, (suspension + F - W) / p.mu];
end

function [zr, zrd] = roadState(road, V, time)
[zr, slope] = dlab.sims.quartercar.roadProfile(road, V * time(:));
zrd = V * slope;
end

function h = maxStep(p)
% Resolve the road's features, the fastest mode, and stay inside the
% Runge–Kutta stability region for stiff damping.
features = Inf;
switch lower(p.road.type)
    case {'bump', 'pothole'}
        features = p.road.length / max(p.V, eps) / 20;
    case 'step'
        features = 0.05 / max(p.V, eps) / 10;
    case 'sine'
        features = p.road.wavelength / max(p.V, eps) / 40;
    case 'random'
        features = 1 / (2.83 * max(p.V, eps)) / 20;
end
M = diag([p.ms p.mu]);
K = [p.ks -p.ks; -p.ks p.ks + p.kt];
C = [p.cs -p.cs; -p.cs p.cs + p.ct];
A = [zeros(2) eye(2); -M \ K, -M \ C];
fastest = max(abs(eig(A)));
h = min([features, 0.15 / fastest, p.dt]);
steps = p.tspan / h;
if steps > 5e6
    if h == features
        cause = 'shorten the run, or lengthen the road''s features';
    else
        cause = 'shorten the run, or soften the tire and damper';
    end
    error('quartercar:TooStiff', 'This car needs %.3g time steps; %s.', steps, cause);
end
end

function [frequencies, response] = linearAnalysis(p)
% Undamped natural frequencies and the frequency responses to road height.
M = diag([p.ms p.mu]);
K = [p.ks -p.ks; -p.ks p.ks + p.kt];
C = [p.cs -p.cs; -p.cs p.cs + p.ct];
frequencies = sort(sqrt(eig(K, M))) / (2 * pi);
f = logspace(-1, log10(30), 400)';
response = struct('f', f, 'body', zeros(size(f)), 'travel', zeros(size(f)), 'tire', zeros(size(f)), ...
    'accel', zeros(size(f)));
for k = 1:numel(f)
    w = 2 * pi * f(k);
    X = (-w^2 * M + 1i * w * C + K) \ [0; p.kt + 1i * w * p.ct];
    response.body(k) = abs(X(1));
    response.travel(k) = abs(X(1) - X(2));
    response.tire(k) = abs((p.kt + 1i * w * p.ct) * (1 - X(2))) / p.kt;
    response.accel(k) = w^2 * abs(X(1));
end
end

function validate(p)
names = {'ms', 'mu', 'ks', 'kt', 'tspan', 'dt', 'g'};
for k = 1:numel(names)
    v = p.(names{k});
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        error('quartercar:InvalidParameter', '%s must be a positive number.', names{k});
    end
end
if ~(p.cs >= 0 && p.ct >= 0 && p.V >= 0)
    error('quartercar:InvalidParameter', 'Damping and speed cannot be negative.');
end
if p.dt >= p.tspan
    error('quartercar:InvalidParameter', 'The output step must be shorter than the duration.');
end
end
