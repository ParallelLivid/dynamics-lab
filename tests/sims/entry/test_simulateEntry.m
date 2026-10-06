function tests = test_simulateEntry
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = ballistic(V0, gamma0, beta)
% Allen–Eggers conditions: exponential atmosphere, no lift, no gravity, flat Earth.
p = struct('V0', V0, 'gamma0', gamma0, 'h0', 120e3, 'beta', beta, 'LD', 0, 'bank', 0, ...
    'noseRadius', 1, 'atmosphere', 'exponential', 'scaleHeight', 7200, 'chuteMach', 0, ...
    'maxTime', 3000, 'dt', 0.05, 'gravity', false, 'curvature', false);
end

function p = lunarReturn()
p = struct('V0', 11000, 'gamma0', -6.5, 'h0', 120e3, 'beta', 350, 'LD', 0.3, ...
    'bank', @(t) 90 * (t > 80), 'noseRadius', 4.7, 'atmosphere', 'standard', 'scaleHeight', 7200, ...
    'chuteMach', 0.8, 'maxTime', 3000, 'dt', 0.5);
end

function testAllenEggersVelocityProfile(testCase)
% Independent reference: Allen and Eggers, NACA TR-1381 (1958).
% V(h) = V_E exp(−ρ(h) H / (2 β sin|γ_E|))  (Allen & Eggers, NACA TR-1381, 1958).
for c = [7500 -20 300; 11000 -45 100; 6000 -8 1000]'
    p = ballistic(c(1), c(2), c(3));
    r = dlab.sims.entry.simulateEntry(p);
    expected = p.V0 * exp(-r.rho * p.scaleHeight / (2 * p.beta * sind(-p.gamma0)));
    verifyEqual(testCase, r.V, expected, 'RelTol', 1e-4, sprintf('V(h) at γ = %g°', c(2)));
    verifyEqual(testCase, r.gamma, p.gamma0 * ones(size(r.gamma)), 'AbsTol', 1e-9, 'γ stays constant.');
end
end

function testAllenEggersPeakDeceleration(testCase)
% a_max = V_E² sin|γ_E| / (2 e H), where ρ = β sin|γ_E| / H.
for c = [7500 -20 300; 11000 -45 100; 6000 -8 1000]'
    p = ballistic(c(1), c(2), c(3));
    r = dlab.sims.entry.simulateEntry(p);
    s = sind(-p.gamma0);
    aMax = p.V0^2 * s / (2 * exp(1) * p.scaleHeight) / 9.80665;
    verifyEqual(testCase, r.peaks.decel, aMax, 'RelTol', 1e-3, sprintf('peak g at γ = %g°', c(2)));
    hStar = p.scaleHeight * log(1.225 / (p.beta * s / p.scaleHeight));
    verifyEqual(testCase, r.peaks.decelAltitude, hStar, 'AbsTol', 0.01 * p.scaleHeight, ...
        sprintf('altitude of the peak at γ = %g°', c(2)));
end
% The golden case of the docs: 7.5 km/s, −20°, β = 300 kg/m², H = 7.2 km.
r = dlab.sims.entry.simulateEntry(ballistic(7500, -20, 300));
verifyEqual(testCase, r.peaks.decel, 50.118, 'RelTol', 1e-4);
verifyEqual(testCase, r.peaks.decelAltitude, 32068, 'AbsTol', 10);
end

function testEnergyIsAccountedFor(testCase)
% V²/2 − μ/r falls by exactly the drag work ∫ (D/m) V dt: lift does no work.
r = dlab.sims.entry.simulateEntry(lunarReturn());
budget = r.energy - r.energy(1) + r.dragWork;
verifyLessThan(testCase, max(abs(budget)) / (0.5 * 11000^2), 1e-7);
verifyEqual(testCase, r.dragWork(end), r.energy(1) - r.energy(end), 'RelTol', 1e-7);
p = ballistic(7500, -20, 300);
p.gravity = true;
p.curvature = true;
r = dlab.sims.entry.simulateEntry(p);
verifyLessThan(testCase, max(abs(r.energy - r.energy(1) + r.dragWork)) / (0.5 * 7500^2), 1e-7);
end

function testWithoutGravityTheCapsuleFliesStraight(testCase)
% Drag only changes the speed, so over a round Earth the path is a straight
% line in space while γ (measured from the local horizon) flattens.
p = ballistic(7500, -30, 5000);
p.curvature = true;
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.termination, 'ground');
direction = [cosd(-30) sind(-30)];          % at the entry point, x downrange, y up
offset = [r.x - r.x(1), r.y - r.y(1)];
distance = abs(offset(:, 1) * direction(2) - offset(:, 2) * direction(1));
verifyLessThan(testCase, max(distance), 1, 'Within a metre of the straight line.');
% At the ground, cos γ = (R + h_E) cos γ_E / R (the line's distance from the centre is fixed).
R = 6371e3;
verifyEqual(testCase, r.gamma(end), -acosd((R + p.h0) * cosd(30) / R), 'AbsTol', 1e-6, ...
    'γ flattens as the horizon turns.');
end

function testLiftLowersPeakDeceleration(testCase)
p = lunarReturn();
p.V0 = 7600;
p.gamma0 = -1.5;
p.beta = 400;
p.LD = 0;
p.bank = 0;
ballisticRun = dlab.sims.entry.simulateEntry(p);
p.LD = 0.3;
lifting = dlab.sims.entry.simulateEntry(p);
verifyLessThan(testCase, lifting.peaks.decel, 0.5 * ballisticRun.peaks.decel);
verifyGreaterThan(testCase, ballisticRun.peaks.decel, 8);
verifyLessThan(testCase, ballisticRun.peaks.decel, 11);
verifyGreaterThan(testCase, lifting.heatLoad(end), ballisticRun.heatLoad(end), ...
    'A longer, gentler flight soaks up more heat.');
end

function testSteeperIsHarsher(testCase)
p = lunarReturn();
p.LD = 0;
p.V0 = 7600;
peak = zeros(1, 4);
angles = [-2 -5 -10 -20];
for k = 1:4
    p.gamma0 = angles(k);
    r = dlab.sims.entry.simulateEntry(p);
    peak(k) = r.peaks.decel;
end
verifyTrue(testCase, all(diff(peak) > 0), 'Peak deceleration grows with the entry angle.');
end

function testShallowEntrySkipsOut(testCase)
p = lunarReturn();
p.gamma0 = -4.5;
p.bank = 0;
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.termination, 'skip');
verifyTrue(testCase, r.skipped);
verifyEqual(testCase, r.h(end), p.h0 + 1, 'AbsTol', 1e-3);
verifyGreaterThan(testCase, r.V(end), 10e3);
verifyGreaterThan(testCase, r.gamma(end), 0);
end

function testStopsAtParachuteOrGround(testCase)
r = dlab.sims.entry.simulateEntry(lunarReturn());
verifyEqual(testCase, r.termination, 'chute');
verifyEqual(testCase, r.mach(end), 0.8, 'RelTol', 1e-6);
verifyFalse(testCase, r.skipped);
verifyGreaterThan(testCase, r.peaks.decel, 5);
verifyLessThan(testCase, r.peaks.decel, 9);
p = lunarReturn();
p.chuteMach = 0;
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.termination, 'ground');
verifyEqual(testCase, r.h(end), 0, 'AbsTol', 1e-3);
end

function testSuttonGravesHeating(testCase)
p = lunarReturn();
p.dt = 0.1;
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.qdot, 1.7415e-4 * sqrt(r.rho / 4.7) .* r.V.^3, 'RelTol', 1e-12);
verifyEqual(testCase, r.heatLoad(end), trapz(r.t, r.qdot), 'RelTol', 1e-4, ...
    'The integrated heat load matches the samples.');
p.noseRadius = 4 * 4.7;
blunt = dlab.sims.entry.simulateEntry(p);
% (The same trajectory to the solver's tolerance: the heat-load state takes part in its step control.)
verifyEqual(testCase, blunt.peaks.qdot, r.peaks.qdot / 2, 'RelTol', 1e-6, 'q̇ ∝ 1/√r_n.');
end

function testStandardAtmosphereDensity(testCase)
p = lunarReturn();
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.rho, dlab.physics.thermosphereDensity(r.h / 1e3), 'RelTol', 1e-12);
end

function testProgressCanCancel(testCase)
p = lunarReturn();
p.progressFcn = @(fraction) fraction > 0.3;
r = dlab.sims.entry.simulateEntry(p);
verifyEqual(testCase, r.termination, 'cancelled');
end

function testRejectsBadInput(testCase)
p = lunarReturn();
p.gamma0 = 5;
verifyError(testCase, @() dlab.sims.entry.simulateEntry(p), 'entry:InvalidParameter');
p = lunarReturn();
p.beta = 0;
verifyError(testCase, @() dlab.sims.entry.simulateEntry(p), 'entry:InvalidParameter');
p = lunarReturn();
p.atmosphere = 'martian';
verifyError(testCase, @() dlab.sims.entry.simulateEntry(p), 'entry:InvalidParameter');
end
