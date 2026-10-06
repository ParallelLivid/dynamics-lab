function tests = test_simulateMembrane
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = drum(shape)
% Unit wave speed (T = ρ = 1), so f = c j / 2πR and f_mn = ½ √((m/a)² + (n/b)²).
p = struct('shape', shape, 'a', 1, 'b', 1, 'R', 1, 'tension', 1, 'rho', 1, 'grid', 40, 'modes', 30, ...
    'initial', 'strike', 'height', 1, 'position', [0.3 0.37], 'width', 0.06, 'mode', [2 1], 'zeta', 0, ...
    'tspan', 2, 'dtOut', 0.01, 'probe', [0.72 0.22]);
end

function f = exactRectangle(labels, a, b)
f = 0.5 * sqrt((labels(:, 1) / a).^2 + (labels(:, 2) / b).^2);
end

function errors = firstErrors(r, count)
d = find(r.distinct, count);
errors = abs(r.frequencies(d) - r.analytic(d)) ./ r.analytic(d);
end

% ------------------------------------------------------------- rectangle
function testRectangleFrequencies(testCase)
% f_mn = (c/2) √((m/a)² + (n/b)²): the order and the values of the lowest eight.
p = drum('rectangle');
[p.a, p.b, p.tension, p.rho, p.grid] = deal(0.6, 0.4, 100, 0.1, 60);
r = dlab.sims.membrane.simulateMembrane(p);
c = sqrt(100 / 0.1);
expected = [1 1; 2 1; 1 2; 3 1; 2 2; 3 2; 4 1; 1 3];
verifyEqual(testCase, r.labels(1:8, :), expected);
verifyEqual(testCase, r.frequencies(1:8), c * exactRectangle(expected, 0.6, 0.4), 'RelTol', 4e-3);
verifyEqual(testCase, r.analytic(1:8), c * exactRectangle(expected, 0.6, 0.4), 'RelTol', 1e-12);
verifyEqual(testCase, r.c, c, 'RelTol', 1e-12);
end

function testRectangleConvergesAtSecondOrder(testCase)
% Halving h cuts the error of the 5-point Laplacian about 4×.
errors = zeros(6, 3);
grids = [20 40 80];
for k = 1:3
    p = drum('rectangle');
    p.grid = grids(k);
    errors(:, k) = firstErrors(dlab.sims.membrane.simulateMembrane(p), 6);
end
verifyLessThan(testCase, errors(:, 2), 0.003, 'h = 1/40: the lowest six within 0.3 %.');
ratios = errors(:, 1:2) ./ errors(:, 2:3);
verifyGreaterThan(testCase, ratios, 3.8);
verifyLessThan(testCase, ratios, 4.2);
end

function testSquarePairsArePureSines(testCase)
% A square's (1,2) and (2,1) share a frequency; each is still a pure product of sines.
r = dlab.sims.membrane.simulateMembrane(drum('rectangle'));
one = find(ismember(r.labels, [1 2], 'rows'));
two = find(ismember(r.labels, [2 1], 'rows'));
verifyNumElements(testCase, [one two], 2);
verifyEqual(testCase, r.frequencies(one), r.frequencies(two), 'RelTol', 1e-9);
verifyEqual(testCase, r.frequencies(one) / r.frequencies(1), sqrt(5 / 2), 'RelTol', 2e-3);
exact = sin(pi * r.x) .* sin(2 * pi * r.y);
shape = r.shapes(:, one);
verifyEqual(testCase, abs(shape' * exact) / (norm(shape) * norm(exact)), 1, 'AbsTol', 1e-10);
end

function testStrikeOnANodalLine(testCase)
% A strike on x = a/2 (the nodal line of every even m) cannot excite those modes.
p = drum('rectangle');
p.position = [0.5 0.37];
r = dlab.sims.membrane.simulateMembrane(p);
even = mod(r.labels(:, 1), 2) == 0;
verifyLessThan(testCase, sum(r.modalEnergy(even)) / sum(r.modalEnergy), 1e-20);
verifyGreaterThan(testCase, sum(r.modalEnergy(~even)), 0);
end

% ---------------------------------------------------------------- circle
function testCircleBesselZeros(testCase)
% Independent reference: the zeros of the Bessel functions.
% f = c j_mn / 2πR with j01 = 2.404826, j11 = 3.831706, j21 = 5.135622, j02 = 5.520078.
p = drum('circle');
p.grid = 80;
r = dlab.sims.membrane.simulateMembrane(p);
labels = [0 1; 1 1; 2 1; 0 2];
besselZeros = [2.404826; 3.831706; 5.135622; 5.520078];
for k = 1:4
    j = find(ismember(r.labels, labels(k, :), 'rows'), 1);
    verifyEqual(testCase, r.analytic(j) * 2 * pi, besselZeros(k), 'AbsTol', 1e-6, 'Bessel zero by fzero.');
    verifyEqual(testCase, r.frequencies(j), besselZeros(k) / (2 * pi), 'RelTol', 2e-3, ...
        sprintf('Mode (%d,%d)', labels(k, :)));
end
d = find(r.distinct);
verifyEqual(testCase, r.labels(d(1:4), :), [0 1; 1 1; 2 1; 0 2], 'The lowest four, in order.');
verifyEqual(testCase, r.frequencies(d(2)) / r.frequencies(d(1)), 3.831706 / 2.404826, 'RelTol', 1e-3);
end

function testCircleConvergesWithRefinement(testCase)
% The polar finite volumes are second order: errors fall about 4× per halving.
grids = [20 40 80];
errors = zeros(5, 3);
for k = 1:3
    p = drum('circle');
    p.grid = grids(k);
    errors(:, k) = firstErrors(dlab.sims.membrane.simulateMembrane(p), 5);
end
verifyLessThan(testCase, errors(:, 1), 0.02, 'Within 2 % even on a coarse grid.');
ratios = errors(:, 1:2) ./ errors(:, 2:3);
verifyGreaterThan(testCase, ratios, 3.5);
verifyLessThan(testCase, ratios, 4.5);
end

function testCentreStrikeRingsOnlyAxisymmetricModes(testCase)
p = drum('circle');
p.position = [0.5 0.5];
r = dlab.sims.membrane.simulateMembrane(p);
verifyLessThan(testCase, sum(r.modalEnergy(r.labels(:, 1) > 0)) / sum(r.modalEnergy), 1e-20);
verifyEqual(testCase, r.axisymmetric, 100, 'AbsTol', 1e-9);
p.position = [0.8 0.55];
r = dlab.sims.membrane.simulateMembrane(p);
verifyLessThan(testCase, r.axisymmetric, 50, 'Off-centre, the other modes take most of the energy.');
end

function testCircleCosSinPairs(testCase)
% Each (m, n) with m ≥ 1 appears twice (cos mθ and sin mθ) at one frequency.
r = dlab.sims.membrane.simulateMembrane(drum('circle'));
pair = find(ismember(r.labels, [1 1], 'rows'));
verifyNumElements(testCase, pair, 2);
verifyEqual(testCase, r.frequencies(pair(1)), r.frequencies(pair(2)), 'RelTol', 1e-9);
verifyEqual(testCase, nnz(r.distinct(pair)), 1);
theta = atan2(r.y, r.x);
cosPart = abs(sum(r.shapes(:, pair(1)) .* sin(theta))) / sum(abs(r.shapes(:, pair(1))));
verifyLessThan(testCase, cosPart, 1e-10, 'The first of a pair is pure cos(mθ).');
end

% ------------------------------------------------------------ in time
function testUndampedEnergyIsConserved(testCase)
for shape = {'rectangle', 'circle'}
    p = drum(shape{1});
    r = dlab.sims.membrane.simulateMembrane(p);
    verifyLessThan(testCase, max(abs(r.E - r.E(1))) / r.E(1), 1e-10, shape{1});
    verifyEqual(testCase, r.E(1), sum(r.modalEnergy), 'RelTol', 1e-10);
end
p = drum('circle');
p.zeta = 0.02;
r = dlab.sims.membrane.simulateMembrane(p);
verifyTrue(testCase, all(diff(r.E) <= 1e-15 * r.E(1)), 'Damping only removes energy.');
end

function testSingleModeStaysSingle(testCase)
% Mode (2,1) of a circle: one frequency, back to the start after one period.
p = drum('circle');
p.initial = 'mode';
f = 5.135622 / (2 * pi);
[p.tspan, p.dtOut, p.height] = deal(1 / f, 1 / (40 * f), 0.01);
r = dlab.sims.membrane.simulateMembrane(p);
[~, dominant] = max(r.modalEnergy);
verifyEqual(testCase, r.labels(dominant, :), [2 1]);
others = r.modalEnergy;
others(dominant) = [];
verifyLessThan(testCase, max(others) / r.modalEnergy(dominant), 1e-20);
first = r.plotShapes * r.Q(:, 1);
last = r.plotShapes * r.Q(:, end);
verifyLessThan(testCase, max(abs(last - first)), 0.01 * p.height, 'A period later it is back (2 % error in f).');
verifyEqual(testCase, max(abs(first)), p.height, 'RelTol', 1e-9);
end

function testDampedModeDecaysAtItsRate(testCase)
% One mode with damping ratio ζ: E ∝ exp(−2ζωt) on average over a period.
p = drum('rectangle');
p.initial = 'mode';
p.mode = [1 1];
p.zeta = 0.01;
p.tspan = 10;
r = dlab.sims.membrane.simulateMembrane(p);
omega = 2 * pi * r.frequencies(1);
period = 1 / r.frequencies(1);
late = r.t > r.t(end) - period;
early = r.t < period;
verifyEqual(testCase, mean(r.E(late)) / mean(r.E(early)), exp(-2 * p.zeta * omega * (r.t(end) - period / 2) ...
    + 2 * p.zeta * omega * period / 2), 'RelTol', 0.02);
end

function testMoreModesCaptureMoreOfAStrike(testCase)
p = drum('rectangle');
p.modes = 10;
few = dlab.sims.membrane.simulateMembrane(p).captured;
p.modes = 120;
many = dlab.sims.membrane.simulateMembrane(p).captured;
verifyGreaterThan(testCase, many, few);
verifyLessThanOrEqual(testCase, many, 100 + 1e-9);
end

% ---------------------------------------------------------------- errors
function testInvalidInputs(testCase)
p = drum('circle');
p.position = [0.95 0.95];
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:InvalidParameter');
p = drum('rectangle');
p.initial = 'mode';
p.mode = [0 1];
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:InvalidParameter');
p.mode = [9 9];
p.modes = 5;
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:InvalidParameter');
p = drum('hexagon');
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:InvalidParameter');
p = drum('rectangle');
p.tension = -1;
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:InvalidParameter');
end

function testCancel(testCase)
p = drum('rectangle');
p.progressFcn = @(~) true;
verifyError(testCase, @() dlab.sims.membrane.simulateMembrane(p), 'membrane:Cancelled');
end
