function tests = test_simulateAttractor
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base(model)
p = struct('model', model, 'sigma', 10, 'rho', 28, 'beta', 8/3, 'a', 0.2, 'b', 0.2, 'c', 5.7, ...
    'alpha', 15.6, 'betaChua', 28, 'm0', -1.143, 'm1', -0.714, 'x0', 1, 'y0', 1, 'z0', 1, ...
    'delta', 1e-8, 'tspan', 200, 'dt', 0.01, 'transient', 0.1);
end

function testLorenzExponent(testCase)
% Independent reference: the published largest Lyapunov exponent of the Lorenz system.
% Largest Lyapunov exponent of the Lorenz system, σ = 10, ρ = 28, β = 8/3:
% 0.9056 (Sprott, Chaos and Time-Series Analysis, 2003).
p = base('lorenz');
p.tspan = 1000;
r = dlab.sims.attractors.simulateAttractor(p);
verifyEqual(testCase, r.lambda, 0.9056, 'AbsTol', 0.02);
verifyGreaterThan(testCase, r.distinct, 32, 'Chaotic: the maxima of z never repeat.');
verifyFalse(testCase, r.settled);
% The twins: exponential separation, then saturation at the attractor's size.
verifyLessThan(testCase, r.divergenceTime, 40);
verifyLessThan(testCase, max(r.separation), 2 * r.extent);
end

function testLorenzEquilibria(testCase)
% C± = (±√(β(ρ − 1)), ±√(β(ρ − 1)), ρ − 1); below the Hopf point
% ρ_H = σ(σ + β + 3)/(σ − β − 1) ≈ 24.74 the motion spirals onto one.
p = base('lorenz');
p.rho = 14;
r = dlab.sims.attractors.simulateAttractor(p);
k = sqrt(8/3 * 13);
verifyEqual(testCase, r.equilibria, [0 0 0; k k 13; -k -k 13], 'AbsTol', 1e-12);
verifyTrue(testCase, r.settled);
verifyEqual(testCase, r.X(end, :), [k k 13], 'AbsTol', 1e-3);
verifyLessThan(testCase, r.lambda, 0);
verifyEqual(testCase, r.distinct, 0);
end

function testRosslerPeriodDoubling(testCase)
% a = b = 0.2: period-1, -2, -4 as c grows; chaos at c = 5.7 with
% λ ≈ 0.0714 (Sprott 2003).
counts = zeros(1, 3);
cs = [2.5 3.5 4.0];
for k = 1:3
    p = base('rossler');
    [p.c, p.tspan, p.dt, p.transient] = deal(cs(k), 600, 0.02, 0.3);
    r = dlab.sims.attractors.simulateAttractor(p);
    counts(k) = r.distinct;
    verifyLessThan(testCase, abs(r.lambda), 0.01, sprintf('c = %g is periodic', cs(k)));
end
verifyEqual(testCase, counts, [1 2 4]);
p = base('rossler');
[p.tspan, p.dt, p.transient] = deal(2000, 0.02, 0.05);
r = dlab.sims.attractors.simulateAttractor(p);
verifyEqual(testCase, r.lambda, 0.0714, 'AbsTol', 0.01);
verifyEqual(testCase, r.sectionName, "x");
end

function testChuaDoubleScroll(testCase)
% Equilibria at the origin and ±((m1 − m0)/(m1 + 1), 0, ∓·) = ±(1.5, 0, −1.5);
% the double scroll visits both sides.
p = base('chua');
[p.x0, p.y0, p.z0, p.tspan] = deal(0.7, 0, 0, 300);
r = dlab.sims.attractors.simulateAttractor(p);
verifyEqual(testCase, r.equilibria, [0 0 0; 1.5 0 -1.5; -1.5 0 1.5], 'AbsTol', 1e-12);
verifyLessThan(testCase, min(r.X(r.steady, 1)), -1);
verifyGreaterThan(testCase, max(r.X(r.steady, 1)), 1);
verifyGreaterThan(testCase, r.lambda, 0.2);
end

function testTangentExponentMatchesALinearSystem(testCase)
% Rössler with c below the fold: with a = b = 0 and c > 0, z decays as
% e^(−c t) and (x, y) rotate (a centre), so the largest exponent is 0
% and the tangent method must find it, not the twins' saturation.
p = base('rossler');
[p.a, p.b, p.c, p.x0, p.y0, p.z0, p.tspan] = deal(1e-9, 0, 1, 1, 0, 0, 100);
r = dlab.sims.attractors.simulateAttractor(p);
verifyLessThan(testCase, abs(r.lambda), 1e-3);
end

function testMaximaDoNotDependOnTheOutputStep(testCase)
% The first maxima of z from (1, 1, 1) at σ = 10, ρ = 28, β = 8/3, from an
% independent integration (SciPy DOP853, RelTol 1e-12, event z' = 0;
% verification sheet). A parabola through three samples was up to 4e-3 off
% at the default step (7e-3 at ρ = 160), and worse at coarser steps; the
% solver's event detection does not depend on the step.
reference = [47.840828629 29.36233592 29.507895129 29.668189249 29.840534478 30.026247554 ...
    30.226883983 30.444301735 30.680748975 30.938986054 31.222459126 31.535554048];
times = [0.3813787 1.0002732 1.6208206 2.2417332 2.8633094 3.4856539 4.1088914 4.7331718 ...
    5.3586765 5.9856279 6.6143022 7.2450478];
for dt = [0.01 0.05 0.2]
    p = base('lorenz');
    [p.tspan, p.dt, p.transient] = deal(7.5, dt, 0);
    r = dlab.sims.attractors.simulateAttractor(p);
    verifyEqual(testCase, r.maxima', reference, sprintf('maxima at dt = %g', dt), 'AbsTol', 1e-6);
    verifyEqual(testCase, r.maximaTimes', times, sprintf('times at dt = %g', dt), 'AbsTol', 1e-6);
end
end

function testChuaEquilibriaOnlyWhereTheyExist(testCase)
% Outer equilibria ±(k, 0, −k) need k = (m1 − m0)/(m1 + 1) ≥ 1; for
% k ≤ −1 the formula gives points that are not equilibria.
cases = [-1.143 -0.714; 2 0; -0.5 -2; 0.5 0.2];   % k = 1.5, −2, 1.5 (m1 < −1), −1/4
expected = [3 1 3 1];
for j = 1:size(cases, 1)
    p = base('chua');
    [p.m0, p.m1, p.tspan, p.dt] = deal(cases(j, 1), cases(j, 2), 0.1, 0.01);
    r = dlab.sims.attractors.simulateAttractor(p);
    verifyEqual(testCase, size(r.equilibria, 1), expected(j), sprintf('m0 = %g, m1 = %g', cases(j, :)));
    for E = r.equilibria'
        g = p.m1 * E(1) + 0.5 * (p.m0 - p.m1) * (abs(E(1) + 1) - abs(E(1) - 1));
        rate = [p.alpha * (E(2) - E(1) - g); E(1) - E(2) + E(3); -p.betaChua * E(2)];
        verifyLessThan(testCase, norm(rate), 1e-12, 'Each listed equilibrium is one.');
    end
end
end

function testChuaExponent(testCase)
% Independent integration (Benettin with QR, 3000 time units): λ1 = 0.428
% at these constants (0.437 at m0 = −8/7, m1 = −5/7); the spectrum
% (0.428, 0, −4.23). Over 1000 units the estimate spreads 0.414–0.463 with
% the start, and round-off differs between platforms (0.435 on Windows,
% 0.463 on Linux CI), so the tolerance spans that spread.
p = base('chua');
[p.x0, p.y0, p.z0, p.tspan] = deal(0.7, 0, 0, 1000);
r = dlab.sims.attractors.simulateAttractor(p);
verifyEqual(testCase, r.lambda, 0.43, 'AbsTol', 0.04);
end

function testLorenzPeriodicWindow(testCase)
% ρ = 160: after a chaotic transient the motion settles on a cycle with two
% maxima of z, 188.65839 and 216.63417 (independent integration); λ ≈ 0.
p = base('lorenz');
[p.rho, p.tspan, p.transient] = deal(160, 60, 0.5);
r = dlab.sims.attractors.simulateAttractor(p);
verifyEqual(testCase, r.distinct, 2);
verifyLessThan(testCase, abs(r.lambda), 0.01);
verifyEqual(testCase, sort(uniquetol(r.maxima, 1e-3))', [188.65839 216.63417], 'AbsTol', 1e-4);
end

function testGrowthLineFollowsTheTwins(testCase)
% The line A·e^{λt} passes through the twins' exponential growth (it was
% drawn through δ at t = 0, a decade or more away from the data), and the
% twins' growth rate there is λ.
p = base('lorenz');
p.tspan = 100;
r = dlab.sims.attractors.simulateAttractor(p);
window = r.separation > 1e-6 & r.separation < 1e-2 * r.extent & r.t < r.divergenceTime;
gap = log(r.separation(window)) - log(r.growthAmplitude * exp(r.lambda * r.t(window)));
verifyLessThan(testCase, median(abs(gap)), 1.5);
slope = polyfit(r.t(window), log(r.separation(window)), 1);
verifyEqual(testCase, slope(1), r.lambda, 'RelTol', 0.15);
% No growth to fit: a fixed point, and a periodic orbit.
p.rho = 14;
verifyTrue(testCase, isnan(dlab.sims.attractors.simulateAttractor(p).growthAmplitude));
end

function testRunningEstimateSkipsItsFirstMoments(testCase)
p = base('chua');
[p.x0, p.y0, p.z0, p.tspan] = deal(0.7, 0, 0, 150);
r = dlab.sims.attractors.simulateAttractor(p);
elapsed = r.lambdaT - r.lambdaT(1);
verifyTrue(testCase, all(isnan(r.lambdaHistory(elapsed < 2))));
verifyTrue(testCase, all(isfinite(r.lambdaHistory(elapsed >= 2))));
verifyLessThan(testCase, max(abs(r.lambdaHistory), [], 'omitnan'), 3, 'No spike swamps the plot.');
end

function testCancelKeepsTheRunSoFar(testCase)
p = base('lorenz');
calls = 0;
p.progressFcn = @(~) stopAfterTwo();
r = dlab.sims.attractors.simulateAttractor(p);
verifyFalse(testCase, r.complete);
verifyLessThan(testCase, r.t(end), p.tspan);
verifyEqual(testCase, numel(r.t), size(r.X, 1));
    function stop = stopAfterTwo()
        calls = calls + 1;
        stop = calls >= 2;
    end
end

function testBadInputIsRejected(testCase)
p = base('lorenz');
p.model = 'henon';
verifyError(testCase, @() dlab.sims.attractors.simulateAttractor(p), 'attractors:InvalidParameter');
p = base('lorenz');
p.dt = 0;
verifyError(testCase, @() dlab.sims.attractors.simulateAttractor(p), 'attractors:InvalidParameter');
end
