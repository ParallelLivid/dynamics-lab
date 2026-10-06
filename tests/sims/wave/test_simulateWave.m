function tests = test_simulateWave
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = guitar()
p = struct('medium', 'string', 'L', 0.65, 'elements', 200, 'tension', 70, 'rho', 0.0006, ...
    'EI', 1, 'rhoA', 1, 'bc', 'fixedfixed', 'initial', 'pluck', 'height', 0.003, 'position', 0.5, ...
    'width', 0.05, 'mode', 1, 'zeta', 0, 'tspan', 0.02, 'dtOut', 1e-5, 'probe', 0.2);
end

function p = beam(bc)
p = guitar();
[p.medium, p.EI, p.rhoA, p.L, p.elements, p.bc, p.tspan, p.dtOut] = deal('beam', 2, 0.5, 1, 100, bc, 0.1, 1e-3);
end

function testStringHarmonics(testCase)
r = dlab.sims.wave.simulateWave(guitar());
f1 = sqrt(70 / 0.0006) / (2 * 0.65);
verifyEqual(testCase, r.frequencies(1), f1, 'RelTol', 5e-4);
verifyEqual(testCase, r.frequencies(1:5) / r.frequencies(1), (1:5)', 'RelTol', 1e-3);
p = guitar();
p.bc = 'fixedfree';
verifyEqual(testCase, dlab.sims.wave.simulateWave(p).frequencies(1), f1 / 2, 'RelTol', 5e-4);
end

function testPluckPointSelectsHarmonics(testCase)
r = dlab.sims.wave.simulateWave(guitar());               % plucked at the middle
even = r.modalEnergy(2:2:10) / sum(r.modalEnergy);
verifyLessThan(testCase, max(even), 1e-12, 'A middle pluck has no even harmonics.');
p = guitar();
p.position = 0.2;
r = dlab.sims.wave.simulateWave(p);
verifyLessThan(testCase, r.modalEnergy(5) / sum(r.modalEnergy), 1e-12, 'A pluck at L/5 misses mode 5.');
end

function testStringReturnsAfterOnePeriod(testCase)
% d'Alembert: after 2L/c an undamped string is back where it started.
p = guitar();
period = 2 * p.L / sqrt(p.tension / p.rho);
[p.tspan, p.dtOut] = deal(period, period);
r = dlab.sims.wave.simulateWave(p);
verifyLessThan(testCase, max(abs(r.U(end, :) - r.U(1, :))), 0.01 * p.height);
end

function testUndampedEnergyIsConstant(testCase)
r = dlab.sims.wave.simulateWave(guitar());
verifyLessThan(testCase, max(abs(r.E - r.E(1))) / r.E(1), 1e-10);
p = guitar();
p.zeta = 0.01;
r = dlab.sims.wave.simulateWave(p);
verifyTrue(testCase, all(diff(r.E) <= 1e-15 * r.E(1)), 'Damping only removes energy.');
end

function testBeamFrequencies(testCase)
% Independent reference: the published β_n L of a beam's modes.
% ω_n = (β_n L)² √(EI / ρA) / L², with β_n L = nπ (pinned), 1.87510 (cantilever),
% and 4.73004 (clamped–clamped and free–free).
scale = sqrt(2 / 0.5) / (2 * pi);
r = dlab.sims.wave.simulateWave(beam('pinned'));
verifyEqual(testCase, r.frequencies(1), pi^2 * scale, 'RelTol', 1e-4);
verifyEqual(testCase, r.frequencies(1:3) / r.frequencies(1), [1; 4; 9], 'RelTol', 1e-3);
r = dlab.sims.wave.simulateWave(beam('cantilever'));
verifyEqual(testCase, r.frequencies(1), 1.87510407^2 * scale, 'RelTol', 1e-4);
verifyEqual(testCase, r.frequencies(2) / r.frequencies(1), 6.2669, 'RelTol', 1e-3);
r = dlab.sims.wave.simulateWave(beam('clamped'));
verifyEqual(testCase, r.frequencies(1), 4.73004074^2 * scale, 'RelTol', 1e-4);
r = dlab.sims.wave.simulateWave(beam('free'));
verifyEqual(testCase, r.rigid, 2, 'Free–free: two rigid-body modes.');
verifyEqual(testCase, r.frequencies(1), 4.73004074^2 * scale, 'RelTol', 1e-4);
end

function testSingleModeStaysSingle(testCase)
p = guitar();
p.initial = 'mode';
p.mode = 3;
r = dlab.sims.wave.simulateWave(p);
[~, dominant] = max(r.modalEnergy);
verifyEqual(testCase, dominant, 3);
verifyGreaterThan(testCase, r.modalEnergy(3) / sum(r.modalEnergy), 1 - 1e-9);
end

function testBadInputIsRejected(testCase)
p = guitar();
p.bc = 'cantilever';
verifyError(testCase, @() dlab.sims.wave.simulateWave(p), 'wave:InvalidParameter');
p = guitar();
p.dtOut = 1e-9;
verifyError(testCase, @() dlab.sims.wave.simulateWave(p), 'wave:TooMuchOutput');
end

function testFineFreeBeamKeepsItsLowestModes(testCase)
% Only the two rigid-body modes are dropped, however fine the mesh: on 800
% elements the highest mode is ~10⁶ times the lowest flexible one.
p = beam('free');
p.elements = 800;
r = dlab.sims.wave.simulateWave(p);
verifyEqual(testCase, r.rigid, 2);
verifyEqual(testCase, r.frequencies(1), 4.73004074^2 * sqrt(2 / 0.5) / (2 * pi), 'RelTol', 1e-4);
end

function testBeamModeStartIsAPureMode(testCase)
% The mode's own slopes, not finite differences of its deflection.
for bc = {'pinned', 'cantilever', 'free'}
    p = beam(bc{1});
    [p.initial, p.mode, p.elements, p.height] = deal('mode', 2, 20, 0.01);
    r = dlab.sims.wave.simulateWave(p);
    verifyGreaterThan(testCase, r.modalEnergy(2) / sum(r.modalEnergy), 1 - 1e-9, bc{1});
    verifyEqual(testCase, max(abs(r.U(1, :))), 0.01, 'RelTol', 1e-12, bc{1});
end
end

function testBeamPluckIsItsStaticDeflection(testCase)
% A plucked beam starts from its deflection under a point load: the energy
% is P δ / 2 = 3 EI δ² / (2 a³) for a cantilever loaded at a, whatever the
% mesh, and almost all of it is in mode 1 (97.3 %, from the exact modes).
% The string's triangle (a ramp for a cantilever) put energy in every mode
% and grew with the number of elements.
p = beam('cantilever');
[p.L, p.EI, p.rhoA, p.position, p.height] = deal(0.3, 0.5, 0.2355, 0.99, 0.02);
a = 0.99 * 0.3;
for n = [30 120]
    p.elements = n;
    r = dlab.sims.wave.simulateWave(p);
    verifyEqual(testCase, r.E(1), 3 * 0.5 * 0.02^2 / (2 * a^3), 'RelTol', 1e-5, sprintf('%d elements', n));
    verifyEqual(testCase, r.modalEnergy(1) / sum(r.modalEnergy), 0.9730, 'AbsTol', 5e-4);
    verifyEqual(testCase, interp1(r.x, r.U(1, :), a), 0.02, 'RelTol', 1e-3);
end
% Pinned, loaded at a = 0.3 L: δ = P a² b² / (3 EI L), so P δ / 2 = 3 EI L δ² / (2 a² b²).
p = beam('pinned');
[p.position, p.height] = deal(0.3, 0.01);
r = dlab.sims.wave.simulateWave(p);
verifyEqual(testCase, r.E(1), 3 * 2 * 1 * 0.01^2 / (2 * 0.3^2 * 0.7^2), 'RelTol', 1e-5);
for bc = {'clamped', 'free'}            % the same energy on a coarse and a fine mesh
    p = beam(bc{1});
    p.position = 0.3;
    [p.elements, coarse] = deal(200, dlab.sims.wave.simulateWave(setfield(p, 'elements', 50))); %#ok<SFLD>
    fine = dlab.sims.wave.simulateWave(p);
    verifyEqual(testCase, coarse.E(1), fine.E(1), 'RelTol', 1e-4, bc{1});
    verifyEqual(testCase, coarse.modalEnergy(1:3), fine.modalEnergy(1:3), 'RelTol', 1e-3, bc{1});
end
end

function testSmoothBeamStartHasItsBendingEnergy(testCase)
% A bump's energy is EI/2 ∫ u''² dx (0.0338395 J here, by quadrature); its
% slopes are exact, not finite differences (1.6 % too much before).
p = beam('clamped');
[p.initial, p.position, p.width, p.height] = deal('gaussian', 0.5, 0.1, 0.003);
r = dlab.sims.wave.simulateWave(p);
verifyEqual(testCase, r.E(1), 0.0338395, 'RelTol', 1e-4);
end
