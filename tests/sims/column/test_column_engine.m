function tests = test_column_engine
%TEST_COLUMN_ENGINE Golden values for the column buckling engine: Euler
%   loads, the elastica against elliptic integrals, the imperfection
%   amplification and first yield, and the Southwell plot.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function m = steelTube(endCondition)
% A 3 m steel tube, 60 × 4 mm (A = 703.7 mm², I = 2.773e5 mm⁴).
[D, d] = deal(0.060, 0.052);
m = struct('endCondition', endCondition, 'L', 3, 'E', 200e9, 'yieldStress', 250e6, ...
    'A', pi / 4 * (D^2 - d^2), 'I', pi / 64 * (D^4 - d^4), 'c', D / 2, 'P', 40e3, 'loadRatio', NaN, ...
    'e0', 3e-3, 'analysis', 'linear', 'scatter', 0);
end

function testEulerLoadsForAllEndConditions(testCase)
m = steelTube('pinned');
EI = m.E * m.I;
beta = fzero(@(b) tan(b) - b, [4.4 4.6]);       % fixed–pinned: tan βL = βL
expected = struct('pinned', pi^2 * EI / m.L^2, 'fixedfree', pi^2 * EI / (2 * m.L)^2, ...
    'fixedpinned', beta^2 * EI / m.L^2, 'fixedfixed', 4 * pi^2 * EI / m.L^2);
for name = ["pinned" "fixedfree" "fixedpinned" "fixedfixed"]
    m.endCondition = name;
    r = dlab.sims.column.column_engine(m);
    verifyEqual(testCase, r.Pcr, expected.(name), 'RelTol', 1e-9, name);
    verifyEqual(testCase, r.effectiveLength, pi * sqrt(EI / expected.(name)), 'RelTol', 1e-9, name);
end
verifyEqual(testCase, r.Ks(3), 0.699, 'AbsTol', 5e-4, 'K = 0.699 for fixed–pinned.');
verifyEqual(testCase, expected.pinned / 1e3, 60.81, 'RelTol', 1e-3, 'The default tube buckles at 60.8 kN.');
end

function testModeShapesMeetTheirEndConditions(testCase)
e = dlab.sims.column.eulerModes(1, 1, 2001);
h = e.x(2) - e.x(1);
for k = 1:4
    phi = e.modes(:, k);
    verifyEqual(testCase, max(abs(phi)), 1, 'AbsTol', 1e-6, e.names(k));
    verifyEqual(testCase, phi(1), 0, 'AbsTol', 1e-12, e.names(k) + ": no deflection at the base");
    if e.names(k) ~= "fixedfree"
        verifyEqual(testCase, phi(end), 0, 'AbsTol', 1e-12, e.names(k) + ": no deflection at the top");
    end
    % The moment factor: EI·max|φ''| / P_cr, from finite differences.
    curvature = diff(phi, 2) / h^2;
    verifyEqual(testCase, max(abs(curvature)) / (pi / e.K(k))^2, e.momentFactors(k), 'RelTol', 1e-3, e.names(k));
end
end

function testElasticaMatchesEllipticIntegrals(testCase)
% Independent reference: the elastica in complete elliptic integrals.
% P/P_cr = (2 K(k)/π)², k = sin(α/2); the crest at 2k/√μ; the chord
% 2E(k)/K(k) − 1 (Timoshenko & Gere, Theory of Elastic Stability, §2.7).
for alphaDeg = [5 20 45 90 120 150 170]
    alpha = deg2rad(alphaDeg);
    k = sin(alpha / 2);
    [K, E] = ellipke(k^2);
    ratio = (2 * K / pi)^2;
    sol = dlab.sims.column.elastica(Alpha=alpha);
    label = sprintf("α = %g°", alphaDeg);
    verifyEqual(testCase, sol.ratio, ratio, 'RelTol', 1e-4, label);
    shot = dlab.sims.column.elastica(Ratio=ratio);
    verifyEqual(testCase, shot.alpha, alpha, 'RelTol', 1e-4, label + ": shooting recovers α");
    verifyEqual(testCase, shot.deflection, 2 * k / (pi * sqrt(ratio)), 'RelTol', 1e-4, label);
    verifyEqual(testCase, 1 - shot.shortening, 2 * E / K - 1, 'AbsTol', 1e-6, label);
    verifyEqual(testCase, shot.theta(end), -alpha, 'AbsTol', 1e-6, label + ": symmetric");
    verifyEqual(testCase, shot.w(end), 0, 'AbsTol', 1e-8, label + ": back on the line of the load");
end
straight = dlab.sims.column.elastica(Ratio=0.9);
verifyEqual(testCase, straight.alpha, 0);
verifyEqual(testCase, max(abs(straight.w)), 0);
end

function testEngineElasticaForEachEndCondition(testCase)
% Fixed–free and fixed–fixed are pieces of the pinned elastica of length K L.
alpha = deg2rad(100);
[K, ~] = ellipke(sin(alpha / 2)^2);
m = steelTube('pinned');
m.analysis = 'elastica';
m.loadRatio = (2 * K / pi)^2;
pinned = dlab.sims.column.column_engine(m);
verifyEqual(testCase, pinned.elastica.alpha, alpha, 'RelTol', 1e-6);
crest = 2 * sin(alpha / 2) / (pi * sqrt(m.loadRatio));     % in units of K L
verifyEqual(testCase, pinned.deflection, crest * m.L, 'RelTol', 1e-6);
verifyEqual(testCase, pinned.maxStress, pinned.P / m.A + pinned.P * crest * m.L * m.c / m.I, 'RelTol', 1e-6);

m.endCondition = 'fixedfree';
free = dlab.sims.column.column_engine(m);
verifyEqual(testCase, free.elastica.alpha, alpha, 'RelTol', 1e-6);
verifyEqual(testCase, free.deflection, crest * 2 * m.L, 'RelTol', 1e-6, 'Tip: the pinned crest of length 2L.');
verifyEqual(testCase, free.elastica.lateral(end), free.deflection, 'RelTol', 1e-6);
verifyEqual(testCase, free.elastica.lateral(1), 0);

m.endCondition = 'fixedfixed';
fixed = dlab.sims.column.column_engine(m);
verifyEqual(testCase, fixed.deflection, 2 * crest * m.L / 2, 'RelTol', 1e-6, 'Two crests of length L/2.');
verifyEqual(testCase, fixed.elastica.lateral(end), 0, 'AbsTol', 1e-9, 'Both ends on the load line.');
verifyEqual(testCase, fixed.elastica.shortening, pinned.elastica.shortening, 'RelTol', 1e-6);

m.endCondition = 'fixedpinned';
verifyError(testCase, @() dlab.sims.column.column_engine(m), 'column:InvalidParameter');
end

function testElasticaCurveRisesPastBuckling(testCase)
m = steelTube('pinned');
r = dlab.sims.column.column_engine(m);
el = r.elastica;
verifyTrue(testCase, all(diff(el.curveRatio) > 0), 'The load rises with the end rotation.');
[K, ~] = ellipke(sin(el.curveAlpha / 2).^2);
verifyEqual(testCase, el.curveRatio, (2 * K / pi).^2, 'RelTol', 1e-4);
end

function testImperfectionAmplification(testCase)
for name = ["pinned" "fixedfree" "fixedpinned" "fixedfixed"]
    m = steelTube(name);
    m.loadRatio = 0.6;
    r = dlab.sims.column.column_engine(m);
    delta = m.e0 / (1 - 0.6);
    verifyEqual(testCase, r.linear.deflection, delta, 'RelTol', 1e-12, name);
    verifyEqual(testCase, r.deflection, delta, 'RelTol', 1e-12, name);
    verifyEqual(testCase, max(abs(r.linear.shape)), delta, 'RelTol', 1e-4, name);   % sampled shape
    verifyEqual(testCase, r.maxStress, r.P / m.A + r.momentFactor * r.P * delta * m.c / m.I, 'RelTol', 1e-12, name);
    % First yield: the largest stress equals the yield stress there.
    m.loadRatio = r.firstYieldLoad / r.Pcr;
    atYield = dlab.sims.column.column_engine(m);
    verifyEqual(testCase, atYield.maxStress, m.yieldStress, 'RelTol', 1e-9, name);
    verifyLessThan(testCase, r.firstYieldLoad, min(r.Pcr, r.squashLoad), name);
end
end

function testPinnedAmplificationAgainstABoundaryValueSolution(testCase)
% EI w'' + P w = EI w0'' with w0 = e0 sin(πx/L), solved by bvp4c.
m = steelTube('pinned');
m.loadRatio = 0.7;
r = dlab.sims.column.column_engine(m);
[L, EI, P, e0] = deal(m.L, m.E * m.I, r.P, m.e0);
ode = @(x, y) [y(2); -P / EI * y(1) - e0 * (pi / L)^2 * sin(pi * x / L)];
sol = bvp4c(ode, @(ya, yb) [ya(1); yb(1)], bvpinit(linspace(0, L, 50), [0 0]), ...
    bvpset('RelTol', 1e-8, 'AbsTol', 1e-12));
w = deval(sol, L / 2);
verifyEqual(testCase, w(1), r.linear.deflection, 'RelTol', 1e-5);
end

function testPerfectColumnFailsAtTheSmallerOfSquashAndEuler(testCase)
m = steelTube('pinned');
m.e0 = 0;
r = dlab.sims.column.column_engine(m);
verifyEqual(testCase, r.failureLoad, min(r.Pcr, r.squashLoad), 'RelTol', 1e-12);
verifyTrue(testCase, r.bucklingGoverns);
m.L = 0.5;                                       % stocky
r = dlab.sims.column.column_engine(m);
verifyEqual(testCase, r.failureLoad, r.squashLoad, 'RelTol', 1e-12);
verifyFalse(testCase, r.bucklingGoverns);
verifyEqual(testCase, r.limitingSlenderness, pi * sqrt(200e9 / 250e6), 'RelTol', 1e-12);
end

function testSouthwellRecoversTheCriticalLoad(testCase)
for name = ["pinned" "fixedfree" "fixedfixed"]
    m = steelTube(name);
    r = dlab.sims.column.column_engine(m);
    verifyEqual(testCase, r.southwell.Pcr, r.Pcr, 'RelTol', 0.01, name);
    verifyEqual(testCase, r.southwell.e0, m.e0, 'RelTol', 0.01, name);
end
m.scatter = 0.03;
r = dlab.sims.column.column_engine(m);
verifyEqual(testCase, r.southwell.Pcr, r.Pcr, 'RelTol', 0.1, 'With 3 % scatter, still close.');
verifyNotEqual(testCase, r.southwell.Pcr, r.Pcr);
m.e0 = 0;
r = dlab.sims.column.column_engine(m);
verifyFalse(testCase, r.southwell.available);
end

function testInvalidInputIsRejected(testCase)
cases = {
    struct('endCondition', 'hinged')
    struct('L', 0)
    struct('E', -1)
    struct('e0', 1)
    struct('P', NaN)
    struct('c', 1e-4)
    struct('analysis', 'elastica', 'loadRatio', 20)
};
for k = 1:numel(cases)
    m = steelTube('pinned');
    changes = cases{k};
    for name = string(fieldnames(changes))'
        m.(name) = changes.(name);
    end
    verifyError(testCase, @() dlab.sims.column.column_engine(m), 'column:InvalidParameter', ...
        sprintf('case %d', k));
end
end

function testProgressCanStopTheCurve(testCase)
m = steelTube('pinned');
calls = 0;
    function stop = monitor(~)
        calls = calls + 1;
        stop = true;
    end
m.progressFcn = @monitor;
r = dlab.sims.column.column_engine(m);
verifyEqual(testCase, calls, 1);
verifyFalse(testCase, isfield(r.params, 'progressFcn'));
end
