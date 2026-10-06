function tests = test_simulateCollisions
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = box(pos, vel, mass)
p = struct('pos', pos, 'vel', vel, 'radius', 0.1, 'mass', mass, 'e', 1, 'ew', 1, 'W', 10, 'H', 10, ...
    'boundary', 'walls', 'tspan', 2, 'dtOut', 0.5, 'maxEvents', 1e5);
end

function g = gasParams(N, boundary)
g = struct('mode', 'gas', 'N', N, 'radius', 0.02, 'mass', 1, 'W', 1, 'H', 1, 'v0', 1, ...
    'velocityInit', 'equal', 'seed', 3, 'tracer', false, 'tracerMass', 50, 'tracerRadius', 4, ...
    'cueSpeed', 0, 'cueAngle', 0, 'offset', 0);
g.boundary = boundary;
end

function p = gasRun(g, tspan)
s = dlab.sims.collisions.initialState(g);
p = struct('pos', s.pos, 'vel', s.vel, 'radius', s.radius, 'mass', s.mass, 'e', 1, 'ew', 1, ...
    'W', g.W, 'H', g.H, 'boundary', g.boundary, 'tspan', tspan, 'dtOut', 0.05, 'maxEvents', 1e6);
end

function testHeadOnEqualMassesExchange(testCase)
r = dlab.sims.collisions.simulateCollisions(box([4 5; 6 5], [1 0; -1 0], 1));
verifyEqual(testCase, r.collisions, 1);
verifyEqual(testCase, [r.vx(end, :); r.vy(end, :)], [-1 1; 0 0], 'AbsTol', 1e-14);
end

function testHeadOnUnequalMasses(testCase)
m = [1; 3];
u = [2; -1];
r = dlab.sims.collisions.simulateCollisions(box([4 5; 6 5], [u [0; 0]], m));
expected = [((m(1) - m(2)) * u(1) + 2 * m(2) * u(2)) / sum(m), ((m(2) - m(1)) * u(2) + 2 * m(1) * u(1)) / sum(m)];
after = find(r.t > r.events(1, 1), 1);
verifyEqual(testCase, r.vx(after, :), expected, 'AbsTol', 1e-12);
end

function testObliqueSeparationIsRightAngle(testCase)
r = dlab.sims.collisions.simulateCollisions(box([3 5; 5 5.1], [1 0; 0 0], 1));
after = find(r.t > r.events(1, 1), 1);
v1 = [r.vx(after, 1) r.vy(after, 1)];
v2 = [r.vx(after, 2) r.vy(after, 2)];
verifyEqual(testCase, v1 * v2', 0, 'AbsTol', 1e-12);
verifyEqual(testCase, r.KE(end), 0.5, 'RelTol', 1e-12);
end

function testInelasticEnergyLoss(testCase)
p = box([3 5; 5 5.1], [1 0; 0 0], [1; 2]);
p.e = 0.6;
r = dlab.sims.collisions.simulateCollisions(p);
mu = 2 / 3;
d = p.pos(2, :) - p.pos(1, :) - [1 0] * r.events(1, 1);  % centres at contact
n = d / norm(d);
un = [1 0] * n';
verifyEqual(testCase, r.KE(end) - r.KE(1), -0.5 * mu * (1 - 0.36) * un^2, 'AbsTol', 1e-12);
end

function testGasRelaxesToMaxwell(testCase)
g = gasParams(100, 'walls');
p = gasRun(g, 40);
r = dlab.sims.collisions.simulateCollisions(p);
verifyGreaterThan(testCase, 2 * r.collisions / 100, 200, 'At least 200 collisions per disc.');
verifyEqual(testCase, r.KE, r.KE(1) * ones(size(r.KE)), 'RelTol', 1e-12);
late = r.t >= r.t(end) / 2;
speed = sqrt(r.vx(late, :).^2 + r.vy(late, :).^2);
kT = mean(r.KE(late)) / 100;
verifyLessThan(testCase, dlab.sims.collisions.maxwellDistance(speed(:), 1, kT), 0.05);
end

function testPeriodicConservesMomentum(testCase)
g = gasParams(60, 'periodic');
p = gasRun(g, 10);
r = dlab.sims.collisions.simulateCollisions(p);
px = r.vx * r.mass;
py = r.vy * r.mass;
verifyEqual(testCase, [px py], [px(1) py(1)] .* ones(size(px)), 'AbsTol', 1e-12);
verifyEqual(testCase, r.wallHits, 0);
verifyGreaterThan(testCase, r.collisions, 100);
end

function testReproducible(testCase)
g = gasParams(50, 'walls');
a = dlab.sims.collisions.simulateCollisions(gasRun(g, 3));
b = dlab.sims.collisions.simulateCollisions(gasRun(g, 3));
verifyTrue(testCase, isequal(a.x, b.x) && isequal(a.vy, b.vy));
end

function testNewtonsCradle(testCase)
g = gasParams(5, 'walls');
[g.mode, g.radius, g.W, g.H] = deal('cradle', 0.1, 4, 1);
s = dlab.sims.collisions.initialState(g);
p = struct('pos', s.pos, 'vel', s.vel, 'radius', s.radius, 'mass', s.mass, 'e', 1, 'ew', 1, ...
    'W', g.W, 'H', g.H, 'boundary', 'walls', 'tspan', 0.9, 'dtOut', 0.1, 'maxEvents', 100);
r = dlab.sims.collisions.simulateCollisions(p);
verifyEqual(testCase, r.vx(end, :), [0 0 0 0 1], 'AbsTol', 1e-12, 'Only the last ball moves on.');
end

function testOverlapIsAnError(testCase)
verifyError(testCase, @() dlab.sims.collisions.simulateCollisions(box([5 5; 5.1 5], [0 0; 0 0], 1)), ...
    'collisions:Overlap');
end

function testObliqueClosedForm(testCase)
% Ball 1 (speed 1 along x) hits ball 2 at rest, the centres 1 radius apart
% across the motion: the line of centres is at α = asin(1/2) = 30°, ball 2
% leaves along it at 2 m1/(m1 + m2) cos α, ball 1 keeps the rest of the
% momentum (closed form, worked out independently of the engine).
alpha = asin(0.5);
n = [cos(alpha) sin(alpha)];
for m = [1 1; 1 3; 3 1]'
    p = box([3 5; 5 5.1], [1 0; 0 0], m);
    r = dlab.sims.collisions.simulateCollisions(p);
    v2 = 2 * m(1) / sum(m) * cos(alpha) * n;
    v1 = [1 0] - m(2) / m(1) * v2;
    f = r.firstCollision;
    verifyEqual(testCase, [f.i f.j], [1 2]);
    verifyEqual(testCase, [f.vi; f.vj], [v1; v2], 'AbsTol', 1e-14);
end
% Equal masses: the 30° and −60° paths, 90° apart, speeds cos α and sin α.
verifyEqual(testCase, r.firstCollision.time, 2 - 0.2 * cos(alpha), 'AbsTol', 1e-14);
end

function testWallReflectionWithRestitution(testCase)
p = struct('pos', [0.5 0.5], 'vel', [3 -2], 'radius', 0.1, 'mass', 2, 'e', 1, 'ew', 0.7, ...
    'W', 1, 'H', 1, 'boundary', 'walls', 'tspan', 0.2, 'dtOut', 0.2, 'maxEvents', 10);
r = dlab.sims.collisions.simulateCollisions(p);
% The right wall (x = 0.9) at t = 0.4 / 3; the bottom (y = 0.1) at 0.2 is the end.
verifyEqual(testCase, r.events(1, 1:3), [0.4 / 3, 1, -2], 'AbsTol', 1e-15);
verifyEqual(testCase, r.events(1, 4), 2 * 1.7 * 3, 'RelTol', 1e-14);
verifyEqual(testCase, [r.vx(end) r.vy(end)], [-2.1 -2], 'AbsTol', 1e-14);
verifyEqual(testCase, r.wallImpulse(end), 10.2, 'RelTol', 1e-14);
end

function testNoOverlapsAndNothingLeavesTheBox(testCase)
% A dense gas sampled finely: every pair stays at least r_i + r_j apart and
% every disc inside the walls (to rounding).
g = gasParams(200, 'walls');
g.radius = 0.025;
p = gasRun(g, 2);
p.dtOut = 0.002;
r = dlab.sims.collisions.simulateCollisions(p);
n = numel(r.mass);
[i, j] = find(triu(true(n), 1));
gap = inf;
for k = 1:numel(r.t)
    d = hypot(r.x(k, i) - r.x(k, j), r.y(k, i) - r.y(k, j)) - (r.radius(i) + r.radius(j))';
    gap = min(gap, min(d));
end
verifyGreaterThan(testCase, gap, -1e-12, 'Discs overlap.');
inside = r.x - r.radius' >= -1e-12 & r.x + r.radius' <= 1 + 1e-12 & r.y - r.radius' >= -1e-12 & r.y + r.radius' <= 1 + 1e-12;
verifyTrue(testCase, all(inside(:)), 'A disc left the box.');
verifyGreaterThan(testCase, r.collisions, 500);
end

function testEnergyLostAddsUpOverTheEvents(testCase)
% The billiards break (e = 0.95, e_w = 0.8): each disc collision with impulse
% J loses J² (1 − e) / (2 μ (1 + e)), each wall hit J² (1 − e_w) / (2 m (1 + e_w)).
s = dlab.sims.collisions.initialState(struct('mode', 'billiards', 'radius', 0.028575, 'mass', 0.17, ...
    'W', 2.24, 'H', 1.12, 'cueSpeed', 8, 'cueAngle', 0));
p = struct('pos', s.pos, 'vel', s.vel, 'radius', s.radius, 'mass', s.mass, 'e', 0.95, 'ew', 0.8, ...
    'W', 2.24, 'H', 1.12, 'boundary', 'walls', 'tspan', 6, 'dtOut', 0.01, 'maxEvents', 1e5);
r = dlab.sims.collisions.simulateCollisions(p);
pair = r.events(:, 3) > 0;
J = r.events(:, 4);
lost = sum(J(pair).^2 * 0.05 / (2 * 0.085 * 1.95)) + sum(J(~pair).^2 * 0.2 / (2 * 0.17 * 1.8));
verifyEqual(testCase, r.KE(1) - r.KE(end), lost, 'RelTol', 1e-12);
verifyEqual(testCase, r.KE(1), 0.5 * 0.17 * 64, 'RelTol', 1e-15);
% Elastic everywhere: the same break keeps its energy.
[p.e, p.ew] = deal(1);
r = dlab.sims.collisions.simulateCollisions(p);
verifyEqual(testCase, r.KE, r.KE(1) * ones(size(r.KE)), 'RelTol', 1e-13);
end

function testMaxwellStartHasTheMeanEnergyOfV0(testCase)
g = gasParams(150, 'walls');
g.velocityInit = 'maxwell';
g.v0 = 2;
s = dlab.sims.collisions.initialState(g);
verifyEqual(testCase, mean(sum(s.vel.^2, 2)), 4, 'RelTol', 1e-12);
end
