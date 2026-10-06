function s = initialState(p)
%INITIALSTATE Starting positions and velocities for simulateCollisions.
%   s = initialState(p) returns pos, vel (N×2), radius and mass (N×1), and
%   tracer (the tracer's index, 0 for none) for p.mode:
%
%     'billiards'  a 15-ball triangle rack and a cue ball (cueSpeed, m/s,
%                  and cueAngle, degrees from +x), on a W×H table
%     'twoball'    a moving ball hitting a ball at rest off-centre: the
%                  centres are p.offset radii apart across the motion
%                  (0 head-on, below 2 a glancing hit)
%     'cradle'     five balls in a row, the first moving (Newton's cradle)
%     'gas'        N discs in shuffled cells of a grid (jittered by what
%                  room each cell leaves), with speeds all equal to v0
%                  (velocityInit 'equal') or Maxwell-distributed and scaled
%                  to the same mean energy ½ m v0² ('maxwell'), in random
%                  directions
%
%   Common fields: radius, mass, W, H, v0, seed. Gas: N, velocityInit,
%   and an optional heavy tracer at the centre (tracer, tracerMass as a
%   multiple of the mass, tracerRadius as a multiple of the radius).
%   Random numbers come from a fixed generator seeded by p.seed, so a seed
%   always gives the same start.
r = p.radius;
m = p.mass;
W = p.W;
H = p.H;
tracer = 0;
switch lower(p.mode)
    case 'billiards'
        gap = 1e-3 * r;                            % racked almost touching
        pitch = 2 * r + gap;
        apex = [0.72 * W, H / 2];
        pos = zeros(15, 2);
        k = 0;
        for row = 0:4
            for ball = 0:row
                k = k + 1;
                pos(k, :) = apex + [row * pitch * sqrt(3) / 2, (ball - row / 2) * pitch];
            end
        end
        cue = [0.25 * W, H / 2];
        angle = deg2rad(p.cueAngle);
        pos = [cue; pos];
        vel = zeros(16, 2);
        vel(1, :) = p.cueSpeed * [cos(angle), sin(angle)];
    case 'twoball'
        pos = [0.25 * W, H / 2; 0.5 * W, H / 2 + p.offset * r];
        vel = [p.v0, 0; 0, 0];
    case 'cradle'
        pitch = 2 * r * (1 + 1e-9);
        x0 = W / 2 - 2 * pitch;
        pos = [(0:4)' * pitch + x0, H / 2 * ones(5, 1)];
        pos(1, 1) = pos(1, 1) - 6 * r;             % the first ball swings in
        vel = zeros(5, 2);
        vel(1, 1) = p.v0;
    case 'gas'
        [pos, vel, tracer] = gas(p);
    otherwise
        error('collisions:InvalidParameter', 'Unknown start "%s".', p.mode);
end
n = size(pos, 1);
s.pos = pos;
s.vel = vel;
s.radius = r * ones(n, 1);
s.mass = m * ones(n, 1);
if tracer > 0
    s.radius(tracer) = r * p.tracerRadius;
    s.mass(tracer) = m * p.tracerMass;
end
s.tracer = tracer;
end

function [pos, vel, tracer] = gas(p)
r = p.radius;
W = p.W;
H = p.H;
n = round(p.N);
tracer = 0;
reserve = 0;
if p.tracer
    reserve = p.tracerRadius * r;              % keep the centre clear
end
% A grid with at least N free cells, as square as the box allows.
columns = max(1, floor(W / (2.02 * r)));
rows = max(1, floor(H / (2.02 * r)));
[cx, cy] = meshgrid(((1:columns) - 0.5) * W / columns, ((1:rows) - 0.5) * H / rows);
cells = [cx(:), cy(:)];
if p.tracer
    free = sqrt(sum((cells - [W H] / 2).^2, 2)) > reserve + r * 1.02;
    cells = cells(free, :);
end
if size(cells, 1) < n
    error('collisions:InvalidParameter', 'The box holds at most %d discs of this size.', size(cells, 1));
end
u = dlab.physics.uniformSequence(p.seed, 4 * n + numel(cells));
% Spread the discs over the cells (in a fixed shuffled order), then jitter
% each within the room its cell leaves.
[~, order] = sort(u(1:size(cells, 1)));
pos = cells(order(1:n), :);
room = max([W / columns, H / rows] / 2 - r * 1.01, 0);
used = size(cells, 1);
pos = pos + (2 * reshape(u(used + 1:used + 2 * n), n, 2) - 1) .* room;
used = used + 2 * n;
direction = 2 * pi * u(used + 1:used + n)';
used = used + n;
if strcmpi(p.velocityInit, 'maxwell')
    % 2-D Maxwell: speed ~ Rayleigh, scaled so that the mean of v² is
    % exactly v0² (kT = ½ m v0², as for the equal start; a sample of N
    % would otherwise be off by about 1/√N).
    speed = sqrt(-log(1 - u(used + 1:used + n)'));
    speed = p.v0 * speed / max(sqrt(mean(speed.^2)), realmin);
else
    speed = p.v0 * ones(n, 1);
end
vel = speed .* [cos(direction), sin(direction)];
if p.tracer
    pos = [[W H] / 2; pos];
    vel = [0 0; vel];
    tracer = 1;
end
end
