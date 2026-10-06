function result = propagateBurns(p, plan)
%PROPAGATEBURNS Fly a maneuver plan: two-body coasting between impulsive
%   burns. Each burn waits for its trigger (a time after the previous
%   burn, or the n-th periapsis, apoapsis, ascending node, or descending
%   node after it, located by ode45 events) and changes the velocity by
%   its Δv in the local frame: prograde (along v), normal (along r × v),
%   and radial (outward, completing the frame).
%
%   p: mu, R, sampleStep (s), coastAfter (orbits of the final orbit after
%   the last burn), optional progressFcn (@(fraction) stop; a cancel
%   errors with maneuvers:Cancelled). plan: from planManeuver.
%
%   result: t, r, v (n×3, km and km/s), elements (n×3: a, e, i in km, -,
%   deg), burnLog (struct array: time, r, v (before), dvLocal, dvInertial,
%   label), final (a, e, i), target (for phasing: its positions n×3, and
%   miss, the distance at the rendezvous), and crashed (true if the path
%   went below the surface).
mu = p.mu;
inc = deg2rad(plan.inc1);
r0 = plan.r1 * [1 0 0];
v0 = sqrt(mu / plan.r1) * [0 cos(inc) sin(inc)];
state = [r0 v0];
now = 0;
T = zeros(0, 1);
S = zeros(0, 6);
burnLog = struct('time', {}, 'r', {}, 'v', {}, 'dvLocal', {}, 'dvInertial', {}, 'label', {});
options = odeset('RelTol', 1e-11, 'AbsTol', 1e-9);
f = @(~, s) [s(4:6); -mu * s(1:3) / norm(s(1:3))^3];
total = numel(plan.burns) + 1;
progress = struct('fcn', [], 'fraction', 0);
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    progress.fcn = p.progressFcn;
end
for k = 1:numel(plan.burns)
    b = plan.burns(k);
    progress.fraction = (k - 1) / total;
    if strcmp(b.at, 'time')
        [T, S, state, now] = coast(f, T, S, state, now, now + b.value, p.sampleStep, options, [], progress);
    else
        for occurrence = 1:round(b.value)
            % Step off the current point so the same event is not found again.
            [T, S, state, now] = coast(f, T, S, state, now, now + 1, p.sampleStep, options, [], progress);
            horizon = now + min(2 * orbitPeriod(state, mu), 1e7);
            [T, S, state, now] = coast(f, T, S, state, now, horizon, p.sampleStep, options, b.at, progress);
        end
    end
    r = state(1:3);
    v = state(4:6);
    [prograde, normal, radial] = localFrame(r, v);
    dv = b.dv(1) * prograde + b.dv(2) * normal + b.dv(3) * radial;
    burnLog(end + 1) = struct('time', now, 'r', r, 'v', v, 'dvLocal', b.dv, 'dvInertial', dv, ...
        'label', b.label); %#ok<AGROW>
    state(4:6) = v + dv;
    report(progress, k / total);
end
progress.fraction = numel(plan.burns) / total;
period = orbitPeriod(state, mu);
if isfinite(period)
    [T, S] = coast(f, T, S, state, now, now + max(p.coastAfter, 0.01) * period, p.sampleStep, options, [], progress);
else
    [T, S] = coast(f, T, S, state, now, now + 86400, p.sampleStep, options, [], progress);
end

result.t = T;
result.r = S(:, 1:3);
result.v = S(:, 4:6);
n = numel(T);
elements = zeros(n, 3);
for k = 1:n
    e = dlab.physics.cart2kep(S(k, 1:3), S(k, 4:6), mu);
    elements(k, :) = [e(1), e(2), rad2deg(e(3))];
end
result.elements = elements;
result.burnLog = burnLog;
result.final = struct('a', elements(end, 1), 'e', elements(end, 2), 'i', elements(end, 3));
result.crashed = any(sqrt(sum(S(:, 1:3).^2, 2)) < p.R);
result.target = [];
result.miss = NaN;
if ~isnan(plan.phasing.angle)
    % The target: the same circular orbit, phaseAngle ahead.
    w = sqrt(mu / plan.r1^3);
    angle = deg2rad(plan.phasing.angle) + w * T;
    result.target = plan.r1 * [cos(angle), cos(inc) * sin(angle), sin(inc) * sin(angle)];
    at = burnLog(end).time;                       % the second burn: the rendezvous
    chaser = burnLog(end).r;
    angle = deg2rad(plan.phasing.angle) + w * at;
    result.miss = norm(chaser - plan.r1 * [cos(angle), cos(inc) * sin(angle), sin(inc) * sin(angle)]);
end
end

function [T, S, state, now] = coast(f, T, S, state, from, to, step, options, event, progress)
% Integrate from FROM to TO (or to EVENT), appending samples every STEP.
% A cancel (PROGRESS.fcn returning true) stops the solver and errors with
% maneuvers:Cancelled.
if to <= from
    if isempty(T)
        [T, S] = deal(from, state(:)');
    end
    now = from;
    return
end
times = [from, (ceil(from / step) * step:step:to), to];
times = unique(times);
if numel(times) == 2
    times = [from, (from + to) / 2, to];
end
if ~isempty(progress.fcn)
    options = odeset(options, 'OutputFcn', @(~, ~, flag) isempty(flag) && progress.fcn(progress.fraction));
end
tEvent = [];
if isempty(event)
    % Without an Events function, ode45 does not assign the event outputs.
    [t, s] = ode45(f, times, state(:), options);
else
    options = odeset(options, 'Events', @(~, s) trigger(s, event));
    [t, s, tEvent, sEvent] = ode45(f, times, state(:), options);
end
if isempty(tEvent) && t(end) < to
    report(progress, progress.fraction);
    error('maneuvers:Integration', 'The orbit could not be integrated past t = %.6g s.', t(end));
end
if ~isempty(event)
    if isempty(tEvent)
        error('maneuvers:NoEvent', 'The %s never came within two orbits.', event);
    end
    keep = t < tEvent(end);
    t = [t(keep); tEvent(end)];
    s = [s(keep, :); sEvent(end, :)];
end
if ~isempty(T) && t(1) == T(end)
    t = t(2:end);
    s = s(2:end, :);
end
T = [T; t];
S = [S; s];
state = s(end, :);
now = t(end);
end

function [value, terminal, direction] = trigger(s, event)
terminal = 1;
switch event
    case 'periapsis'
        value = s(1:3)' * s(4:6);      % r·v rises through zero at periapsis
        direction = 1;
    case 'apoapsis'
        value = s(1:3)' * s(4:6);
        direction = -1;
    case 'ascending'
        value = s(3);
        direction = 1;
    otherwise                          % descending node
        value = s(3);
        direction = -1;
end
end

function [prograde, normal, radial] = localFrame(r, v)
prograde = v / norm(v);
normal = cross(r, v);
normal = normal / norm(normal);
radial = cross(prograde, normal);       % outward for a circular orbit
end

function T = orbitPeriod(state, mu)
r = norm(state(1:3));
energy = 0.5 * norm(state(4:6))^2 - mu / r;
if energy >= 0
    T = inf;
else
    a = -mu / (2 * energy);
    T = 2 * pi * sqrt(a^3 / mu);
end
end

function report(progress, fraction)
% Report progress; error with maneuvers:Cancelled once the user cancels.
if ~isempty(progress.fcn) && progress.fcn(fraction)
    error('maneuvers:Cancelled', 'The maneuver was cancelled.');
end
end
