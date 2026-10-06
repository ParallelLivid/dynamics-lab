function result = simulateAttitude(p)
%SIMULATEATTITUDE Rigid spacecraft with three reaction wheels and thrusters.
%   result = simulateAttitude(p) integrates Euler's equations with wheel
%   momentum and an attitude quaternion (scalar first, body to world):
%
%     I ω' = −ω × (I ω + h) − τ_w + τ_thr + τ_d      h' = τ_w
%     q'   = ½ q ⊗ [0; ω]
%
%   h is the momentum of three reaction wheels along the body axes, τ_w
%   the torque the motors put on the wheels (the body feels −τ_w), τ_thr
%   the thruster torque, and τ_d a constant disturbance torque (body axes).
%
%   p.mode (control law; wheels unless noted):
%     'free'      no control: torque-free tumbling (wheels idle)
%     'detumble'  rate damping, body torque τ = −Kd ω
%     'slew'      quaternion PD to p.qTarget:
%                 τ = −Kp · 2 sign(q_e0) q_e,vec − Kd ω,  q_e = q_target⁻¹ ⊗ q
%                 (2 q_e,vec is the error angle for small errors, so the
%                 gains are per radian: one axis is I θ'' + Kd θ' + Kp θ = 0)
%     'hold'      the same law (give qTarget = q0 to hold the start attitude)
%     'bangbang'  rest-to-rest eigenaxis slew on the thrusters: angular
%                 acceleration α along the eigenaxis e for half the angle,
%                 then −α. The thrusters (throttled) give I α e plus the
%                 gyroscopic torque ω × (I ω + h), with
%                 α = thrust / max_i(I_i |e_i| + θ |(e × I e)_i|) so that
%                 no axis needs more than its thrust; the wheels' PD holds
%                 the target afterwards. One axis: t = 2 √(θ I / thrust).
%   Body torque requests are met by the wheels within ±tauMax each; a
%   wheel at ±hMax cannot take more momentum in that direction.
%
%   Fields: I (principal inertias, kg·m²), omega0 (body rates, rad/s), q0,
%   qTarget (unit quaternions, any sign), mode, Kp (N·m/rad), Kd
%   (N·m·s/rad), tauMax (N·m), hMax (N·m·s), thrust (N·m per axis),
%   disturbance (1×3 N·m, body axes), tspan, dt (output step). Optional:
%   h0 (initial wheel momentum, default 0), dump (logical: momentum
%   dumping with thrusters in the wheel modes), dumpAt (fraction of hMax
%   where an axis starts dumping, default 0.8), dumpStop (where it stops,
%   default 0.1), dumpTorque (N·m), progressFcn (@(fraction) stop).
%
%   result: t, q (n×4), omega (n×3), h (n×3), euler (n×3, 3-2-1 roll,
%   pitch, yaw, rad), targetEuler (1×3), error (eigenaxis error angle,
%   rad), signedError (rad, along the initial error axis), tauWheel (n×3,
%   body torque from the wheels), tauCommand (n×3, the controller's
%   request), tauThruster (n×3), disturbance (1×3), saturated (n×3
%   logical, wheel at its limit), dumping (n×3 logical), axes (n×3×3,
%   world coordinates of body axes), targetAxes (3×3), energy (½ ωᵀIω),
%   H (n×3, inertial angular momentum of body and wheels), drift (energy,
%   H: largest relative changes; NaN when the start value is 0), plan (bang-bang: angle, axis, alpha,
%   switchTime, endTime), settleTime (error within 0.1° from then on,
%   NaN if not), finalError, maxError, maxRate, maxWheel, wheelFraction,
%   saturationTime (NaN if never), wasSaturated, impulse (thruster
%   ∫Σ|τ| dt), dumps, overshoot (% of the initial error, NaN without a
%   target), initialError, and the limits I, tauMax, hMax, mode.
p = withDefaults(p);
validate(p);
mode = lower(char(p.mode));
m = struct();
m.I = p.I(:);
m.Kp = p.Kp;
m.Kd = p.Kd;
m.tauMax = p.tauMax;
m.hMax = p.hMax;
m.dist = p.disturbance(:);
m.dumpTorque = p.dumpTorque;
m.dumpAt = p.dumpAt;
m.dumpStop = p.dumpStop;
m.thrust = p.thrust;
m.dump = logical(p.dump) && ismember(mode, {'detumble', 'slew', 'hold'});
m.qT = p.qTarget(:) / norm(p.qTarget);
switch mode
    case 'free'
        m.law = 'none';
    case 'detumble'
        m.law = 'damp';
    otherwise
        m.law = 'pd';
end

q0 = p.q0(:) / norm(p.q0);
omega0 = p.omega0(:);
h0 = p.h0(:);
tEnd = p.tspan;

% The bang-bang plan: rotate by the error angle about the eigenaxis.
plan = struct('angle', 0, 'axis', [0; 0; 1], 'alpha', 0, 'switchTime', 0, 'endTime', 0);
qe0 = dlab.physics.Quaternion.relative(m.qT, q0);
initialError = errorAngle(qe0);
if strcmp(mode, 'bangbang') && initialError > 1e-12
    v = signOf(qe0(1)) * qe0(2:4);
    plan.angle = initialError;
    plan.axis = -v / norm(v);
    % The thrusters also cancel the gyroscopic torque ω × I ω (largest at
    % the peak rate, ω² = θ α), so the rotation stays about e.
    gyro = abs(cross(plan.axis, m.I .* plan.axis));
    plan.alpha = p.thrust / max(m.I .* abs(plan.axis) + plan.angle * gyro);
    plan.switchTime = sqrt(plan.angle / plan.alpha);
    plan.endTime = 2 * plan.switchTime;
end
m.thrustAccel = plan.alpha * (m.I .* plan.axis);       % body torque while accelerating
boundaries = [plan.switchTime plan.endTime];
boundaries = boundaries(boundaries > 0);

baseOptions = odeset('RelTol', 1e-10, 'AbsTol', 1e-12);
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    baseOptions = odeset(baseOptions, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, [0 tEnd]));
end

ctx = struct('phase', 0, 'wheelsOn', true, 'sat', false(3, 1), 'dump', false(3, 1), 'satEvents', true);
state = [q0; omega0; h0; 0];
t0 = 0;
segments = struct('t0', {}, 't1', {}, 'sol', {}, 'ctx', {});
dumps = 0;
maxSegments = 4000;
while t0 < tEnd * (1 - 1e-12)
    [ctx.phase, tStop] = phaseAt(t0, boundaries, tEnd);
    ctx.wheelsOn = ctx.phase == 0 && ~strcmp(m.law, 'none');
    if numel(segments) >= maxSegments
        ctx.satEvents = false;           % chattering at a limit: the limit alone holds h
    end
    options = odeset(baseOptions, 'Events', @(~, y) events(y, ctx, m));
    sol = ode45(@(~, y) rhs(y, ctx, m), [t0 tStop], state, options);
    reached = sol.x(end);
    segments(end + 1) = struct('t0', t0, 't1', reached, 'sol', sol, 'ctx', ctx); %#ok<AGROW>
    state = sol.y(:, end);
    fired = [];
    if isfield(sol, 'xe') && ~isempty(sol.xe)
        fired = sol.ie(abs(sol.xe - reached) <= 1e-12 * max(1, reached));
    end
    if isempty(fired) && reached < tStop * (1 - 1e-12)
        tEnd = reached;                  % stopped by the progress monitor (Cancel)
        break
    end
    for k = unique(fired(:))'
        j = mod(k - 1, 3) + 1;
        if k <= 3
            if ctx.sat(j)
                ctx.sat(j) = false;
            else
                ctx.sat(j) = true;
                state(7 + j) = sign(state(7 + j)) * m.hMax;
            end
        else
            ctx.dump(j) = ~ctx.dump(j);
            dumps = dumps + ctx.dump(j);
        end
    end
    t0 = reached;
end

% Sample every segment on the output grid.
t = (0:p.dt:tEnd)';
if t(end) < tEnd
    t(end + 1) = tEnd;
end
if numel(t) < 3
    t = linspace(0, tEnd, 3)';
end
n = numel(t);
y = zeros(n, 11);
seg = zeros(n, 1);
for k = numel(segments):-1:1
    rows = seg == 0 & t >= segments(k).t0 - 1e-12 * max(1, tEnd);
    rows = rows & t <= segments(k).t1 + 1e-12 * max(1, tEnd);
    if any(rows)
        y(rows, :) = deval(segments(k).sol, min(max(t(rows), segments(k).t0), segments(k).t1))';
        seg(rows) = k;
    end
end

q = y(:, 1:4) ./ sqrt(sum(y(:, 1:4).^2, 2));
omega = y(:, 5:7);
h = y(:, 8:10);
[tauWheel, tauCommand, tauThruster] = deal(zeros(n, 3));
[saturated, dumping] = deal(false(n, 3));
euler = zeros(n, 3);
err = zeros(n, 1);
signedError = zeros(n, 1);
frames = zeros(n, 3, 3);
H = zeros(n, 3);
n0 = [0; 0; 0];
if initialError > 1e-12
    n0 = signOf(qe0(1)) * qe0(2:4) / norm(qe0(2:4));
end
for k = 1:n
    c = segments(seg(k)).ctx;
    [tauW, tauC, tauT] = actuators(q(k, :)', omega(k, :)', h(k, :)', c, m);
    tauWheel(k, :) = -tauW';
    tauCommand(k, :) = tauC';
    tauThruster(k, :) = tauT';
    saturated(k, :) = (c.sat | abs(h(k, :)') >= m.hMax * (1 - 1e-9))';
    dumping(k, :) = c.dump';
    [euler(k, 1), euler(k, 2), euler(k, 3)] = dlab.physics.Quaternion.toEuler(q(k, :)');
    qe = dlab.physics.Quaternion.relative(m.qT, q(k, :)');
    err(k) = errorAngle(qe);
    signedError(k) = 2 * atan2(signOf(qe(1)) * (qe(2:4)' * n0), abs(qe(1)));
    R = dlab.physics.Quaternion.toDcm(q(k, :)');
    frames(k, :, :) = reshape(R, 1, 3, 3);
    H(k, :) = (R * (m.I .* omega(k, :)' + h(k, :)'))';
end
[phi, theta, psi] = dlab.physics.Quaternion.toEuler(m.qT);
energy = 0.5 * sum(m.I' .* omega.^2, 2);

result.t = t;
result.q = q;
result.omega = omega;
result.h = h;
result.euler = euler;
result.targetEuler = [phi theta psi];
result.error = err;
result.signedError = signedError;
result.tauWheel = tauWheel;
result.tauCommand = tauCommand;
result.tauThruster = tauThruster;
result.disturbance = m.dist';
result.saturated = saturated;
result.dumping = dumping;
result.axes = frames;
result.targetAxes = dlab.physics.Quaternion.toDcm(m.qT);
result.energy = energy;
result.H = H;
% Relative changes; undefined (NaN) from rest, where there is nothing to compare with
% (it read 4e306 for a slew from rest).
result.drift.energy = relativeChange(max(abs(energy - energy(1))), abs(energy(1)));
result.drift.H = relativeChange(max(sqrt(sum((H - H(1, :)).^2, 2))), norm(H(1, :)));
result.plan = plan;
result.mode = string(mode);
result.I = m.I';
result.tauMax = m.tauMax;
result.hMax = m.hMax;
result.thrust = p.thrust;
result.initialError = initialError;
result.settleTime = settleTime(t, err, deg2rad(0.1));
result.finalError = err(end);
result.maxError = max(err);
result.maxRate = max(sqrt(sum(omega.^2, 2)));
result.maxWheel = max(abs(h(:)));
result.wheelFraction = result.maxWheel / m.hMax;
result.wasSaturated = any(saturated(:));
result.saturationTime = NaN;
if result.wasSaturated
    result.saturationTime = t(find(any(saturated, 2), 1));
end
result.impulse = y(end, 11);
result.dumps = dumps;
result.overshoot = NaN;
if ~strcmp(m.law, 'none') && ~strcmp(m.law, 'damp') && initialError > 1e-9
    result.overshoot = 100 * max(0, -min(signedError)) / initialError;
end
end

% ---------------------------------------------------------------- model
function dy = rhs(y, ctx, m)
q = y(1:4);
w = y(5:7);
h = y(8:10);
[tauW, ~, tauT] = actuators(q, w, h, ctx, m);
dw = (-cross(w, m.I .* w + h) - tauW + tauT + m.dist) ./ m.I;
dq = dlab.physics.Quaternion.derivative(q, w) + (1 - q' * q) * q;
dy = [dq; dw; tauW; sum(abs(tauT))];
end

function [tauW, tauC, tauT] = actuators(q, w, h, ctx, m)
% Wheel torque (on the wheels), the controller's body-torque request, and
% the thruster torque on the body.
tauC = zeros(3, 1);
if ctx.wheelsOn
    switch m.law
        case 'damp'
            tauC = -m.Kd * w;
        case 'pd'
            qe = dlab.physics.Quaternion.relative(m.qT, q);
            tauC = -m.Kp * 2 * signOf(qe(1)) * qe(2:4) - m.Kd * w;
    end
end
tauW = min(max(-tauC, -m.tauMax), m.tauMax);
for i = 1:3
    outward = tauW(i) * h(i) > 0;
    if outward && (ctx.sat(i) || abs(h(i)) >= m.hMax)
        tauW(i) = 0;
    end
end
tauT = zeros(3, 1);
if ctx.phase ~= 0
    tauT = ctx.phase * m.thrustAccel + cross(w, m.I .* w + h);
    tauT = min(max(tauT, -m.thrust), m.thrust);
end
if any(ctx.dump)
    tauT(ctx.dump) = tauT(ctx.dump) - m.dumpTorque * sign(h(ctx.dump));
end
end

function [value, terminal, direction] = events(y, ctx, m)
% 1–3: a wheel reaches its limit, or (saturated) the controller asks it to
% unload; 4–6: an axis starts or stops dumping momentum.
h = y(8:10);
value = ones(6, 1);
direction = zeros(6, 1);
terminal = true(6, 1);
if ~ctx.wheelsOn
    return
end
[~, tauC] = actuators(y(1:4), y(5:7), h, ctx, m);
request = min(max(-tauC, -m.tauMax), m.tauMax);
for i = 1:3
    if ctx.satEvents
        if ctx.sat(i)
            value(i) = request(i) * sign(h(i));
            direction(i) = -1;
        else
            value(i) = abs(h(i)) - m.hMax;
            direction(i) = 1;
        end
    end
    if m.dump
        if ctx.dump(i)
            value(3 + i) = abs(h(i)) - m.dumpStop * m.hMax;
            direction(3 + i) = -1;
        else
            value(3 + i) = abs(h(i)) - m.dumpAt * m.hMax;
            direction(3 + i) = 1;
        end
    end
end
end

function [phase, tStop] = phaseAt(t0, boundaries, tEnd)
% +1 accelerating, −1 braking (bang-bang thrusters), 0 wheels.
phase = 0;
tStop = tEnd;
tol = 1e-12 * max(1, tEnd);
if numel(boundaries) == 2 && t0 < boundaries(2) - tol
    if t0 < boundaries(1) - tol
        phase = 1;
        tStop = min(boundaries(1), tEnd);
    else
        phase = -1;
        tStop = min(boundaries(2), tEnd);
    end
end
end

% ---------------------------------------------------------------- helpers
function angle = errorAngle(qe)
% Eigenaxis angle of an error quaternion, 0 to π, the same for q and −q.
angle = 2 * atan2(norm(qe(2:4)), abs(qe(1)));
end

function s = signOf(x)
% sign with sign(0) = 1: at exactly 180° either way round is fine.
s = 1 - 2 * (x < 0);
end

function r = relativeChange(change, scale)
r = NaN;
if scale > 0
    r = change / scale;
end
end

function t = settleTime(time, err, band)
% When the error last left the band (NaN unless it ends inside), with the
% crossing interpolated between samples.
t = NaN;
if err(end) > band
    return
end
last = find(err > band, 1, 'last');
if isempty(last)
    t = 0;
    return
end
a = err(last) - band;
b = err(last + 1) - band;
t = time(last) + a / (a - b) * (time(last + 1) - time(last));
end

function p = withDefaults(p)
defaults = struct('h0', [0 0 0], 'dump', false, 'dumpAt', 0.8, 'dumpStop', 0.1, 'dumpTorque', 0.05, ...
    'thrust', 1, 'disturbance', [0 0 0], 'Kp', 0, 'Kd', 0, 'tauMax', Inf, 'hMax', Inf);
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(p, names{k}) || isempty(p.(names{k}))
        p.(names{k}) = defaults.(names{k});
    end
end
if ~isfield(p, 'qTarget') || isempty(p.qTarget)
    p.qTarget = p.q0;
end
end

function validate(p)
modes = {'free', 'detumble', 'slew', 'hold', 'bangbang'};
if ~any(strcmpi(char(p.mode), modes))
    error('attitude:InvalidParameter', 'Unknown mode "%s".', char(p.mode));
end
I = p.I;
if ~(numel(I) == 3 && all(I > 0) && all(isfinite(I)))
    error('attitude:InvalidParameter', 'The principal inertias must be positive.');
end
if any(I > I([2 3 1]) + I([3 1 2]) + 1e-12 * max(I))
    error('attitude:InvalidParameter', ...
        'No real body has these inertias: each must be at most the sum of the other two.');
end
if ~(numel(p.q0) == 4 && norm(p.q0) > 0 && numel(p.qTarget) == 4 && norm(p.qTarget) > 0)
    error('attitude:InvalidParameter', 'The attitudes must be nonzero quaternions [w x y z].');
end
if ~(numel(p.omega0) == 3 && all(isfinite(p.omega0)) && numel(p.h0) == 3 && numel(p.disturbance) == 3)
    error('attitude:InvalidParameter', 'The rates, wheel momenta, and disturbance need three components.');
end
if ~(p.Kp >= 0 && p.Kd >= 0)
    error('attitude:InvalidParameter', 'The gains Kp and Kd must not be negative.');
end
if ~(p.tauMax > 0 && p.hMax > 0)
    error('attitude:InvalidParameter', 'The wheel torque and momentum limits must be positive.');
end
if any(abs(p.h0) > p.hMax)
    error('attitude:InvalidParameter', 'The initial wheel momentum is beyond the wheel limit.');
end
if strcmpi(char(p.mode), 'bangbang') && ~(p.thrust > 0 && isfinite(p.thrust))
    error('attitude:InvalidParameter', 'A bang-bang slew needs a positive thruster torque.');
end
if p.dump && ~(p.dumpTorque > 0 && p.dumpAt > 0 && p.dumpAt <= 1 && p.dumpStop >= 0 && p.dumpStop < p.dumpAt)
    error('attitude:InvalidParameter', ...
        'Momentum dumping needs a positive torque and 0 ≤ stop level < start level ≤ 100 %%.');
end
if ~(p.tspan > 0 && p.dt > 0 && isfinite(p.tspan))
    error('attitude:InvalidParameter', 'The duration and output step must be positive.');
end
end
