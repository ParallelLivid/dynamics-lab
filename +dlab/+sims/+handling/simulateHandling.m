function result = simulateHandling(p)
%SIMULATEHANDLING A car's yaw and sideslip response to steering.
%   result = simulateHandling(p) integrates the single-track (bicycle)
%   model at constant forward speed V (dlab.sims.handling.dynamics) with
%   the global position and heading (x forward at the start, y to the
%   left):
%
%     X' = V cos ψ − v sin ψ     Y' = V sin ψ + v cos ψ     ψ' = r
%
%   using ode45 (relative tolerance 1e-8). The run stops early when the
%   sideslip angle β = atan(v / V) passes spinLimit: the car has spun, and
%   the model (constant speed, small angles) no longer holds.
%
%   Fields: m (kg), Iz (kg·m²), a, b (m, centre of mass to the front and
%   rear axles), Cf, Cr (N/rad, cornering stiffness per axle), V (m/s),
%   tyre ('linear' | 'saturating'), mu, g, steer (a function of time
%   giving the road-wheel angle in rad, vectorized), tspan, dt; optional
%   spinLimit (rad, default 30°) and progressFcn.
%
%   result: t, v, r, beta, x, y, psi, delta, alphaF, alphaR, Ff, Fr, ay
%   (m/s²), the linear model (A, B, understeerGradient, yawGain,
%   characteristicSpeed, criticalSpeed, poles, stable), rSteady (the
%   linear steady-state yaw rate for the steering at each time, NaN when
%   unstable), axle loads Fzf and Fzr, gainCurve (speeds V in m/s and the
%   linear r/δ, NaN above the critical speed), and termination
%   ("completed" | "spun").
validate(p);
spinLimit = deg2rad(30);
if isfield(p, 'spinLimit') && ~isempty(p.spinLimit)
    spinLimit = p.spinLimit;
end
[A, B, info] = dlab.sims.handling.linearModel(p);

t = (0:p.dt:p.tspan)';
if t(end) < p.tspan - 1e-12 * p.tspan
    t(end + 1) = p.tspan;
end
s0 = zeros(5, 1);
options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, 'MaxStep', min(0.02, p.dt), ...
    'Events', @(~, s) spin(s, p.V, spinLimit));
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, [0 p.tspan]));
end
[tOut, s, tEvent, sEvent] = ode45(@(time, s) rhs(time, s, p), t, s0, options);
termination = "completed";
if ~isempty(tEvent)
    termination = "spun";
    if tOut(end) < tEvent(end)
        tOut(end + 1) = tEvent(end);
        s(end + 1, :) = sEvent(end, :);
    end
end

delta = p.steer(tOut(:)');
[~, f] = dlab.sims.handling.dynamics(s(:, 1:2)', delta, p);
L = p.a + p.b;

result.t = tOut;
result.v = s(:, 1);
result.r = s(:, 2);
result.beta = atan(s(:, 1) / p.V);
result.x = s(:, 3);
result.y = s(:, 4);
result.psi = s(:, 5);
result.delta = delta(:);
result.alphaF = f.alphaF(:);
result.alphaR = f.alphaR(:);
result.Ff = f.Ff(:);
result.Fr = f.Fr(:);
result.ay = f.ay(:);
result.A = A;
result.B = B;
result.understeerGradient = info.understeerGradient;
result.yawGain = info.yawGain;
result.characteristicSpeed = info.characteristicSpeed;
result.criticalSpeed = info.criticalSpeed;
result.poles = info.poles;
result.stable = info.stable;
result.rSteady = info.yawGain * result.delta;
result.Fzf = p.m * p.g * p.b / L;
result.Fzr = p.m * p.g * p.a / L;
result.gainCurve = gainCurve(p.V, L, info);
result.termination = termination;
end

function ds = rhs(time, s, p)
delta = p.steer(time);
dvr = dlab.sims.handling.dynamics(s(1:2), delta, p);
c = cos(s(5));
sn = sin(s(5));
ds = [dvr; p.V * c - s(1) * sn; p.V * sn + s(1) * c; s(2)];
end

function [value, terminal, direction] = spin(s, V, limit)
value = limit - abs(atan(s(1) / V));
terminal = 1;
direction = -1;
end

function curve = gainCurve(V, L, info)
% r/δ = V / (L + K V²) over a range of speeds that shows its shape.
K = info.understeerGradient;
top = max([2 * V, 40, 1.6 * info.characteristicSpeed, 1.6 * info.criticalSpeed], [], 'omitnan');
speeds = linspace(0, top, 400)';
gain = speeds ./ (L + K * speeds.^2);
if K < 0
    gain(speeds >= info.criticalSpeed) = NaN;
end
curve = struct('V', speeds, 'gain', gain);
end

function validate(p)
names = {'m', 'Iz', 'a', 'b', 'Cf', 'Cr', 'V', 'g', 'tspan', 'dt'};
for k = 1:numel(names)
    value = p.(names{k});
    if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && value > 0)
        error('handling:InvalidParameter', '%s must be a positive number.', names{k});
    end
end
if ~any(strcmpi(p.tyre, {'linear', 'saturating'}))
    error('handling:InvalidParameter', 'Unknown tyre model "%s" (use linear or saturating).', p.tyre);
end
if strcmpi(p.tyre, 'saturating') && ~(isscalar(p.mu) && isfinite(p.mu) && p.mu > 0)
    error('handling:InvalidParameter', 'The friction coefficient must be positive.');
end
if ~isa(p.steer, 'function_handle')
    error('handling:InvalidParameter', 'steer must be a function of time (rad).');
end
if p.dt >= p.tspan
    error('handling:InvalidParameter', 'The output step must be shorter than the duration.');
end
end
