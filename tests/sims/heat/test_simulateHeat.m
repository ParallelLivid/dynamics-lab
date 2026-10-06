function tests = test_simulateHeat
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
% A copper bar, 1 m, both ends at 20 °C, a sine mode of 50 °C on top.
fixed = struct('type', 'dirichlet', 'T', 20, 'flux', 0, 'h', 0, 'Tinf', 0);
p = struct('L', 1, 'N', 51, 'k', 401, 'rho', 8960, 'c', 385, 'q', 0, 'scheme', 'explicit', ...
    'dt', 1, 'tspan', 1800, 'dtOut', 30, 'left', fixed, 'right', fixed, ...
    'initial', struct('type', 'sine', 'T0', 20, 'amplitude', 50, 'mode', 1, 'position', 0.5, 'width', 0.1));
end

function testExplicitSchemeDecaysByItsAmplificationFactor(testCase)
% FTCS multiplies a sine mode by g = 1 − 4r sin²(πΔx/2L) every step.
r = dlab.sims.heat.simulateHeat(base());
g = 1 - 4 * r.r * sin(pi * 0.02 / 2)^2;
steps = round(r.t(end) / r.dt);
verifyEqual(testCase, (r.T(end, 26) - 20) / 50, g^steps, 'RelTol', 1e-10);
verifyLessThan(testCase, max(abs(r.T(:) - r.exact(:))), 0.01);
end

function testCrankNicolsonIsSecondOrderInTime(testCase)
% Against the semi-discrete solution (no spatial error): CN slope 2, BE 1.
p = base();
p.tspan = 600;
p.dtOut = 600;
steps = [40 20 10 5];
for scheme = {'cranknicolson', 'implicit'}
    p.scheme = scheme{1};
    errors = zeros(size(steps));
    for k = 1:numel(steps)
        p.dt = steps(k);
        r = dlab.sims.heat.simulateHeat(p);
        rate = 4 * r.alpha / 0.02^2 * sin(pi * 0.02 / 2)^2;
        semi = 20 + 50 * exp(-rate * 600) * sin(pi * r.x');
        errors(k) = max(abs(r.T(end, :) - semi));
    end
    slope = polyfit(log(steps), log(errors), 1);
    expected = 2 - strcmp(scheme{1}, 'implicit');
    verifyEqual(testCase, slope(1), expected, 'AbsTol', 0.1, scheme{1});
end
end

function testExplicitSchemeIsUnstableBeyondHalf(testCase)
p = base();
p.initial.type = 'hotspot';
p.initial.amplitude = 80;
alpha = p.k / (p.rho * p.c);
p.dt = 0.55 * 0.02^2 / alpha;
r = dlab.sims.heat.simulateHeat(p);
verifyFalse(testCase, r.stable);
verifyLessThan(testCase, r.blowupTime, p.tspan);
p.dt = 0.5 * 0.02^2 / alpha;
verifyTrue(testCase, dlab.sims.heat.simulateHeat(p).stable);
p.scheme = 'implicit';
p.dt = 20 * 0.02^2 / alpha;
verifyTrue(testCase, dlab.sims.heat.simulateHeat(p).stable, 'Implicit is unconditionally stable.');
end

function testSteadyStates(testCase)
p = base();
p.scheme = 'implicit';
p.initial.type = 'uniform';
p.left.T = 100;
p.right.T = 0;
p.tspan = 40000;
p.dt = 100;
p.dtOut = 40000;
r = dlab.sims.heat.simulateHeat(p);
verifyEqual(testCase, r.T(end, :), 100 - 100 * r.x', 'AbsTol', 1e-6, 'A straight line.');
% Convection at the right end: two thermal resistances in series.
p.right = struct('type', 'robin', 'T', 0, 'flux', 0, 'h', 25, 'Tinf', 20);
r = dlab.sims.heat.simulateHeat(p);
expected = 20 + 80 * (1 / 25) / (1 / 401 + 1 / 25);
verifyEqual(testCase, r.T(end, end), expected, 'RelTol', 1e-4);
end

function testInsulatedRodConservesEnergy(testCase)
p = base();
insulated = struct('type', 'neumann', 'T', 0, 'flux', 0, 'h', 0, 'Tinf', 0);
[p.left, p.right] = deal(insulated);
p.initial.type = 'hotspot';
p.scheme = 'cranknicolson';
p.dt = 5;
r = dlab.sims.heat.simulateHeat(p);
verifyLessThan(testCase, max(abs(r.energy - r.energy(1))) / r.energy(1), 1e-12);
p.left.flux = 1000;
r = dlab.sims.heat.simulateHeat(p);
verifyEqual(testCase, r.energy - r.energy(1), r.heatIn, 'RelTol', 1e-9, 'Heat in = heat stored.');
end

function testTimeVaryingEndTemperature(testCase)
p = base();
p.scheme = 'cranknicolson';
p.left.T = @(t) 20 + 10 * sin(2 * pi * t / 600);
r = dlab.sims.heat.simulateHeat(p);
verifyEqual(testCase, r.T(:, 1), 20 + 10 * sin(2 * pi * r.t / 600), 'AbsTol', 1e-12);
verifyEmpty(testCase, r.exact, 'No exact solution with a varying end.');
end

function testBadInputIsRejected(testCase)
p = base();
p.N = 2;
verifyError(testCase, @() dlab.sims.heat.simulateHeat(p), 'heat:InvalidParameter');
p = base();
p.right = struct('type', 'robin', 'T', 0, 'flux', 0, 'h', 0, 'Tinf', 0);
verifyError(testCase, @() dlab.sims.heat.simulateHeat(p), 'heat:InvalidParameter');
p = base();
p.dt = 1e-5;
p.tspan = 100;
verifyError(testCase, @() dlab.sims.heat.simulateHeat(p), 'heat:TooManySteps');
end

function testEnergyBalanceClosesAtEveryTime(testCase)
% Stored change = heat in, at every output and for every scheme: the heat in
% is weighted in time as the scheme weights it (trapezoidal weights left
% 0.03–0.08 % for explicit and implicit), and a fixed end's half cell is
% counted (a cycling end temperature left 5 % mid-run).
p = base();
p.q = 5e5;
p.left.T = @(t) 20 + 10 * sin(2 * pi * t / 600);
p.right = struct('type', 'robin', 'T', 0, 'flux', 0, 'h', 50, 'Tinf', 10);
for scheme = {'explicit', 'implicit', 'cranknicolson'}
    p.scheme = scheme{1};
    r = dlab.sims.heat.simulateHeat(p);
    gap = (r.energy - r.energy(1)) - r.heatIn;
    verifyLessThan(testCase, max(abs(gap)) / max(abs(r.heatIn)), 1e-10, scheme{1});
end
end
