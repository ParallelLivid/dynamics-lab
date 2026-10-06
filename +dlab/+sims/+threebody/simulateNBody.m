function result = simulateNBody(p)
%SIMULATENBODY Point masses under their mutual gravity (G = 1).
%   Fields: mass (N×1), pos and vel (N×3), soft (softening length ε:
%   the force uses r² + ε²), tspan, dt, optional progressFcn.
%
%   result: t, pos and vel (n × N × 3), energy, momentum (n×3), angular
%   (angular momentum, n×3), drift (struct: energy, momentum, angular;
%   largest changes, relative to the scale of each), and closest (the
%   smallest distance between any two bodies) with its time and pair.
m = p.mass(:);
n = numel(m);
if n < 2 || n > 8 || any(m <= 0) || ~isequal(size(p.pos), [n 3]) || ~isequal(size(p.vel), [n 3])
    error('threebody:InvalidParameter', 'Give 2 to 8 bodies with positive masses, positions, and velocities.');
end
if ~(p.tspan > 0 && p.dt > 0 && p.soft >= 0)
    error('threebody:InvalidParameter', 'The duration and output step must be positive.');
end
for i = 1:n - 1
    gaps = sqrt(sum((p.pos(i + 1:end, :) - p.pos(i, :)).^2, 2));
    if any(gaps == 0) && p.soft == 0
        error('threebody:InvalidParameter', 'Two bodies start at the same place.');
    end
end
t = (0:p.dt:p.tspan)';
if t(end) < p.tspan
    t(end + 1) = p.tspan;
end
if numel(t) < 3
    t = linspace(0, p.tspan, 3)';
end
s0 = [reshape(p.pos', [], 1); reshape(p.vel', [], 1)];
options = odeset('RelTol', 1e-12, 'AbsTol', 1e-12);
if isfield(p, 'progressFcn') && ~isempty(p.progressFcn)
    options = odeset(options, 'OutputFcn', dlab.physics.odeProgress(p.progressFcn, t));
end
[tOut, s] = ode113(@(~, y) rhs(y, m, p.soft), t, s0, options);
k = numel(tOut);
pos = permute(reshape(s(:, 1:3 * n)', 3, n, k), [3 2 1]);
vel = permute(reshape(s(:, 3 * n + 1:end)', 3, n, k), [3 2 1]);

kinetic = 0.5 * sum(sum(vel.^2, 3) .* m', 2);
potential = zeros(k, 1);
closest = inf;
closestTime = 0;
pair = [1 2];
for i = 1:n - 1
    for j = i + 1:n
        d = sqrt(sum((pos(:, i, :) - pos(:, j, :)).^2, 3));
        potential = potential - m(i) * m(j) ./ sqrt(d.^2 + p.soft^2);
        [dMin, at] = min(d);
        if dMin < closest
            [closest, closestTime, pair] = deal(dMin, tOut(at), [i j]);
        end
    end
end
momentum = squeeze(sum(vel .* m', 2));
angular = squeeze(sum(cross(pos, vel .* m', 3), 2));
if k == 1
    momentum = momentum(:)';
    angular = angular(:)';
end
energy = kinetic + potential;
speedScale = sqrt(2 * max(kinetic) / sum(m));
sizeScale = max(sqrt(sum(p.pos.^2, 2)));

result.t = tOut;
result.pos = pos;
result.vel = vel;
result.mass = m;
result.energy = energy;
result.momentum = momentum;
result.angular = angular;
result.drift.energy = max(abs(energy - energy(1))) / max(abs(energy(1)), max(kinetic));
result.drift.momentum = max(sqrt(sum((momentum - momentum(1, :)).^2, 2))) / max(sum(m) * speedScale, realmin);
result.drift.angular = max(sqrt(sum((angular - angular(1, :)).^2, 2))) / ...
    max(sum(m) * speedScale * sizeScale, realmin);
result.closest = closest;
result.closestTime = closestTime;
result.closestPair = pair;
end

function dy = rhs(y, m, soft)
n = numel(m);
r = reshape(y(1:3 * n), 3, n)';
v = y(3 * n + 1:end);
dx = r(:, 1)' - r(:, 1);                   % dx(i, j) = x_j − x_i
dy_ = r(:, 2)' - r(:, 2);
dz = r(:, 3)' - r(:, 3);
d2 = dx.^2 + dy_.^2 + dz.^2 + soft^2;
inv3 = d2.^-1.5;
inv3(1:n + 1:end) = 0;
a = [(dx .* inv3) * m, (dy_ .* inv3) * m, (dz .* inv3) * m];
dy = [v; reshape(a', [], 1)];
end
