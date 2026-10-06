function tests = test_double_pendulum_solve
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
p = struct('L1', 1, 'L2', 1, 'm1', 1, 'm2', 1, 'b', 0, 'g', 9.81, 'theta1', 5, 'theta2', 5, ...
    'omega1', 0, 'omega2', 0, 'tspan', 20, 'dt', 0.01, 'twin', false, 'delta', 1e-3, 'lyapunov', false);
end

function testInPhaseNormalMode(testCase)
% Equal rods and bobs: ω² = (g/L)(2 ∓ √2). Started in the in-phase mode
% shape (θ2 = √2 θ1), it swings at the lower frequency alone.
p = base();
p.theta1 = 2;
p.theta2 = 2 * sqrt(2);
[sol, errMsg] = dlab.sims.pendulum.double_pendulum_solve(p);
verifyEmpty(testCase, errMsg);
up = find(sol.theta1(1:end-1) < 0 & sol.theta1(2:end) >= 0);
t = sol.t;
crossings = t(up) - sol.theta1(up) .* (t(up + 1) - t(up)) ./ (sol.theta1(up + 1) - sol.theta1(up));
verifyEqual(testCase, mean(diff(crossings)), 2 * pi / sqrt(9.81 * (2 - sqrt(2))), 'RelTol', 5e-4);
end

function testLightLowerBobIsASinglePendulum(testCase)
p = base();
p.m2 = 1e-6;
p.theta1 = 30;
p.theta2 = 0;
p.tspan = 10;
sol = dlab.sims.pendulum.double_pendulum_solve(p);
single = dlab.sims.pendulum.pendulum_solve(1, 1, 0, 30, 0, 9.81, 10, 0.01);
verifyEqual(testCase, sol.theta1, single.theta, 'AbsTol', 1e-4);
end

function testUndampedEnergyIsConserved(testCase)
p = base();
p.theta1 = 120;
p.theta2 = -20;
p.tspan = 30;
sol = dlab.sims.pendulum.double_pendulum_solve(p);
verifyLessThan(testCase, max(abs(sol.E - sol.E(1))) / abs(sol.E(1)), 1e-7);
verifyEqual(testCase, sol.E, sol.KE + sol.PE, 'AbsTol', 1e-12);
verifyEqual(testCase, hypot(sol.x2 - sol.x1, sol.y2 - sol.y1), ones(size(sol.t)), 'AbsTol', 1e-12);
verifyGreaterThan(testCase, size(sol.poincare, 1), 5);
verifyLessThanOrEqual(testCase, max(abs(sol.poincare(:, 1))), pi);
end

function testDampingDissipatesEnergy(testCase)
p = base();
p.b = 0.5;
p.theta1 = 60;
sol = dlab.sims.pendulum.double_pendulum_solve(p);
verifyTrue(testCase, all(diff(sol.E) <= 1e-9), 'Energy never increases.');
verifyLessThan(testCase, sol.E(end), 0.2 * sol.E(1));
end

function testTwinsDivergeInTheChaoticRegime(testCase)
p = base();
p.theta1 = 150;
p.theta2 = 150;
p.twin = true;
p.delta = 1e-6;
sol = dlab.sims.pendulum.double_pendulum_solve(p);
verifyGreaterThan(testCase, max(sol.separation) / sol.separation(1), 1e5);
verifyTrue(testCase, isfinite(sol.divergenceTime));
verifyLessThan(testCase, sol.divergenceTime, 20);
verifyEqual(testCase, sol.twin.theta2(1) - sol.theta2(1), deg2rad(1e-6), 'AbsTol', 1e-15);
end

function testTwinsStayTogetherForSmallSwings(testCase)
p = base();
p.twin = true;
sol = dlab.sims.pendulum.double_pendulum_solve(p);
verifyTrue(testCase, isnan(sol.divergenceTime));
verifyLessThan(testCase, max(sol.separation), 1e-3);
end

function testLyapunovExponentSeparatesOrderFromChaos(testCase)
p = base();
p.lyapunov = true;
p.theta1 = 120;
p.theta2 = -20;
p.tspan = 30;
chaotic = dlab.sims.pendulum.double_pendulum_solve(p);
verifyGreaterThan(testCase, chaotic.lyapunov.exponent, 0.5);
verifyLessThan(testCase, chaotic.lyapunov.exponent, 3);
p.theta1 = 5;
p.theta2 = 5;
regular = dlab.sims.pendulum.double_pendulum_solve(p);
verifyLessThan(testCase, regular.lyapunov.exponent, 0.1);
end

function testBadInputIsReported(testCase)
p = base();
p.L2 = -1;
[sol, errMsg] = dlab.sims.pendulum.double_pendulum_solve(p);
verifyEmpty(testCase, sol);
verifyNotEmpty(testCase, errMsg);
p = base();
p.dt = 30;
[~, errMsg] = dlab.sims.pendulum.double_pendulum_solve(p);
verifySubstring(testCase, errMsg, 'output step');
end
