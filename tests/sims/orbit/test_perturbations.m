function tests = test_perturbations
%TEST_PERTURBATIONS J2 oblateness and atmospheric drag in simulateOrbit,
%   against first-order theory.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function [body, state] = earthOrbit(altitude, e, incDeg, argpDeg)
% Earth, and an orbit given by elements measured from its equator.
bodies = dlab.sims.orbit.BodyCatalog();
body = bodies.Earth;
toFrame = dlab.physics.roty(deg2rad(body.tilt));
[r, v] = dlab.physics.kep2cart(body.radius + altitude, e, deg2rad(incDeg), 0, deg2rad(argpDeg), 0, body.mu);
state = [toFrame * r(:); toFrame * v(:)];
end

function rate = driftRate(result, column)
% Secular rate (deg/day) of an equatorial element by a straight-line fit.
fit = polyfit(result.time / 86400, rad2deg(unwrap(result.equatorial(:, column))), 1);
rate = fit(1);
end

function testNoPerturbationKeepsTheTwoBodyModel(testCase)
[body, state] = earthOrbit(700, 0.01, 50, 30);
options = struct('durationOrbits', 3, 'sampleStep', 60);
plain = dlab.sims.orbit.simulateOrbit(state, body, options);
options.J2 = 0;
options.dragB = 0;
again = dlab.sims.orbit.simulateOrbit(state, body, options);
verifyEqual(testCase, again.state, plain.state);
verifyEqual(testCase, again.energy, plain.energy);
end

function testSunSynchronousNodeRate(testCase)
% Independent reference: the J2 nodal rate formula.
% J2 turns the node at Ω̇ = −1.5 n J2 (R/p)² cos i: at 700 km and i =
% 98.18° that is the Sun's apparent rate, 360° per year = 0.9856°/day.
J2 = 1.08263e-3;
[body, state] = earthOrbit(700, 0.001, 98.177, 0);
r = dlab.sims.orbit.simulateOrbit(state, body, struct('durationOrbits', 30, 'sampleStep', 60, 'J2', J2));
verifyEqual(testCase, driftRate(r, 4), 360 / 365.2422, 'RelTol', 0.01);
% Energy (with the J2 potential) and the angular momentum about the spin axis are conserved.
verifyLessThan(testCase, max(abs(r.energy - r.energy(1))) / abs(r.energy(1)), 1e-8);
verifyLessThan(testCase, max(abs(r.angularMomentum - r.angularMomentum(1))) / abs(r.angularMomentum(1)), 1e-8);
% The inclination to the equator stays put (no secular change).
verifyEqual(testCase, rad2deg(r.equatorial(end, 3)), 98.177, 'AbsTol', 0.02);
end

function testApsidalRateAndCriticalInclination(testCase)
% ω̇ = 0.75 n J2 (R/p)² (5 cos² i − 1): positive at 30°, zero at 63.43°.
J2 = 1.08263e-3;
[body, state] = earthOrbit(1000, 0.1, 30, 45);
r = dlab.sims.orbit.simulateOrbit(state, body, struct('durationOrbits', 40, 'sampleStep', 60, 'J2', J2));
E = r.equatorial(1, :);
n = sqrt(body.mu / E(1)^3);
factor = n * J2 * (body.radius / (E(1) * (1 - E(2)^2)))^2;
verifyEqual(testCase, driftRate(r, 5), rad2deg(0.75 * factor * (5 * cos(E(3))^2 - 1)) * 86400, 'RelTol', 0.02);
verifyEqual(testCase, driftRate(r, 4), rad2deg(-1.5 * factor * cos(E(3))) * 86400, 'RelTol', 0.02);
[body, state] = earthOrbit(20000, 0.74, 63.435, 270);
r = dlab.sims.orbit.simulateOrbit(state, body, struct('durationOrbits', 20, 'sampleStep', 300, 'J2', J2));
verifyLessThan(testCase, abs(driftRate(r, 5)), 1e-3, 'The critical inclination freezes the perigee.');
end

function testDragDecayMatchesKingHele(testCase)
% A circular polar orbit (where the air's rotation barely matters) decays at
% da/dt = −ρ (Cd A/m) √(μ a) (King-Hele, Theory of Satellite Orbits in an Atmosphere).
[body, state] = earthOrbit(400, 0, 90, 0);
B = 2.2 * 0.01;
r = dlab.sims.orbit.simulateOrbit(state, body, struct('durationOrbits', 16, 'sampleStep', 60, 'dragB', B));
fit = polyfit(r.time / 86400, r.equatorial(:, 1), 1);
a = body.radius + 400;
expected = -dlab.physics.thermosphereDensity(400) * B * sqrt(body.mu * 1e9 * a * 1e3) * 86400 / 1000;
verifyEqual(testCase, fit(1), expected, 'RelTol', 0.02);
verifyLessThan(testCase, r.energy(end), r.energy(1), 'Drag takes energy away.');
end

function testLowOrbitReenters(testCase)
[body, state] = earthOrbit(250, 0, 51.6, 0);
r = dlab.sims.orbit.simulateOrbit(state, body, struct('durationOrbits', 200, 'sampleStep', 60, 'dragB', 2.2 * 0.02));
verifyTrue(testCase, r.impacted);
verifyEqual(testCase, r.time(end) / 86400, 2.6, 'AbsTol', 0.5);
end

function testThermosphereTable(testCase)
% Vallado's table at its band edges, continuous enough between bands, and
% the ISA value near 86 km within the bands' accuracy.
rho = dlab.physics.thermosphereDensity([0 100 400 1000]);
verifyEqual(testCase, rho, [1.225 5.297e-7 3.725e-12 3.019e-15], 'RelTol', 1e-12);
h = 0:1:1200;
d = dlab.physics.thermosphereDensity(h);
verifyTrue(testCase, all(diff(d) < 0), 'Density falls with height.');
jumps = abs(diff(log(d)));
verifyLessThan(testCase, max(jumps), 0.25, 'No large steps between the bands.');
verifyEqual(testCase, dlab.physics.thermosphereDensity(86), dlab.physics.atmosphere(86000), 'RelTol', 0.25);
end
