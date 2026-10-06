function tests = test_simulateOscillator
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base(model)
p = struct('model', model, 'delta', 0.3, 'alpha', -1, 'beta', 1, 'mu', 1, 'q', 2, 'A', 0, 'omega', 1, ...
    'x0', 0.5, 'v0', 0, 'periods', 100, 'tspan', 200, 'transient', 0.5, 'samplesPerPeriod', 100);
end

function p = pendulum(A)
p = base('pendulum');
[p.A, p.omega, p.x0, p.periods, p.samplesPerPeriod] = deal(A, 2/3, 0, 200, 40);
end

function testVanDerPolLimitCycle(testCase)
r = dlab.sims.nonlinear.simulateOscillator(base('vanderpol'));
verifyEqual(testCase, mean(r.poincare(:, 1)), 2.0086, 'AbsTol', 1e-3);
verifyEqual(testCase, r.cyclePeriod, 6.6633, 'AbsTol', 1e-3);
verifyEqual(testCase, r.distinct, 1);
p = base('vanderpol');
p.mu = 0.1;
p.tspan = 600;
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, mean(r.poincare(:, 1)), 2.000, 'AbsTol', 2e-3);
end

function testLinearDuffingFrequency(testCase)
p = base('duffing');
[p.alpha, p.beta, p.delta, p.x0, p.tspan] = deal(2, 0, 0, 0.01, 1000);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, r.dominantFrequency, sqrt(2), 'RelTol', 1e-3);
verifyEqual(testCase, r.energy, r.energy(1) * ones(size(r.energy)), 'Undamped energy is conserved (RK4: 3e-6 here).', 'RelTol', 1e-5);
end

function testPendulumPeriodDoubling(testCase)
% Baker & Gollub: q = 2, ω = 2/3.
r = dlab.sims.nonlinear.simulateOscillator(pendulum(0.9));
verifyEqual(testCase, r.distinct, 1, 'A = 0.9: period-1.');
r = dlab.sims.nonlinear.simulateOscillator(pendulum(1.07));
verifyEqual(testCase, r.distinct, 2, 'A = 1.07: period-2.');
% It swings just past the inverted position (by 0.035 rad) and falls back:
% not a turn over the top, and its amplitude is (max − min)/2.
verifyFalse(testCase, r.overTheTop);
verifyEqual(testCase, r.amplitude, 2.6824, 'AbsTol', 1e-3);
for A = [1.15 1.5]
    r = dlab.sims.nonlinear.simulateOscillator(pendulum(A));
    verifyGreaterThan(testCase, r.distinct, 32, sprintf('A = %g: chaotic.', A));
    verifyTrue(testCase, all(abs(r.poincare(:, 1)) <= pi), 'Section angles are wrapped.');
    verifyTrue(testCase, r.overTheTop, 'It turns over the top.');
    verifyTrue(testCase, isnan(r.amplitude), 'No amplitude for an angle that runs on.');
end
% The windows of order inside the chaotic band (Baker & Gollub, Chaotic
% Dynamics, ch. 3; also a separate DOP853 integration): 1.35 period-1, 1.45 period-2,
% 1.47 period-4.
expected = [1 2 4];
A = [1.35 1.45 1.47];
for k = 1:3
    r = dlab.sims.nonlinear.simulateOscillator(pendulum(A(k)));
    verifyEqual(testCase, r.distinct, expected(k), sprintf('A = %g', A(k)));
end
end

function testSettlesToRest(testCase)
% Free and damped: after the transient only rounding noise is left. No
% dominant frequency is made up from it.
p = base('duffing');
[p.alpha, p.beta, p.delta] = deal(1, 1, 0.3);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyTrue(testCase, r.atRest);
verifyTrue(testCase, isnan(r.dominantFrequency));
p.delta = 5;                                        % overdamped: no maxima at all
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyTrue(testCase, r.atRest);
r = dlab.sims.nonlinear.simulateOscillator(base('vanderpol'));
verifyFalse(testCase, r.atRest, 'A limit cycle is not at rest.');
end

function testPotentialHoldsOnlyItsCoefficients(testCase)
% A saved result must not carry the progress callback (and with it the app).
p = base('duffing');
p.progressFcn = @(fraction) false;
r = dlab.sims.nonlinear.simulateOscillator(p);
info = functions(r.potential);
verifyEqual(testCase, sort(string(fieldnames(info.workspace{1})))', ["alpha" "beta"]);
verifyEqual(testCase, r.potential(2), -1 * 4 / 2 + 16 / 4);
end

function testHardeningResonanceJumps(testCase)
p = base('duffing');
[p.delta, p.alpha, p.beta, p.A, p.x0, p.periods, p.transient, p.samplesPerPeriod] = ...
    deal(0.1, 1, 0.1, 0.5, 0, 150, 0.6, 40);
omega = 1:0.1:2;
amplitude = zeros(size(omega));
for k = 1:numel(omega)
    p.omega = omega(k);
    r = dlab.sims.nonlinear.simulateOscillator(p);
    amplitude(k) = r.amplitude;
end
ratio = amplitude(1:end-1) ./ amplitude(2:end);
verifyGreaterThan(testCase, max(ratio), 1.5, 'The response drops off the upper branch.');
end

function testHardeningHysteresisMatchesHarmonicBalance(testCase)
% Sweep ω up and then down, each run starting where the last one ended
% (runs are whole forcing periods, so the drive's phase carries on). The
% harmonic balance [(α − ω² + 3βa²/4)² + (δω)²] a² = A² has three
% amplitudes for 1.2165 < ω < 1.4005 (independent root count): the
% response must jump down between 1.40 and 1.45 going up, and up between
% 1.20 and 1.25 coming down.
p = base('duffing');
[p.delta, p.alpha, p.beta, p.A, p.x0, p.v0, p.periods, p.transient, p.samplesPerPeriod] = ...
    deal(0.1, 1, 0.1, 0.5, 0, 0, 150, 0.6, 40);
omega = 1:0.05:2;
up = zeros(size(omega));
down = up;
for k = 1:numel(omega)
    p.omega = omega(k);
    r = dlab.sims.nonlinear.simulateOscillator(p);
    [up(k), p.x0, p.v0] = deal(r.amplitude, r.x(end), r.v(end));
end
[p.x0, p.v0] = deal(0, 0);
for k = numel(omega):-1:1
    p.omega = omega(k);
    r = dlab.sims.nonlinear.simulateOscillator(p);
    [down(k), p.x0, p.v0] = deal(r.amplitude, r.x(end), r.v(end));
end
[~, jumpUp] = max(up(1:end-1) ./ up(2:end));
[~, jumpDown] = max(down(1:end-1) ./ down(2:end));
verifyEqual(testCase, omega(jumpUp), 1.40, 'Going up, the last large response is at 1.40.', 'AbsTol', 1e-9);
verifyEqual(testCase, omega(jumpDown), 1.20, 'Coming down, the first large response is at 1.20.', 'AbsTol', 1e-9);
% Inside the bistable band both branches, against harmonic balance (2 %).
k = find(abs(omega - 1.3) < 1e-9);
verifyEqual(testCase, up(k), 3.21526, 'Upper branch at ω = 1.3.', 'RelTol', 0.02);
verifyEqual(testCase, down(k), 0.75772, 'Lower branch at ω = 1.3.', 'RelTol', 0.02);
end

function testUndampedDuffingPeriodMatchesEllipticIntegral(testCase)
% Independent reference: the Duffing period as an elliptic integral.
% T = 4 K(m) / √(α + βX²), m = βX² / (2(α + βX²)), from x = X at rest
% (scipy.special.ellipk, checked against direct quadrature).
cases = [1 1 1 4.768022029; 1 -1 0.5 6.978326992; 1 -0.5 1 8.008619044; -1 1 2 4.685680337];
for k = 1:size(cases, 1)
    p = base('duffing');
    [p.alpha, p.beta, p.x0, p.v0, p.delta] = deal(cases(k, 1), cases(k, 2), cases(k, 3), 0, 0);
    r = dlab.sims.nonlinear.simulateOscillator(p);
    verifyEqual(testCase, r.cyclePeriod, cases(k, 4), sprintf('α = %g, β = %g, X = %g', cases(k, 1:3)), 'RelTol', 5e-6);
end
% Weakly nonlinear: ω ≈ √α (1 + 3βX²/(8α)) = 1.00375 (exact 1.0037418).
[p.alpha, p.beta, p.x0] = deal(1, 0.04, 0.5);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, 2 * pi / r.cyclePeriod, 1.00375, 'Lindstedt frequency shift.', 'AbsTol', 2e-5);
end

function testVanDerPolPeriodsSmallAndLargeMu(testCase)
% Independent values: Radau at RelTol 1e-11 (scipy). Small μ: T ≈ 2π(1 + μ²/16);
% large μ: T ≈ (3 − 2 ln 2) μ + 3 · 2.338 μ^(−1/3) (relaxation).
p = base('vanderpol');
[p.mu, p.tspan, p.samplesPerPeriod] = deal(0.1, 600, 60);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, r.cyclePeriod, 2 * pi * (1 + 0.1^2 / 16), 'AbsTol', 1e-4);
[p.mu, p.tspan, p.samplesPerPeriod] = deal(5, 200, 200);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, r.cyclePeriod, 11.612231, 'μ = 5 (the preset).', 'AbsTol', 1e-4);
verifyEqual(testCase, mean(r.poincare(:, 1)), 2.021508, 'AbsTol', 1e-4);
[p.mu, p.tspan, p.samplesPerPeriod] = deal(50, 1000, 60);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, r.cyclePeriod, 82.508334, 'μ = 50 at the default samples.', 'RelTol', 1e-5);
verifyEqual(testCase, mean(r.poincare(:, 1)), 2.002956, ...
    'The maximum right after the fast jump (was 2.084 with interpolation over a whole sample).', 'AbsTol', 1e-4);
verifyEqual(testCase, r.distinct, 1);
verifyEqual(testCase, r.cyclePeriod, (3 - 2 * log(2)) * 50 + 3 * 2.338107 * 50^(-1/3), 'RelTol', 2e-3);
end

function testStroboscopicSection(testCase)
% A linear forced oscillator settles to one point per period.
p = base('duffing');
[p.alpha, p.beta, p.delta, p.A, p.omega, p.periods] = deal(1, 0, 0.5, 1, 2, 60);
r = dlab.sims.nonlinear.simulateOscillator(p);
verifyEqual(testCase, r.distinct, 1);
verifyEqual(testCase, r.poincareTimes / (2 * pi / 2), round(r.poincareTimes / (2 * pi / 2)), 'AbsTol', 1e-9);
X = 1 / abs(1 - 4 + 1i * 0.5 * 2);
verifyEqual(testCase, r.amplitude, X, 'RelTol', 1e-4);
end

function testRejectsBadInput(testCase)
p = base('duffing');
p.model = 'lorenz';
verifyError(testCase, @() dlab.sims.nonlinear.simulateOscillator(p), 'nonlinear:InvalidParameter');
p = base('pendulum');
p.q = 0;
verifyError(testCase, @() dlab.sims.nonlinear.simulateOscillator(p), 'nonlinear:InvalidParameter');
p = base('duffing');
[p.tspan, p.samplesPerPeriod] = deal(1e5, 1000);   % 1.6e7 samples
verifyError(testCase, @() dlab.sims.nonlinear.simulateOscillator(p), 'nonlinear:InvalidParameter');
end
