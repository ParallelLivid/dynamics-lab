function tests = test_simulateHandling
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = car()
% An understeering family car at 100 km/h, steering stepped by 1° at 0.5 s.
p = struct('m', 1500, 'Iz', 2500, 'a', 1.1, 'b', 1.6, 'Cf', 80000, 'Cr', 110000, 'V', 100 / 3.6, ...
    'tyre', 'linear', 'mu', 0.9, 'g', 9.81, 'steer', @(t) deg2rad(1) * (t >= 0.5), 'tspan', 6, 'dt', 0.01);
end

function p = oversteerCar(V)
p = car();
p.a = 1.5;
p.b = 1.2;
p.Cf = 90000;
p.Cr = 75000;
p.V = V;
end

function K = gradientOf(p)
L = p.a + p.b;
K = p.m / L * (p.b / p.Cf - p.a / p.Cr);
end

function testSteadyYawGain(testCase)
% Independent reference: the linear bicycle model's yaw gain V/(L + K V²).
% r/δ = V / (L + K V²), K = (m/L)(b/Cf − a/Cr): from the linear model and
% at the end of a step-steer run.
p = car();
L = p.a + p.b;
K = gradientOf(p);
gain = p.V / (L + K * p.V^2);
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, r.understeerGradient, K, 'RelTol', 1e-12);
verifyEqual(testCase, r.understeerGradient, 0.0055556, 'AbsTol', 1e-7);
verifyEqual(testCase, r.yawGain, gain, 'RelTol', 1e-10);
verifyEqual(testCase, r.r(end) / r.delta(end), gain, 'RelTol', 1e-5, 'The run settles at the steady state.');
verifyEqual(testCase, r.characteristicSpeed, sqrt(L / K), 'RelTol', 1e-12);
verifyTrue(testCase, isnan(r.criticalSpeed));
verifyTrue(testCase, r.stable);
verifyEqual(testCase, r.ay(end), p.V * r.r(end), 'RelTol', 1e-6, 'Steady turning: a_y = V r.');
end

function testGainPeaksAtTheCharacteristicSpeed(testCase)
p = car();
L = p.a + p.b;
p.V = sqrt(L / gradientOf(p));
[~, ~, info] = dlab.sims.handling.linearModel(p);
verifyEqual(testCase, info.yawGain, p.V / (2 * L), 'RelTol', 1e-10, 'Half the neutral car''s gain.');
for factor = [0.8 1.25]
    q = p;
    q.V = factor * p.V;
    [~, ~, other] = dlab.sims.handling.linearModel(q);
    verifyLessThan(testCase, other.yawGain, info.yawGain);
end
end

function testNeutralSteer(testCase)
p = car();
p.a = 1.35;
p.b = 1.35;
p.Cf = 90000;
p.Cr = 90000;
p.V = 80 / 3.6;
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, r.understeerGradient, 0);
verifyEqual(testCase, r.yawGain, p.V / 2.7, 'RelTol', 1e-10);
verifyEqual(testCase, r.r(end) / r.delta(end), p.V / 2.7, 'RelTol', 1e-5);
verifyTrue(testCase, isnan(r.characteristicSpeed) && isnan(r.criticalSpeed));
end

function testOversteerCriticalSpeed(testCase)
% Unstable above V_crit = √(−L/K), stable below.
p = oversteerCar(20);
K = gradientOf(p);
verifyLessThan(testCase, K, 0);
Vcrit = sqrt(-2.7 / K);
verifyEqual(testCase, Vcrit, 27.0, 'AbsTol', 1e-3);
below = oversteerCar(0.95 * Vcrit);
above = oversteerCar(1.05 * Vcrit);
[A, ~, info] = dlab.sims.handling.linearModel(below);
verifyEqual(testCase, info.criticalSpeed, Vcrit, 'RelTol', 1e-12);
verifyLessThan(testCase, max(real(eig(A))), 0);
verifyEqual(testCase, info.yawGain, below.V / (2.7 + K * below.V^2), 'RelTol', 1e-10);
[A, ~, info] = dlab.sims.handling.linearModel(above);
verifyGreaterThan(testCase, max(real(eig(A))), 0);
verifyFalse(testCase, info.stable);
verifyTrue(testCase, isnan(info.yawGain));
at = oversteerCar(Vcrit);
[A, ~, ~] = dlab.sims.handling.linearModel(at);
verifyEqual(testCase, det(A), 0, 'AbsTol', 1e-9 * norm(A)^2, 'A pole crosses zero at V_crit.');

% Simulations at 0.8 and 1.2 V_crit: below settles at the linear gain,
% above diverges and spins.
below = oversteerCar(0.8 * Vcrit);
below.steer = @(t) deg2rad(0.5) * (t >= 0.5);
below.tspan = 15;
r = dlab.sims.handling.simulateHandling(below);
verifyEqual(testCase, r.termination, "completed");
verifyEqual(testCase, r.r(end) / r.delta(end), below.V / (2.7 + K * below.V^2), 'RelTol', 1e-5);
above = oversteerCar(1.2 * Vcrit);
above.steer = below.steer;
r = dlab.sims.handling.simulateHandling(above);
verifyEqual(testCase, r.termination, "spun");
verifyEqual(testCase, abs(rad2deg(r.beta(end))), 30, 'AbsTol', 1e-3);
end

function testSaturatingMatchesLinearAtSmallSteer(testCase)
p = car();
p.steer = @(t) deg2rad(0.2) * (t >= 0.5);
linear = dlab.sims.handling.simulateHandling(p);
p.tyre = 'saturating';
saturating = dlab.sims.handling.simulateHandling(p);
verifyLessThan(testCase, max(abs(saturating.r - linear.r)) / max(abs(linear.r)), 0.01);
verifyLessThan(testCase, max(abs(saturating.ay - linear.ay)) / max(abs(linear.ay)), 0.01);
end

function testFrictionLimitsLateralAcceleration(testCase)
% 8° at 80 km/h, where linear tyres would give 1.3 g: a_y levels off just
% below μ g, and the front slips far more than the rear (understeer at
% the limit). Steering 15°, the car slides out, but a_y never passes μ g.
p = car();
p.V = 80 / 3.6;
p.tyre = 'saturating';
p.steer = @(t) deg2rad(8) * min(t, 1);
p.tspan = 8;
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, r.termination, "completed");
verifyGreaterThan(testCase, r.yawGain * deg2rad(8) * p.V, 1.3 * p.mu * p.g, 'What linear tyres would give.');
verifyLessThan(testCase, max(abs(r.ay)), p.mu * p.g);
verifyGreaterThan(testCase, abs(r.ay(end)), 0.95 * p.mu * p.g);
verifyGreaterThan(testCase, abs(r.alphaF(end)), 1.5 * abs(r.alphaR(end)));
p.steer = @(t) deg2rad(15) * min(t, 1);
r = dlab.sims.handling.simulateHandling(p);
verifyLessThanOrEqual(testCase, max(abs(r.ay)), p.mu * p.g);
verifyEqual(testCase, r.Fzf + r.Fzr, p.m * p.g, 'RelTol', 1e-12);
verifyEqual(testCase, r.Fzf, p.m * p.g * p.b / 2.7, 'RelTol', 1e-12);
end

function testPathIsACircleInSteadyTurning(testCase)
% The centre of mass moves on a circle of radius |velocity| / r.
p = car();
p.steer = @(t) deg2rad(1) + 0 * t;
p.tspan = 12;
r = dlab.sims.handling.simulateHandling(p);
late = r.t > 6;
x = r.x(late);
y = r.y(late);
c = [2 * x, 2 * y, ones(size(x))] \ (x.^2 + y.^2);      % algebraic circle fit
radius = sqrt(c(3) + c(1)^2 + c(2)^2);
verifyEqual(testCase, radius, hypot(p.V, r.v(end)) / r.r(end), 'RelTol', 1e-5);
verifyEqual(testCase, r.psi(end), trapz(r.t, r.r), 'RelTol', 1e-4);
p.steer = @(t) 0 * t;
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, r.x, p.V * r.t, 'RelTol', 1e-9);
verifyEqual(testCase, r.y, zeros(size(r.t)));
end

function testRejectsBadInput(testCase)
p = car();
p.m = 0;
verifyError(testCase, @() dlab.sims.handling.simulateHandling(p), 'handling:InvalidParameter');
p = car();
p.tyre = 'pacejka';
verifyError(testCase, @() dlab.sims.handling.simulateHandling(p), 'handling:InvalidParameter');
p = car();
p.tyre = 'saturating';
p.mu = 0;
verifyError(testCase, @() dlab.sims.handling.simulateHandling(p), 'handling:InvalidParameter');
end

function testAgainstAnIndependentIntegration(testCase)
% scipy solve_ivp (RK45, rtol 1e-11) of the same model, written
% separately: the default 2° step at 100 km/h (ζ = 0.661, a_y overshoot
% 3.44 %), and the saturating-tyre ramp to 8° at 80 km/h.
p = car();
p.steer = @(t) deg2rad(2) * (t >= 0.5);
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, max(abs(r.ay)) / 9.81, 0.40648, 'RelTol', 1e-4);
verifyEqual(testCase, rad2deg(max(abs(r.r))), 9.39797, 'RelTol', 1e-4);
verifyEqual(testCase, rad2deg(max(abs(r.beta))), 0.82393, 'RelTol', 1e-4);
verifyEqual(testCase, rad2deg(r.psi(end)), 43.57378, 'RelTol', 1e-5);
verifyEqual(testCase, [r.x(end) r.y(end)], [153.152 53.3286], 'RelTol', 1e-5);
p = car();
[p.tyre, p.V] = deal('saturating', 80 / 3.6);
p.steer = @(t) deg2rad(8 * min(max((t - 0.5) / 5, 0), 1));
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, max(abs(r.ay)) / 9.81, 0.86226, 'RelTol', 1e-4);
verifyEqual(testCase, r.alphaF(end) / r.alphaR(end), 1.9546, 'RelTol', 1e-3);
end

function testSpinJustAboveTheCriticalSpeedIsSlow(testCase)
% V_crit = 97.2 km/h. A 1° step spins the oversteering car at 5.27 s at
% 100 km/h, but only at 6.29 s at 98 km/h (after a 6 s run): the lesson
% asks for 100 km/h or more.
p = oversteerCar(100 / 3.6);
r = dlab.sims.handling.simulateHandling(p);
verifyEqual(testCase, r.termination, "spun");
verifyEqual(testCase, r.t(end), 5.2663, 'AbsTol', 1e-3);
p = oversteerCar(98 / 3.6);
verifyEqual(testCase, dlab.sims.handling.simulateHandling(p).termination, "completed");
p.tspan = 10;
verifyEqual(testCase, dlab.sims.handling.simulateHandling(p).t(end), 6.2858, 'AbsTol', 1e-3);
end
