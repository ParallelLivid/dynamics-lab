function tests = test_simulatePlate
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = base()
% A unit square with α = 1 (k = ρ = c = 1), all edges fixed at 0, starting
% in the (1, 1) mode: T = sin(πx) sin(πy) exp(−2π² t). r = 0.08 (explicit).
p = struct('a', 1, 'b', 1, 'nx', 21, 'ny', 21, 'k', 1, 'rho', 1, 'c', 1, 'd', 1, 'scheme', 'explicit', ...
    'dt', 2e-4, 'tspan', 0.05, 'dtOut', 0.01, 'left', edge('fixed'), 'right', edge('fixed'), ...
    'bottom', edge('fixed'), 'top', edge('fixed'), ...
    'initial', struct('type', 'mode', 'T0', 0, 'amplitude', 1, 'position', [0.4 0.55], 'width', 0.08, ...
        'mode', [1 1], 'edge', 'left'), ...
    'source', struct('type', 'none', 'q', 0, 'position', [0.5 0.5], 'width', 0.1), 'probe', [0.7 0.5]);
end

function e = edge(type, varargin)
e = struct('type', type, 'T', 0, 'flux', 0, 'h', 0, 'Tinf', 0);
for k = 1:2:numel(varargin)
    e.(varargin{k}) = varargin{k + 1};
end
end

function p = highestMode(r, n)
% The checkerboard (n − 2, n − 2) mode on an n × n grid, at r = α Δt / h².
p = base();
[p.nx, p.ny] = deal(n);
h = 1 / (n - 1);
p.dt = r * h^2;
p.tspan = 100 * p.dt;
p.dtOut = p.tspan;
p.initial.mode = [n - 2, n - 2];
p.initial.amplitude = 1e-3;
end

% ------------------------------------------------------------- accuracy
function testSeparableModeConvergesAtSecondOrder(testCase)
% At a fixed r = 0.2, halving h cuts the error about 4× for both schemes.
for scheme = {'explicit', 'adi'}
    errors = zeros(1, 3);
    nodes = [11 21 41];
    for k = 1:3
        p = base();
        p.scheme = scheme{1};
        [p.nx, p.ny] = deal(nodes(k));
        p.dt = 0.2 / (nodes(k) - 1)^2;
        r = dlab.sims.plate.simulatePlate(p);
        exact = sin(pi * r.y) * sin(pi * r.x) * exp(-2 * pi^2 * r.t(end));
        errors(k) = max(abs(r.T(:, :, end) - exact), [], 'all');
        verifyEqual(testCase, r.maxError, errors(k), 'RelTol', 1e-12, 'maxError is the largest over the run.');
    end
    ratios = errors(1:2) ./ errors(2:3);
    verifyGreaterThan(testCase, ratios, 3.8, scheme{1});
    verifyLessThan(testCase, ratios, 4.2, scheme{1});
    verifyLessThan(testCase, errors(3), 3e-4, scheme{1});
end
end

function testExactDecayRate(testCase)
% Independent reference: the exact decay rate of a separable mode.
% λ = α π² (m²/a² + n²/b²), and the mode keeps its shape.
p = base();
[p.a, p.b, p.nx, p.ny] = deal(2, 1, 41, 21);
p.initial.mode = [2 1];
r = dlab.sims.plate.simulatePlate(p);
verifyTrue(testCase, r.hasExact);
verifyEqual(testCase, r.decayRate, pi^2 * (1 + 1), 'RelTol', 1e-12);
numeric = -log(r.modeAmplitude(end) / r.modeAmplitude(1)) / r.t(end);
verifyEqual(testCase, numeric, r.decayRate, 'RelTol', 2e-3);
p.left = edge('fixed', 'T', 5);
verifyFalse(testCase, dlab.sims.plate.simulatePlate(p).hasExact, 'Not with an edge away from T0.');
end

% ------------------------------------------------------------ stability
function testExplicitLimitIsAQuarterOnASquareGrid(testCase)
% FTCS multiplies the checkerboard mode by g = 1 − 8 r sin²((n−2)π/2(n−1))
% per step: |g| < 1 at r = ¼, |g| > 1 at r = 0.26.
n = 41;
s = sin((n - 2) * pi / (2 * (n - 1)))^2;
r = dlab.sims.plate.simulatePlate(highestMode(0.25, n));
g = 1 - 8 * 0.25 * s;
verifyEqual(testCase, r.modeAmplitude(end) / r.modeAmplitude(1), g^100, 'RelTol', 1e-9);
verifyLessThan(testCase, abs(g), 1);
verifyTrue(testCase, r.stable);
verifyLessThan(testCase, r.dt, r.dtMax);
verifyEqual(testCase, r.dtMax * (n - 1)^2, 1 / (4 * s), 'RelTol', 1e-10, 'The exact limit for fixed edges.');

r = dlab.sims.plate.simulatePlate(highestMode(0.26, n));
g = 1 - 8 * 0.26 * s;
verifyEqual(testCase, r.modeAmplitude(end) / r.modeAmplitude(1), g^100, 'RelTol', 1e-9);
verifyGreaterThan(testCase, abs(g)^100, 1000, 'The checkerboard grows.');
verifyGreaterThan(testCase, r.dt, r.dtMax);

p = highestMode(0.26, n);
p.tspan = 1000 * p.dt;
r = dlab.sims.plate.simulatePlate(p);
verifyFalse(testCase, r.stable);
verifyEqual(testCase, r.termination, 'unstable');
verifyLessThan(testCase, r.blowupTime, p.tspan);

p = base();
[p.left, p.right, p.bottom, p.top] = deal(edge('flux'));
verifyEqual(testCase, dlab.sims.plate.simulatePlate(p).dtMax * 20^2, 0.25, 'RelTol', 1e-10, ...
    'Insulated edges: exactly r = ¼.');
end

function testAdiIsStableAtLargeSteps(testCase)
% Peaceman–Rachford: g = ((1 − 2r s)/(1 + 2r s))² for the (m, m) mode.
n = 41;
s = sin((n - 2) * pi / (2 * (n - 1)))^2;
p = highestMode(5, n);
p.scheme = 'adi';
r = dlab.sims.plate.simulatePlate(p);
g = ((1 - 2 * 5 * s) / (1 + 2 * 5 * s))^2;
verifyEqual(testCase, r.modeAmplitude(end) / r.modeAmplitude(1), g^100, 'RelTol', 1e-9);
verifyTrue(testCase, r.stable);
p = base();
p.scheme = 'adi';
p.initial.type = 'hotspot';
p.dt = 5 / 20^2;
p.tspan = 200 * p.dt;
r = dlab.sims.plate.simulatePlate(p);
verifyTrue(testCase, r.stable);
verifyLessThan(testCase, max(abs(r.T(:, :, end)), [], 'all'), 1e-3, 'Decayed, not blown up.');
end

% --------------------------------------------------------------- energy
function testInsulatedPlateConservesEnergy(testCase)
p = base();
[p.left, p.right, p.bottom, p.top] = deal(edge('flux'));
p.initial = struct('type', 'hotspot', 'T0', 20, 'amplitude', 80, 'position', [0.4 0.55], 'width', 0.08, ...
    'mode', [1 1], 'edge', 'left');
for scheme = {'explicit', 'adi'}
    p.scheme = scheme{1};
    r = dlab.sims.plate.simulatePlate(p);
    verifyLessThan(testCase, max(abs(r.energy - r.energy(1))) / r.energy(1), 1e-12, scheme{1});
    verifyEqual(testCase, r.heatIn, zeros(size(r.t)), scheme{1});
    verifyLessThan(testCase, max(r.T(:, :, end), [], 'all') - min(r.T(:, :, end), [], 'all'), 20, 'It spreads.');
end
end

function testEnergyBalanceWithConvectionAndSources(testCase)
% Stored heat = heat in through the edges + generated, to rounding.
p = base();
[p.a, p.b, p.nx, p.ny, p.k, p.rho, p.c, p.d] = deal(0.2, 0.1, 41, 21, 237, 2700, 897, 0.01);
p.initial = struct('type', 'hotspot', 'T0', 20, 'amplitude', 80, 'position', [0.4 0.55], 'width', 0.08, ...
    'mode', [1 1], 'edge', 'left');
[p.dt, p.tspan, p.dtOut] = deal(0.05, 60, 1);
for scheme = {'explicit', 'adi'}
    p.scheme = scheme{1};
    [p.left, p.right, p.bottom, p.top] = deal(edge('convection', 'h', 50, 'Tinf', 20));
    r = dlab.sims.plate.simulatePlate(p);
    change = r.energy - r.energy(1);
    verifyLessThan(testCase, r.heatIn(end), 0, 'The hot plate loses heat.');
    verifyLessThan(testCase, max(abs(change - r.heatIn)) / max(abs(change)), 1e-9, scheme{1});
    p.left = edge('fixed', 'T', 100);
    p.bottom = edge('fixed', 'T', 0);
    p.top = edge('flux', 'flux', 2000);
    p.source = struct('type', 'spot', 'q', 1e7, 'position', [0.5 0.5], 'width', 0.1);
    r = dlab.sims.plate.simulatePlate(p);
    change = r.energy - r.energy(1);
    verifyLessThan(testCase, max(abs(change - r.heatIn - r.generated)) / max(abs(change)), 1e-9, scheme{1});
    p.source.type = 'none';
end
end

function testUniformSourceHeatsAnInsulatedPlate(testCase)
% With insulated edges every node warms at q / ρc.
p = base();
[p.left, p.right, p.bottom, p.top] = deal(edge('flux'));
p.initial.type = 'uniform';
p.source = struct('type', 'uniform', 'q', 3, 'position', [0.5 0.5], 'width', 0.1);
p.scheme = 'adi';
r = dlab.sims.plate.simulatePlate(p);
verifyEqual(testCase, r.meanT(end), 3 * p.tspan, 'RelTol', 1e-10);
verifyEqual(testCase, r.generated(end), 3 * p.tspan, 'RelTol', 1e-10, 'q · area · thickness · t');
end

% --------------------------------------------------------- steady states
function testSteadyStateBetweenTwoFixedEdgesIsLinear(testCase)
p = base();
[p.a, p.b, p.nx, p.ny] = deal(1, 0.5, 21, 11);
p.scheme = 'adi';
p.left = edge('fixed', 'T', 100);
p.right = edge('fixed', 'T', 0);
[p.bottom, p.top] = deal(edge('flux'));
p.initial.type = 'hotspot';
[p.dt, p.tspan, p.dtOut] = deal(0.01, 5, 0.05);
r = dlab.sims.plate.simulatePlate(p);
verifyEqual(testCase, r.T(:, :, end), repmat(100 * (1 - r.x), 11, 1), 'AbsTol', 1e-9);
verifyTrue(testCase, isfinite(r.steadyTime) && r.steadyTime < p.tspan);
end

function testSteadyStateWithAConvectionEdge(testCase)
% Conduction and convection resistances in series: T(a) = T∞ + (T₀ − T∞)(1/h)/(a/k + 1/h).
p = base();
[p.a, p.b, p.nx, p.ny, p.k] = deal(1, 0.5, 21, 11, 5);
p.scheme = 'adi';
p.left = edge('fixed', 'T', 100);
p.right = edge('convection', 'h', 20, 'Tinf', 10);
[p.bottom, p.top] = deal(edge('flux'));
p.initial.type = 'uniform';
[p.dt, p.tspan, p.dtOut] = deal(0.002, 2, 0.1);
r = dlab.sims.plate.simulatePlate(p);
expected = 10 + 90 * (1 / 20) / (1 / 5 + 1 / 20);
verifyEqual(testCase, r.T(:, end, end), expected * ones(11, 1), 'RelTol', 1e-9);
end

% ----------------------------------------------------------- the rest
function testDeterministic(testCase)
p = base();
p.initial.type = 'hotspot';
p.source = struct('type', 'spot', 'q', 5, 'position', [0.3 0.6], 'width', 0.1);
verifyTrue(testCase, isequaln(dlab.sims.plate.simulatePlate(p), dlab.sims.plate.simulatePlate(p)));
end

function testProgressCanCancel(testCase)
p = base();
p.progressFcn = @(fraction) fraction > 0.3;
r = dlab.sims.plate.simulatePlate(p);
verifyEqual(testCase, r.termination, 'cancelled');
verifyLessThan(testCase, r.t(end), p.tspan);
end

function testBadInputIsRejected(testCase)
p = base();
p.nx = 2;
verifyError(testCase, @() dlab.sims.plate.simulatePlate(p), 'plate:InvalidParameter');
p = base();
p.top = edge('convection');
verifyError(testCase, @() dlab.sims.plate.simulatePlate(p), 'plate:InvalidParameter');
p = base();
p.scheme = 'cranknicolson';
verifyError(testCase, @() dlab.sims.plate.simulatePlate(p), 'plate:InvalidParameter');
p = base();
p.dt = 1e-7;
p.tspan = 10;
verifyError(testCase, @() dlab.sims.plate.simulatePlate(p), 'plate:TooManySteps');
end
