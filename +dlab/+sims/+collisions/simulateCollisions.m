function result = simulateCollisions(p)
%SIMULATECOLLISIONS Hard discs in a box, event by event (no time steps).
%   result = simulateCollisions(p) moves the discs in straight lines
%   between collisions, finds the next collision exactly (a quadratic for
%   each pair, linear for walls), and applies it.
%
%   p.pos, p.vel   N×2 initial positions (m) and velocities (m/s)
%   p.radius, p.mass   N×1 (or scalars)
%   p.e, p.ew      restitution between discs and at the walls
%   p.W, p.H       box size (m), corner at the origin
%   p.boundary     'walls' or 'periodic' (no walls; the box repeats)
%   p.tspan, p.dtOut   duration and sampling step (s)
%   p.maxEvents    stop after this many events (a guard)
%   p.progressFcn  optional @(fraction) stop, checked every 500 events
%
%   Collisions are smooth (no friction, no spin): the impulse
%   J = (1 + e) μ u acts along the line of centres (μ the reduced mass, u
%   the approach speed). Approaches slower than 10⁻⁶ of the RMS speed are
%   elastic, which prevents inelastic collapse.
%
%   result: t (samples), x, y, vx, vy (samples × N), KE, P (|total
%   momentum|), events (log: time, i, j (−1…−4 for the left, right,
%   bottom, and top walls), impulse), collisions and wallHits (counts),
%   wallImpulse (cumulative, at the samples), firstCollision (time, i, j,
%   and the two velocities vi, vj just after the first disc–disc
%   collision; time NaN if there was none), stopped ("completed" |
%   "maxEvents" | "cancelled"), and the inputs radius, mass, W, H.
[x, v, radius, mass] = validate(p);
n = size(x, 1);
periodic = strcmpi(p.boundary, 'periodic');
box = [p.W p.H];
speedScale = sqrt(mean(sum(v.^2, 2)));
slowest = 1e-6 * max(speedScale, realmin);

samples = (0:p.dtOut:p.tspan)';
if samples(end) < p.tspan
    samples(end + 1) = p.tspan;
end
ns = numel(samples);
X = zeros(ns, n);
Y = X;
VX = X;
VY = X;
wallImpulse = zeros(ns, 1);

eventLog = zeros(min(p.maxEvents, 1e6), 4);
count = 0;
collisions = 0;
wallHits = 0;
impulseSum = 0;
first = struct('time', NaN, 'i', 0, 'j', 0, 'vi', [NaN NaN], 'vj', [NaN NaN]);

nextTime = inf(n, 1);
partner = zeros(n, 1);
for i = 1:n
    [nextTime(i), partner(i)] = predict(i, x, v, radius, box, periodic);
end

now = 0;
next = 1;                                         % next sample to record
stopped = "completed";
while true
    [tEvent, i] = min(nextTime);
    % Record the samples before this event.
    while next <= ns && samples(next) <= tEvent
        dt = samples(next) - now;
        here = x + v * dt;
        if periodic
            here = mod(here, box);
        end
        X(next, :) = here(:, 1)';
        Y(next, :) = here(:, 2)';
        VX(next, :) = v(:, 1)';
        VY(next, :) = v(:, 2)';
        wallImpulse(next) = impulseSum;
        next = next + 1;
    end
    if next > ns
        break
    end
    if count >= p.maxEvents
        stopped = "maxEvents";
        break
    end
    % Move everyone to the event.
    x = x + v * (tEvent - now);
    now = tEvent;
    j = partner(i);
    count = count + 1;
    if j > 0
        d = x(j, :) - x(i, :);
        if periodic
            d = d - box .* round(d ./ box);
        end
        normal = d / norm(d);
        u = (v(i, :) - v(j, :)) * normal';         % approach speed (> 0)
        e = p.e;
        if u < slowest
            e = 1;
        end
        J = (1 + e) * u * mass(i) * mass(j) / (mass(i) + mass(j));
        v(i, :) = v(i, :) - J / mass(i) * normal;
        v(j, :) = v(j, :) + J / mass(j) * normal;
        collisions = collisions + 1;
        if collisions == 1
            first = struct('time', now, 'i', i, 'j', j, 'vi', v(i, :), 'vj', v(j, :));
        end
        involved = [i; j];
    else
        wall = -j;
        dim = 1 + (wall > 2);                      % 1: left/right, 2: bottom/top
        if periodic
            % Crossing the box edge: reappear on the opposite side.
            x(i, dim) = box(dim) * mod(wall, 2);    % left/bottom (odd) → far side
            J = 0;
        else
            J = mass(i) * (1 + p.ew) * abs(v(i, dim));
            v(i, dim) = -p.ew * v(i, dim);
            impulseSum = impulseSum + J;
            wallHits = wallHits + 1;
        end
        involved = i;
    end
    if count <= size(eventLog, 1)
        eventLog(count, :) = [now, i, j, J];
    end
    % Recompute the involved discs and every disc that expected to meet them.
    stale = unique([involved; find(ismember(partner, involved(involved > 0)))]);
    for k = stale'
        [nextTime(k), partner(k)] = predict(k, x, v, radius, box, periodic);
        nextTime(k) = nextTime(k) + now;
    end
    % Every 500 events: a report costs a good fraction of an event.
    if isfield(p, 'progressFcn') && ~isempty(p.progressFcn) && mod(count, 500) == 0
        if p.progressFcn(now / p.tspan)
            stopped = "cancelled";
            break
        end
    end
end
if next <= ns
    % Ended early: keep the samples reached.
    keep = 1:next - 1;
    [samples, X, Y, VX, VY, wallImpulse] = deal(samples(keep), X(keep, :), Y(keep, :), VX(keep, :), ...
        VY(keep, :), wallImpulse(keep));
end

result.t = samples;
result.x = X;
result.y = Y;
result.vx = VX;
result.vy = VY;
result.KE = 0.5 * (VX.^2 + VY.^2) * mass;
result.P = sqrt((VX * mass).^2 + (VY * mass).^2);
result.events = eventLog(1:min(count, size(eventLog, 1)), :);
result.collisions = collisions;
result.wallHits = wallHits;
result.wallImpulse = wallImpulse;
result.firstCollision = first;
result.stopped = stopped;
result.radius = radius;
result.mass = mass;
result.W = p.W;
result.H = p.H;
result.periodic = periodic;
end

% ------------------------------------------------------------ prediction
function [t, who] = predict(i, x, v, radius, box, periodic)
% The time until disc I's next event (from now) and with whom: another
% disc (> 0), or a wall (−1 left, −2 right, −3 bottom, −4 top; in a
% periodic box, crossing that edge).
n = size(x, 1);
others = [1:i - 1, i + 1:n]';
t = inf;
who = 0;
if ~isempty(others)
    dr = x(others, :) - x(i, :);
    dv = v(others, :) - v(i, :);
    sigma = radius(others) + radius(i);
    if periodic
        % The nearest image and its eight neighbours, all at once (one
        % column per image).
        dr = dr - box .* round(dr ./ box);
        sx = [0 -1 1 0 0 -1 -1 1 1] * box(1);
        sy = [0 0 0 -1 1 -1 1 -1 1] * box(2);
    else
        [sx, sy] = deal(0);
    end
    dx = dr(:, 1) + sx;
    dy = dr(:, 2) + sy;
    vv = repmat(sum(dv.^2, 2), 1, numel(sx));
    b = dx .* dv(:, 1) + dy .* dv(:, 2);
    rr = dx.^2 + dy.^2;
    disc = b.^2 - vv .* (rr - sigma.^2);
    hit = b < 0 & disc >= 0 & vv > 0;
    if any(hit(:))
        times = inf(size(b));
        times(hit) = max((-b(hit) - sqrt(disc(hit))) ./ vv(hit), 0);
        [t, k] = min(times(:));
        who = others(mod(k - 1, numel(others)) + 1);
    end
end
% Walls (or box edges).
r = radius(i) * ~periodic;
for dim = 1:2
    speed = v(i, dim);
    if speed > 0
        tWall = (box(dim) - r - x(i, dim)) / speed;
        code = -2 * dim;                           % right or top
    elseif speed < 0
        tWall = (r - x(i, dim)) / speed;
        code = -2 * dim + 1;                       % left or bottom
    else
        continue
    end
    tWall = max(tWall, 0);
    if tWall < t
        t = tWall;
        who = code;
    end
end
end

function [x, v, radius, mass] = validate(p)
x = p.pos;
v = p.vel;
n = size(x, 1);
if n < 1 || size(x, 2) ~= 2 || ~isequal(size(v), size(x))
    error('collisions:InvalidParameter', 'Positions and velocities must be N×2.');
end
radius = p.radius(:) .* ones(n, 1);
mass = p.mass(:) .* ones(n, 1);
if any(radius <= 0) || any(mass <= 0)
    error('collisions:InvalidParameter', 'Radii and masses must be positive.');
end
if ~(p.e >= 0 && p.e <= 1 && p.ew >= 0 && p.ew <= 1)
    error('collisions:InvalidParameter', 'Restitution must be between 0 and 1.');
end
if ~(p.tspan > 0 && p.dtOut > 0 && p.maxEvents >= 1)
    error('collisions:InvalidParameter', 'The duration, output step, and event limit must be positive.');
end
if ceil(p.tspan / p.dtOut) * n > 2e7
    error('collisions:InvalidParameter', 'Too many samples: increase the output step.');
end
periodic = strcmpi(p.boundary, 'periodic');
box = [p.W p.H];
if ~periodic && any(any(x - radius < -1e-12 | x + radius > box + 1e-12))
    error('collisions:Overlap', 'A disc starts outside the box or through a wall.');
end
if periodic
    if any(any(x < 0 | x >= box))
        error('collisions:Overlap', 'A disc starts outside the periodic box.');
    end
    if 2 * max(radius) * 2 >= min(box)
        error('collisions:InvalidParameter', 'The periodic box must be wider than two discs.');
    end
end
for i = 1:n - 1
    d = x(i + 1:end, :) - x(i, :);
    if periodic
        d = d - box .* round(d ./ box);
    end
    gap = sqrt(sum(d.^2, 2)) - radius(i + 1:end) - radius(i);
    k = find(gap < -1e-12, 1);
    if ~isempty(k)
        error('collisions:Overlap', 'Discs %d and %d overlap at the start.', i, i + k);
    end
end
end
