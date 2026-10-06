function result = simulateQuadrotor(p)
%SIMULATEQUADROTOR Rigid-body quadrotor with a cascaded flight controller.
%   result = simulateQuadrotor(p) integrates dlab.sims.quadrotor.closedLoop
%   (ode45, RelTol 1e-8, MaxStep 0.01 s) and stops early when the
%   quadrotor reaches the ground (z = 0): "crashed" if it hits faster than
%   crashSpeed, else "landed".
%
%   Fields of p:
%     airframe    m, L (centre to rotor), Ixx, Iyy, Izz, kf (N/(rad/s)²),
%                 km (N·m/(rad/s)²), tauMotor (s), Tmax (N per rotor),
%                 kd (drag, N·s²/m²), g
%     controller  'position' | 'attitude' | 'off'; KpXY, KdXY, KiXY, KpZ,
%                 KdZ, KiZ (outer loop, per unit mass: 1/s², 1/s, 1/s³);
%                 KrRP, KwRP, KrYaw, KwYaw (inner loop: 1/s², 1/s);
%                 maxTilt (rad); band (m, the integrals run only this close);
%                 aIntMax (m/s², the most the integrals may add);
%                 offThrust (fraction of hover thrust per rotor, mode off)
%     mission     'setpoint': reference, @(t) [x; y; z; yaw] (or 7 values
%                 with the setpoint velocity); 'waypoints': waypoints (N×5
%                 [x y z yaw hold], yaw in rad) and cruiseSpeed (m/s), flown
%                 from the start (see missionPath)
%     attitude    attitudeCommand, @(t) [roll; pitch] (rad), for 'attitude'
%     wind        @(t) 3×1 wind velocity (m/s), or [] for still air
%     start       pos0 (3), vel0 (3), euler0 (3: roll, pitch, yaw, rad),
%                 omega0 (3, body rates, rad/s)
%     failure     failRotor (0 none, 1–4), failTime (s), failScale (the
%                 fraction of thrust that rotor keeps)
%     run         crashSpeed (m/s), tEnd, dt (output step), optional
%                 progressFcn
%
%   result: t; pos, vel (n×3); quat (n×4); euler (n×3: roll, pitch, yaw
%   unwrapped, rad); attitudeCmd (n×3, the inner loop's target); omega
%   (n×3); integral (n×3); rotorSpeed, thrust, thrustCmd (n×4); saturated
%   (n×1); reference (n×4: x y z yaw); tilt (n×1, rad); termination
%   ("completed" | "crashed" | "landed"); contactSpeed; hoverThrust;
%   hoverSpeed; thrustToWeight; stats (see below); path (waypoints only);
%   model; ctrl; plus failRotor, failTime, failScale, mission, controller.
%
%   stats: finalError (m), maxTilt (rad), settlingTime (s after the last
%   setpoint change until the position stays within 5 % of the move, at
%   least 2 cm; NaN if there was no move or it never settled), overshoot
%   (% of the move, setpoint missions only), peakThrust (N),
%   timeSaturated (s), maxYawRate (rad/s).
validate(p);
[model, ctrl] = dlab.sims.quadrotor.airframe(p);

path = [];
if strcmpi(p.mission, 'waypoints')
    path = dlab.sims.quadrotor.missionPath(p.pos0, p.euler0(3), p.waypoints, p.cruiseSpeed);
    reference = path.fcn;
else
    reference = @(t) padReference(p.reference(t));
end
attitude = @(t) [0; 0];
if ctrl.mode == 2
    attitude = p.attitudeCommand;
end
wind = @(t) zeros(3, 1);
if isfield(p, 'wind') && ~isempty(p.wind)
    wind = p.wind;
end
eta = @(t) thrustScale(t, p);

if ctrl.mode == 3
    speed0 = sqrt(ctrl.offThrust / model.kf);
else
    speed0 = model.hoverSpeed;
end
e = p.euler0;
s0 = [p.pos0(:); p.vel0(:); dlab.physics.Quaternion.fromEuler(e(1), e(2), e(3)); p.omega0(:); ...
    zeros(3, 1); speed0 * ones(4, 1)];
rhs = @(t, s) dlab.sims.quadrotor.closedLoop(s, reference(t), attitude(t), eta(t), wind(t), ...
    zeros(3, 1), model, ctrl);

tspan = (0:p.dt:p.tEnd)';
if tspan(end) < p.tEnd
    tspan(end + 1) = p.tEnd;
end
options = odeset('RelTol', 1e-8, 'AbsTol', 1e-9, 'MaxStep', 0.01, 'Events', @ground);
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, tspan));
end
[t, s, tEvent, sEvent] = ode45(rhs, tspan, s0, options);

termination = "completed";
contactSpeed = NaN;
if ~isempty(tEvent) && tEvent(end) > 0
    if t(end) < tEvent(end)
        t(end + 1) = tEvent(end);
        s(end + 1, :) = sEvent(end, :);
    end
    contactSpeed = norm(sEvent(end, 4:6));
    termination = "landed";
    if contactSpeed > p.crashSpeed
        termination = "crashed";
    end
end

n = numel(t);
quat = s(:, 7:10) ./ vecnorm(s(:, 7:10), 2, 2);
[thrust, thrustCmd] = deal(zeros(n, 4));
saturated = false(n, 1);
reference4 = zeros(n, 4);
attitudeCmd = zeros(n, 3);
for k = 1:n
    r = reference(t(k));
    [~, out] = dlab.sims.quadrotor.closedLoop(s(k, :)', r, attitude(t(k)), eta(t(k)), wind(t(k)), ...
        zeros(3, 1), model, ctrl);
    thrust(k, :) = out.thrust';
    thrustCmd(k, :) = out.thrustCmd';
    saturated(k) = out.saturated;
    reference4(k, :) = r(1:4)';
    attitudeCmd(k, :) = eulerOf(out.qd);
end
euler = zeros(n, 3);
for k = 1:n
    euler(k, :) = eulerOf(quat(k, :)');
end
euler(:, 3) = unwrap(euler(:, 3));
attitudeCmd(:, 3) = unwrap(attitudeCmd(:, 3));
tilt = acos(min(max(1 - 2 * (quat(:, 2).^2 + quat(:, 3).^2), -1), 1));

result.t = t;
result.pos = s(:, 1:3);
result.vel = s(:, 4:6);
result.quat = quat;
result.euler = euler;
result.attitudeCmd = attitudeCmd;
result.omega = s(:, 11:13);
result.integral = s(:, 14:16);
result.rotorSpeed = s(:, 17:20);
result.thrust = thrust;
result.thrustCmd = thrustCmd;
result.saturated = saturated;
result.reference = reference4;
result.tilt = tilt;
result.termination = termination;
result.contactSpeed = contactSpeed;
result.hoverThrust = model.hoverThrust;
result.hoverSpeed = model.hoverSpeed;
result.thrustToWeight = 4 * model.Tmax / (model.m * model.g);
result.path = path;
result.model = model;
result.ctrl = ctrl;
result.mission = lower(string(p.mission));
result.controller = lower(string(p.controller));
result.failRotor = p.failRotor;
result.failTime = p.failTime;
result.failScale = p.failScale;
result.stats = statistics(result);
end

function r = padReference(r)
r = r(:);
if numel(r) == 4
    r = [r; 0; 0; 0];
end
end

function eta = thrustScale(t, p)
eta = ones(4, 1);
if p.failRotor > 0 && t >= p.failTime
    eta(p.failRotor) = p.failScale;
end
end

function [value, terminal, direction] = ground(~, s)
value = s(3) + 1e-9;           % (a start on the ground is not a contact)
terminal = 1;
direction = -1;
end

function e = eulerOf(q)
% Roll, pitch, yaw (3-2-1) of a unit quaternion, as a row.
[w, x, y, z] = deal(q(1), q(2), q(3), q(4));
e = [atan2(2*(w*x + y*z), 1 - 2*(x^2 + y^2)), asin(min(max(2*(w*y - z*x), -1), 1)), ...
    atan2(2*(w*z + x*y), 1 - 2*(y^2 + z^2))];
end

function stats = statistics(r)
t = r.t;
target = r.reference(end, 1:3);
stats.finalError = norm(r.pos(end, :) - target);
stats.maxTilt = max(r.tilt);
stats.peakThrust = max(r.thrust, [], 'all');
stats.timeSaturated = sum(diff(t) .* r.saturated(1:end-1));
stats.maxYawRate = max(abs(r.omega(:, 3)));
stats.settlingTime = NaN;
stats.overshoot = NaN;
changed = find(any(abs(diff(r.reference(:, 1:3))) > 1e-12, 2), 1, 'last');
if isempty(changed)
    return
end
from = changed + 1;                        % the first sample at the final setpoint
move = target - r.pos(from, :);
distance = norm(move);
if distance < 1e-6
    return
end
band = max(0.05 * distance, 0.02);
miss = vecnorm(r.pos(from:end, :) - target, 2, 2);
if r.termination == "completed" && miss(end) <= band
    last = find(miss > band, 1, 'last');
    if isempty(last)
        stats.settlingTime = 0;
    else
        stats.settlingTime = t(from + last) - t(from);
    end
end
if distance > 0.1 && r.mission == "setpoint"
    along = (r.pos(from:end, :) - target) * (move' / distance);
    stats.overshoot = 100 * max(0, max(along)) / distance;
end
end

function validate(p)
positive = {'m', 'L', 'Ixx', 'Iyy', 'Izz', 'kf', 'tauMotor', 'Tmax', 'g', 'tEnd', 'dt', 'cruiseSpeed'};
for k = 1:numel(positive)
    name = positive{k};
    if isfield(p, name) && ~(isscalar(p.(name)) && p.(name) > 0 && isfinite(p.(name)))
        error('quadrotor:InvalidParameter', '%s must be a positive number.', name);
    end
end
nonnegative = {'km', 'kd', 'KpXY', 'KdXY', 'KiXY', 'KpZ', 'KdZ', 'KiZ', 'KrRP', 'KwRP', 'KrYaw', 'KwYaw', ...
    'band', 'aIntMax', 'offThrust', 'crashSpeed', 'failTime'};
for k = 1:numel(nonnegative)
    name = nonnegative{k};
    if ~(isscalar(p.(name)) && p.(name) >= 0)
        error('quadrotor:InvalidParameter', '%s cannot be negative.', name);
    end
end
if ~(p.maxTilt > 0 && p.maxTilt < pi / 2)
    error('quadrotor:InvalidParameter', 'The tilt limit must be between 0 and 90 degrees.');
end
if ~(any(p.failRotor == 0:4) && p.failScale >= 0 && p.failScale <= 1)
    error('quadrotor:InvalidParameter', 'The failed rotor is 0 (none) to 4, keeping 0 to 1 of its thrust.');
end
if p.pos0(3) < 0
    error('quadrotor:InvalidParameter', 'The quadrotor must start on or above the ground (z ≥ 0).');
end
if ~any(strcmpi(p.mission, {'setpoint', 'waypoints'}))
    error('quadrotor:InvalidParameter', 'Unknown mission "%s" (setpoint or waypoints).', char(p.mission));
end
end
