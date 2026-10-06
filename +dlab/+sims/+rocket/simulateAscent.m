function result = simulateAscent(p)
%SIMULATEASCENT A multi-stage rocket flying from the ground toward orbit,
%   in the plane of its trajectory, over a spherical Earth.
%
%   States (inertial, Earth's centre at the origin, the pad at (0, R)):
%   x, y, vx, vy, mass, and four integrals for the Δv budget: gravity
%   loss −∫ g·v̂ dt, drag loss −∫ (D/m)·v̂ dt, steering loss
%   ∫ (T/m)(1 − t̂·v̂) dt, and the thrust Δv ∫ T/m dt. Along the velocity
%   v̂, d|v|/dt = T/m − (the three loss rates), so
%
%       ∫ T/m dt = |v|_end − |v|_start + gravity + drag + steering
%
%   holds to integration accuracy (and |v|_start is the Earth-rotation gain).
%
%   Fields:
%     stages      struct array or table: dry, prop (kg), thrust (vacuum, kN),
%                 ispVac, ispSl (s), delay (s of coasting before ignition)
%     payload     kg;  diameter (m);  cdScale (drag multiplier, 0 = no drag)
%     kickAltitude (m), kickAngle (deg): vertical rise, then a 5 s pitch-over,
%                 then a gravity turn (thrust along the air-relative velocity).
%                 With a finite target, upper stages instead control the climb
%                 rate toward the target altitude (pitching just enough), so
%                 the rest of their thrust builds horizontal speed.
%     pitchProgram  [] or @(t) flight-path angle (deg above the horizon) to
%                 steer by instead
%     throttle    @(t) in [0, 1]
%     targetApoapsis  km above the surface (Inf: burn everything); the last
%                 stage cuts off when the apoapsis reaches it (or, under the
%                 upper-stage climb guidance, when the orbital energy matches a
%                 circular orbit at that altitude). circularize
%                 (logical): an impulsive burn at that apoapsis, limited by the
%                 last stage's remaining propellant
%     latitude (deg), rotation (logical: start with the Earth's eastward
%                 speed, and the air turning with the Earth)
%     gravity     logical (true; false only for tests)
%     maxTime, dt (s): the time limit (after a cutoff, the coast to the
%                 apoapsis may pass it);  optional progressFcn
%
%   result: t, x, y, vx, vy, mass, h (altitude, m), downrange (m along
%   the surface), speed (inertial), airspeed, mach, q (dynamic pressure,
%   Pa), gload (sensed acceleration / g₀), thrust (N), stage (index, 0 when
%   off), losses (n×4: gravity, drag, steering, thrust Δv; m/s, running), events
%   (struct array: time, label, h, v), budget (struct, at the end of
%   powered flight: tsiolkovsky per burn and total, thrustDv, gravity,
%   drag, steering, pressure, rotation, achieved, circularization; m/s), orbit (perigee and apogee
%   altitudes after cutoff, km; a, e), orbitAchieved, termination.
g0 = 9.80665;
[mu, R] = deal(3.986004418e14, 6371e3);
stages = normalizeStages(p.stages);
ns = numel(stages);
diameter = p.diameter;
area = pi * diameter^2 / 4;
spin = 0;
if p.rotation
    spin = 7.2921150e-5 * cosd(p.latitude);
end
gravityOn = ~isfield(p, 'gravity') || p.gravity;
if isfield(p, 'pitchProgram')
    program = p.pitchProgram;
else
    program = [];
end
ctx = struct('mu', mu * gravityOn, 'R', R, 'area', area, 'cd', p.cdScale, 'spin', spin, ...
    'stage', 0, 'thrust', 0, 'isp', 1, 'exitArea', 0, 'throttle', p.throttle, 'kickTime', NaN, ...
    'kickAltitude', p.kickAltitude, 'kickAngle', deg2rad(p.kickAngle), 'program', program, 'g0', g0, ...
    'upper', false, 'targetAltitude', p.targetApoapsis * 1e3);

liftoff = p.payload + sum([stages.dry]) + sum([stages.prop]);
v0 = spin * [R, 0];                         % the pad turns with the Earth
state = [0, R, v0, liftoff, 0, 0, 0, 0];
now = 0;
T = 0;
S = state;
STAGE = 0;
events = struct('time', {0}, 'label', {'Liftoff'}, 'h', {0}, 'v', {norm(v0)});
tsiolkovsky = zeros(ns, 1);
termination = 'completed';
target = p.targetApoapsis * 1e3;
cut = false;
circularization = 0;
leftover = 0;
lastStage = ns;
for k = 1:ns
    s = stages(k);
    if s.delay > 0
        [T, S, STAGE, state, now, why] = segment(T, S, STAGE, state, now, now + s.delay, ctx, p, 0, -Inf, target);
        if ~strcmp(why, 'time')
            termination = why;
            break
        end
    end
    ctx.stage = k;
    ctx.upper = k > 1;
    ctx.thrust = s.thrust * 1e3;
    ctx.isp = s.ispVac;
    ctx.exitArea = s.thrust * 1e3 * (1 - s.ispSl / s.ispVac) / 101325;
    events(end + 1) = struct('time', now, 'label', sprintf('Stage %d ignition', k), 'h', altitude(state, R), ...
        'v', norm(state(3:4))); %#ok<AGROW>
    startMass = state(5);
    empty = startMass - s.prop;
    % Only the last stage cuts off at the target apoapsis; the others burn out.
    limit = Inf;
    if k == ns
        limit = target;
    end
    [T, S, STAGE, state, now, why, ctx] = segment(T, S, STAGE, state, now, p.maxTime, ctx, p, k, empty, limit);
    tsiolkovsky(k) = dlab.sims.rocket.tsiolkovsky(s.ispVac, startMass, state(5));
    if strcmp(why, 'burnout')
        events(end + 1) = struct('time', now, 'label', sprintf('Stage %d burnout', k), 'h', altitude(state, R), ...
            'v', norm(state(3:4))); %#ok<AGROW>
        % Drop the empty stage: a second sample at the same time, so the
        % last burning one keeps its mass (and its thrust acceleration).
        state(5) = state(5) - s.dry;
        S(end + 1, :) = state; %#ok<AGROW>
        T(end + 1) = now; %#ok<AGROW>
        STAGE(end + 1) = 0; %#ok<AGROW>
        ctx.stage = 0;
        if k < ns
            continue
        end
        % The last stage burned out: powered flight is over (completed).
    elseif strcmp(why, 'cutoff')
        cut = true;
        leftover = state(5) - empty;             % propellant left for the circularization
        lastStage = k;
        events(end + 1) = struct('time', now, 'label', 'Cutoff: target orbit energy reached', ...
            'h', altitude(state, R), 'v', norm(state(3:4))); %#ok<AGROW>
        ctx.stage = 0;
    else
        termination = why;
    end
    break
end
ctx.stage = 0;
powered = state;                            % the end of powered flight, for the budget
if strcmp(termination, 'completed')
    % Coast: to the apoapsis after a cutoff, otherwise until the ground or the time limit.
    stopAtApoapsis = cut;
    coastEnd = p.maxTime;
    if cut
        % To the apoapsis even past the time limit (it is at most one orbit
        % away): the circularization should not depend on the limit.
        period = 2 * pi * sqrt(semiMajorAxis(state(1:2), state(3:4), ctx)^3 / max(ctx.mu, 1));
        if isfinite(period)
            coastEnd = max(coastEnd, now + period);
        end
    end
    [T, S, STAGE, state, now, why] = segment(T, S, STAGE, state, now, coastEnd, ctx, p, 0, -Inf, ...
        Inf, stopAtApoapsis);
    if strcmp(why, 'apoapsis')
        events(end + 1) = struct('time', now, 'label', 'Apoapsis', 'h', altitude(state, R), ...
            'v', norm(state(3:4)));
        if p.circularize
            % With what is left in the last stage: a full circularization if
            % the propellant allows, otherwise as much of it as it does.
            r = norm(state(1:2));
            radial = state(1:2) / r;
            along = [radial(2), -radial(1)];         % downrange (clockwise, the launch direction)
            if dot(along, state(3:4)) < 0
                along = -along;
            end
            change = sqrt(mu / r) * along - state(3:4);
            available = g0 * stages(lastStage).ispVac * log(state(5) / max(state(5) - leftover, realmin));
            circularization = min(norm(change), available);
            newV = state(3:4) + circularization * change / max(norm(change), realmin);
            state(3:4) = newV;
            state(5) = state(5) / exp(circularization / (g0 * stages(lastStage).ispVac));
            S(end + 1, :) = state;
            T(end + 1) = now;
            STAGE(end + 1) = 0;
            events(end + 1) = struct('time', now, 'label', 'Circularization burn', 'h', altitude(state, R), ...
                'v', norm(newV));
        end
    elseif strcmp(why, 'impact')
        termination = 'impact';
        events(end + 1) = struct('time', now, 'label', 'Impact', 'h', 0, 'v', norm(state(3:4)));
    end
end

% ------------------------------------------------------------- outputs
result.t = T;
result.x = S(:, 1);
result.y = S(:, 2);
result.vx = S(:, 3);
result.vy = S(:, 4);
result.mass = S(:, 5);
r = sqrt(S(:, 1).^2 + S(:, 2).^2);
result.h = r - R;
result.downrange = R * atan2(S(:, 1), S(:, 2));
result.speed = sqrt(S(:, 3).^2 + S(:, 4).^2);
air = [S(:, 3) - spin * S(:, 2), S(:, 4) + spin * S(:, 1)];
result.airspeed = sqrt(sum(air.^2, 2));
[rho, ~, ~, a] = dlab.physics.atmosphere(max(result.h, 0), 'Extended', true);
rho = reshape(rho, [], 1);
a = reshape(a, [], 1);
result.mach = result.airspeed ./ a;
result.q = 0.5 * rho .* result.airspeed.^2;
result.stage = STAGE(:);
n = numel(T);
thrust = zeros(n, 1);
gload = zeros(n, 1);
for k = 1:n
    [~, info] = rhs(T(k), S(k, :)', stageContext(ctx, stages, STAGE(k), p));
    thrust(k) = info.thrust;
    gload(k) = info.sensed / g0;
end
result.thrust = thrust;
result.gload = gload;
result.losses = S(:, 6:9);
result.events = events;

final = powered;                            % the budget covers the powered flight
budget.tsiolkovsky = tsiolkovsky;
budget.total = sum(tsiolkovsky);
budget.thrustDv = final(9);
budget.gravity = final(6);
budget.drag = final(7);
budget.steering = final(8);
budget.pressure = budget.total - final(9);
budget.rotation = norm(v0);
budget.achieved = norm(final(3:4)) - norm(v0);
budget.circularization = circularization;
result.budget = budget;
% The orbit at the end (after the circularization burn, if any).
[result.orbit, result.orbitAchieved] = orbitOf(S(end, 1:2), S(end, 3:4), mu, R);
result.termination = termination;
result.cutoff = cut;
end

% ------------------------------------------------------------ segments
function [T, S, STAGE, state, now, why, ctx] = segment(T, S, STAGE, state, now, stopTime, ctx, p, k, empty, ...
    target, stopAtApoapsis)
% Integrate one phase (stage K burning, or coasting for K = 0) until the
% time UNTIL or an event: burnout, impact, cutoff (apoapsis ≥ TARGET),
% the pitch-over (the kick, which continues the segment), or apoapsis.
if nargin < 12
    stopAtApoapsis = false;
end
why = 'time';
if stopTime <= now
    return
end
while true
    times = unique([now, ceil(now / p.dt) * p.dt:p.dt:stopTime, stopTime]);
    if numel(times) == 2
        times = [now, (now + stopTime) / 2, stopTime];
    end
    options = odeset('RelTol', 1e-9, 'AbsTol', 1e-6, 'MaxStep', max(p.dt, 0.05), ...
        'Events', @(t, s) stops(t, s, ctx, k, empty, target, stopAtApoapsis));
    [t, s, tEvent, sEvent, which] = ode45(@(t, s) rhs(t, s, ctx), times, state(:), options);
    if ~isempty(tEvent)
        keep = t < tEvent(end);
        t = [t(keep); tEvent(end)];
        s = [s(keep, :); sEvent(end, :)];
    end
    if t(1) == T(end)
        t = t(2:end);
        s = s(2:end, :);
    end
    T = [T; t]; %#ok<AGROW>
    S = [S; s]; %#ok<AGROW>
    STAGE = [STAGE; k * ones(numel(t), 1)]; %#ok<AGROW>
    state = S(end, :);
    now = T(end);
    if isfield(p, 'progressFcn') && ~isempty(p.progressFcn) && p.progressFcn(min(now / p.maxTime, 1))
        why = 'cancelled';
        return
    end
    if isempty(tEvent)
        return
    end
    names = {'burnout', 'impact', 'cutoff', 'kick', 'apoapsis'};
    why = names{which(end)};
    if strcmp(why, 'kick')
        ctx.kickTime = now;                       % pitch over, then keep flying this stage
        why = 'time';
        continue
    end
    return
end
end

function [value, terminal, direction] = stops(t, s, ctx, k, empty, target, stopAtApoapsis)
h = norm(s(1:2)) - ctx.R;
burning = k > 0;
if ctx.upper && isfinite(ctx.targetAltitude) && isempty(ctx.program)
    % Climb-rate guidance holds the target altitude: cut off when the
    % orbital energy reaches that of a circular orbit there.
    reached = semiMajorAxis(s(1:2), s(3:4), ctx) - ctx.R;
else
    reached = apoapsisAltitude(s(1:2), s(3:4), ctx);
end
value = [s(5) - empty
         h + 1
         target - reached
         ctx.kickAltitude - h + 1e9 * ~isnan(ctx.kickTime)
         dot(s(1:2), s(3:4))];
if ~burning
    value(1) = 1;
    value(3) = 1;
end
if ~stopAtApoapsis || t < 1
    value(5) = 1;
end
terminal = [1; 1; 1; 1; 1];
direction = [-1; -1; -1; -1; -1];
end

function [ds, info] = rhs(t, s, ctx)
r = s(1:2);
v = s(3:4);
m = s(5);
rn = norm(r);
up = r / rn;
h = rn - ctx.R;
g = -ctx.mu * r / rn^3;
air = [v(1) - ctx.spin * r(2); v(2) + ctx.spin * r(1)];
[rho, ~, pressure, sound] = dlab.physics.atmosphere(max(h, 0), 'Extended', true);
airspeed = norm(air);
drag = [0; 0];
if airspeed > 0 && ctx.cd > 0
    drag = -0.5 * rho * airspeed * air * ctx.cd * dragCoefficient(airspeed / sound) * ctx.area;
end
thrust = 0;
mdot = 0;
direction = up;
if ctx.stage > 0
    throttle = min(max(ctx.throttle(t), 0), 1);
    thrust = max(throttle * ctx.thrust - pressure * ctx.exitArea, 0);
    mdot = throttle * ctx.thrust / (ctx.g0 * ctx.isp);
    direction = steer(t, up, v, air, h, rn, thrust / m, -g' * up, ctx);
end
a = g + (thrust * direction + drag) / m;
speed = norm(v);
if speed > 1e-9
    along = v / speed;
else
    along = direction;
end
ds = [v; a; -mdot
      -g' * along
      -(drag' * along) / m
      thrust / m * (1 - direction' * along)
      thrust / m];
if nargout > 1
    info = struct('thrust', thrust, 'sensed', norm(thrust * direction + drag) / m);
end
end

function d = steer(t, up, v, air, h, rn, accel, gravity, ctx)
% Thrust direction. First stage: vertical, the pitch-over, then a gravity
% turn (along the air-relative velocity). Upper stages, when there is a
% target: climb-rate control, pitching just enough to approach the target
% altitude gently while the rest of the thrust builds horizontal speed.
% A pitch program, when given, overrides both.
east = [up(2); -up(1)];                    % downrange (the launch direction)
if ~isempty(ctx.program)
    gamma = deg2rad(ctx.program(t));
    d = cos(gamma) * east + sin(gamma) * up;
    return
end
if ctx.upper && isfinite(ctx.targetAltitude) && accel > 0
    climb = v' * up;
    horizontal = norm(v - climb * up);
    wanted = min(max((ctx.targetAltitude - h) / 100, -100), 300);   % m/s, toward the target altitude
    needed = (wanted - climb) / 10 + gravity - horizontal^2 / rn;   % vertical thrust acceleration
    pitch = asin(min(max(needed / accel, -0.3), 0.95));
    d = cos(pitch) * east + sin(pitch) * up;
    return
end
if isnan(ctx.kickTime) || t < ctx.kickTime
    d = up;
    return
end
blend = min((t - ctx.kickTime) / 5, 1);
if blend < 1 || norm(air) < 1
    angle = ctx.kickAngle * blend;
    d = sin(angle) * east + cos(angle) * up;
else
    d = air / norm(air);
    if d' * up < 0 && h > 0
        % Past the top of a suborbital arc: keep thrusting horizontally.
        d = east * sign(d' * east + eps);
    end
end
end

function cd = dragCoefficient(mach)
% A generic slender rocket: subsonic 0.3, a peak of 0.6 just above Mach 1.
M = [0 0.8 1.0 1.2 1.5 2 3 5 10];
C = [0.30 0.32 0.45 0.60 0.55 0.45 0.35 0.25 0.22];
cd = interp1(M, C, min(max(mach, 0), 10));
end

function a = semiMajorAxis(r, v, ctx)
mu = max(ctx.mu, 1);
energy = 0.5 * (v(:)' * v(:)) - mu / norm(r);
a = Inf;
if energy < 0
    a = -mu / (2 * energy);
end
end

function ra = apoapsisAltitude(r, v, ctx)
mu = max(ctx.mu, 1);
rn = norm(r);
energy = 0.5 * (v(:)' * v(:)) - mu / rn;
if energy >= 0
    ra = Inf;
    return
end
a = -mu / (2 * energy);
hvec = r(1) * v(2) - r(2) * v(1);
e = sqrt(max(1 - hvec^2 / (mu * a), 0));
ra = a * (1 + e) - ctx.R;
end

function [orbit, achieved] = orbitOf(r, v, mu, R)
rn = norm(r);
energy = 0.5 * (v(:)' * v(:)) - mu / rn;
hvec = r(1) * v(2) - r(2) * v(1);
if energy >= 0
    orbit = struct('perigee', NaN, 'apogee', Inf, 'a', Inf, 'e', 1);
    achieved = false;
    return
end
a = -mu / (2 * energy);
e = sqrt(max(1 - hvec^2 / (mu * a), 0));
orbit = struct('perigee', (a * (1 - e) - R) / 1e3, 'apogee', (a * (1 + e) - R) / 1e3, 'a', a / 1e3, 'e', e);
achieved = orbit.perigee > 120;
end

function c = stageContext(ctx, stages, k, p)
c = ctx;
c.stage = k;
c.upper = k > 1;
if k > 0
    s = stages(k);
    c.thrust = s.thrust * 1e3;
    c.isp = s.ispVac;
    c.exitArea = s.thrust * 1e3 * (1 - s.ispSl / s.ispVac) / 101325;
end
c.kickAltitude = p.kickAltitude;
end

function h = altitude(state, R)
h = norm(state(1:2)) - R;
end

function stages = normalizeStages(value)
if isstruct(value)
    stages = value(:)';
else
    stages = table2struct(value)';
end
if isempty(stages)
    error('rocket:InvalidParameter', 'Give at least one stage.');
end
for k = 1:numel(stages)
    s = stages(k);
    if ~(s.dry > 0 && s.prop > 0 && s.thrust > 0 && s.ispVac > 0 && s.ispSl > 0 && s.ispSl <= s.ispVac && s.delay >= 0)
        error('rocket:InvalidParameter', ...
            'Stage %d: masses, thrust, and Isp must be positive, with sea-level Isp at most the vacuum Isp.', k);
    end
end
end
