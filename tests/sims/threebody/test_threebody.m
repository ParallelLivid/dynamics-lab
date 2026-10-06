function tests = test_threebody
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = arenstorf()
p = struct('mu', 0.012277471, 'state0', [0.994 0 0 0 -2.00158510637908 0], ...
    'tspan', 17.0652165601580, 'dt', 0.01, 'radii', [0 0]);
end

function testEarthMoonLagrangePoints(testCase)
% Independent reference: the published Earth–Moon Lagrange points.
L = dlab.sims.threebody.lagrangePoints(0.01215058);
verifyEqual(testCase, L(1:3, 1)', [0.836915 1.155682 -1.005063], 'AbsTol', 5e-7);
verifyEqual(testCase, L(4, :), [0.5 - 0.01215058, sqrt(3) / 2, 0], 'AbsTol', 1e-15);
for k = 1:5
    verifyLessThan(testCase, norm(dlab.sims.threebody.cr3bpRhs([L(k, :)'; 0; 0; 0], 0.01215058)), 1e-12);
end
end

function testArenstorfOrbitCloses(testCase)
r = dlab.sims.threebody.simulateCr3bp(arenstorf());
verifyLessThan(testCase, norm(r.state(end, :) - r.state(1, :)), 1e-6);
verifyEqual(testCase, char(r.termination), 'completed');
end

function testJacobiConstantIsConserved(testCase)
p = arenstorf();
p.tspan = 10 * p.tspan;
p.dt = 0.05;
r = dlab.sims.threebody.simulateCr3bp(p);
verifyLessThan(testCase, max(abs(r.C - r.C0)), 1e-10);
end

function testExactJacobian(testCase)
% cr3bpJacobian matches finite differences of cr3bpRhs.
mu = 0.01215058;
L = dlab.sims.threebody.lagrangePoints(mu);
for k = [1 4]
    s0 = [L(k, :)'; 0; 0; 0];
    J = dlab.physics.jacobian(@(s) dlab.sims.threebody.cr3bpRhs(s, mu), s0);
    verifyEqual(testCase, dlab.sims.threebody.cr3bpJacobian(mu, L(k, :)), J, 'AbsTol', 1e-7);
end
% Off the plane too.
point = [0.3 0.2 0.1];
J = dlab.physics.jacobian(@(s) dlab.sims.threebody.cr3bpRhs(s, mu), [point'; 0; 0; 0]);
verifyEqual(testCase, dlab.sims.threebody.cr3bpJacobian(mu, point), J, 'AbsTol', 1e-6);
end

function testStabilityOfTheTriangularPoints(testCase)
% L4 is linearly stable below Routh's critical mass ratio 0.03852.
lambda = eig(dlab.sims.threebody.cr3bpJacobian(0.01215058, [0.5 - 0.01215058, sqrt(3) / 2, 0]));
verifyLessThan(testCase, max(abs(real(lambda))), 1e-12);
lambda = eig(dlab.sims.threebody.cr3bpJacobian(0.05, [0.45, sqrt(3) / 2, 0]));
verifyGreaterThan(testCase, max(real(lambda)), 0.1);
L = dlab.sims.threebody.lagrangePoints(0.01215058);
lambda = eig(dlab.sims.threebody.cr3bpJacobian(0.01215058, L(1, :)));
verifyEqual(testCase, nnz(abs(imag(lambda)) < 1e-12 & real(lambda) > 0), 1, 'L1: one unstable real eigenvalue.');
end

function testFigureEight(testCase)
x1 = [0.97000436 -0.24308753 0];
v3 = [-0.93240737 -0.86473146 0];
p = struct('mass', [1; 1; 1], 'pos', [x1; -x1; 0 0 0], 'vel', [-v3 / 2; -v3 / 2; v3], 'soft', 0, ...
    'tspan', 6.32591398, 'dt', 0.01);
r = dlab.sims.threebody.simulateNBody(p);
verifyLessThan(testCase, max(abs(reshape(r.pos(end, :, :) - r.pos(1, :, :), 1, []))), 1e-5);
verifyLessThan(testCase, [r.drift.energy r.drift.momentum r.drift.angular], 1e-9);
end

function testCollisionWithAPrimary(testCase)
p = arenstorf();
[p.mu, p.state0, p.radii, p.tspan] = deal(0.01215058, [0.7 0 0 0.4227 * cosd(30) 0.4227 * sind(30) 0], ...
    [6371 1737.4] / 384400, 30);
r = dlab.sims.threebody.simulateCr3bp(p);
verifyEqual(testCase, char(r.termination), 'collision2');
verifyEqual(testCase, r.r2(end), 1737.4 / 384400, 'RelTol', 1e-6);
end

function testRejectsBadInput(testCase)
p = arenstorf();
p.mu = 0.7;
verifyError(testCase, @() dlab.sims.threebody.simulateCr3bp(p), 'threebody:InvalidParameter');
q = struct('mass', 1, 'pos', [0 0 0], 'vel', [0 0 0], 'soft', 0, 'tspan', 1, 'dt', 0.1);
verifyError(testCase, @() dlab.sims.threebody.simulateNBody(q), 'threebody:InvalidParameter');
end
