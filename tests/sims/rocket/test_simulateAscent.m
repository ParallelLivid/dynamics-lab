function tests = test_simulateAscent
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = sounding()
stage = struct('dry', 300, 'prop', 1200, 'thrust', 60, 'ispVac', 260, 'ispSl', 260, 'delay', 0);
p = struct('stages', stage, 'payload', 100, 'diameter', 0.5, 'cdScale', 0, 'kickAltitude', 1e9, ...
    'kickAngle', 0, 'throttle', @(t) 1, 'targetApoapsis', Inf, 'circularize', false, 'latitude', 28.5, ...
    'rotation', false, 'gravity', true, 'maxTime', 60, 'dt', 0.5);
end

function p = launcher()
stages = struct('dry', {22000, 4000}, 'prop', {400000, 92000}, 'thrust', {8200, 700}, ...
    'ispVac', {311, 348}, 'ispSl', {282, 300}, 'delay', {0, 3});
p = struct('stages', stages, 'payload', 15000, 'diameter', 3.7, 'cdScale', 1, 'kickAltitude', 300, ...
    'kickAngle', 7.5, 'throttle', @(t) 1, 'targetApoapsis', 200, 'circularize', true, 'latitude', 28.5, ...
    'rotation', false, 'gravity', true, 'maxTime', 2000, 'dt', 1);
end

function e = closure(r)
b = r.budget;
e = abs(b.thrustDv - b.gravity - b.drag - b.steering - b.achieved) / b.thrustDv;
end

function testVacuumMatchesTsiolkovsky(testCase)
p = sounding();
p.gravity = false;
r = dlab.sims.rocket.simulateAscent(p);
ideal = dlab.sims.rocket.tsiolkovsky(260, 1600, 400);
verifyEqual(testCase, r.budget.achieved, ideal, 'RelTol', 1e-8);
verifyEqual(testCase, r.budget.total, ideal, 'RelTol', 1e-12);
end

function testVerticalBurnoutSpeed(testCase)
% v = g₀ Isp ln(m₀/m_f) − ∫ g dt, vertically, without drag or back-pressure.
r = dlab.sims.rocket.simulateAscent(sounding());
burnout = r.events(strcmp({r.events.label}, 'Stage 1 burnout')).time;
during = r.t <= burnout;
radius = sqrt(r.x(during).^2 + r.y(during).^2);
gravityDv = trapz(r.t(during), 3.986004418e14 ./ radius.^2);
k = find(during, 1, 'last');
verifyEqual(testCase, r.speed(k), dlab.sims.rocket.tsiolkovsky(260, 1600, 400) - gravityDv, 'RelTol', 1e-3);
verifyLessThan(testCase, max(abs(r.x)), 1e-6, 'Straight up.');
end

function testStagingAndBudget(testCase)
p = launcher();
r = dlab.sims.rocket.simulateAscent(p);
verifyLessThan(testCase, closure(r), 1e-6);
k = find(r.t == r.events(strcmp({r.events.label}, 'Stage 1 burnout')).time, 1, 'last');
liftoff = 15000 + 22000 + 400000 + 4000 + 92000;
verifyEqual(testCase, r.mass(k), liftoff - 400000 - 22000, 'RelTol', 1e-9, 'The empty first stage is dropped.');
verifyTrue(testCase, r.orbitAchieved);
verifyGreaterThan(testCase, r.orbit.perigee, 150);
[~, iq] = max(r.q);
verifyGreaterThan(testCase, r.h(iq), 8e3);
verifyLessThan(testCase, r.h(iq), 15e3);
verifyGreaterThan(testCase, r.budget.gravity, 1000);
verifyLessThan(testCase, r.budget.gravity, 1800);
end

function testBurnoutKeepsTheBurningMass(testCase)
% The last burning sample has the full burnout mass (400 kg) and its thrust
% acceleration; the next one, at the same time, has dropped the stage.
r = dlab.sims.rocket.simulateAscent(sounding());
k = find(r.t == r.events(strcmp({r.events.label}, 'Stage 1 burnout')).time);
verifyEqual(testCase, r.mass(k), [400; 100], 'RelTol', 1e-9);
verifyEqual(testCase, r.stage(k), [1; 0]);
verifyEqual(testCase, r.gload(k(1)), 60e3 / 400 / 9.80665, 'RelTol', 1e-9, 'No air: T/m exactly.');
end

function testCoastGoesOnToTheApoapsis(testCase)
% The time limit ends a coast after cutoff only after the apoapsis.
p = launcher();
p.maxTime = 700;                           % cutoff near 585 s, apoapsis near 2000 s
r = dlab.sims.rocket.simulateAscent(p);
verifyTrue(testCase, any(strcmp({r.events.label}, 'Circularization burn')));
verifyGreaterThan(testCase, r.t(end), 1900);
verifyEqual(testCase, r.orbit.e, 0, 'AbsTol', 1e-6);
end

function testThrottleBucketLowersMaxQ(testCase)
p = launcher();
r = dlab.sims.rocket.simulateAscent(p);
nominal = max(r.q);
p.kickAngle = 5;
p.throttle = @(t) 1 - 0.3 * (t > 40 & t < 75);
r = dlab.sims.rocket.simulateAscent(p);
verifyLessThan(testCase, max(r.q), 0.9 * nominal);
verifyLessThan(testCase, closure(r), 1e-6);
end

function testExtendedAtmosphereIsContinuous(testCase)
[rhoBelow, ~, pBelow] = dlab.physics.atmosphere(86000 - 1e-6, 'Extended', true);
[rhoAbove, ~, pAbove] = dlab.physics.atmosphere(86000 + 1e-6, 'Extended', true);
verifyEqual(testCase, rhoAbove, rhoBelow, 'RelTol', 1e-6);
verifyEqual(testCase, pAbove, pBelow, 'RelTol', 1e-6);
rho = dlab.physics.atmosphere([0; 50e3; 120e3], 'Extended', true);
verifySize(testCase, rho, [3 1]);
end

function testRejectsBadStages(testCase)
p = sounding();
p.stages.ispSl = 300;
verifyError(testCase, @() dlab.sims.rocket.simulateAscent(p), 'rocket:InvalidParameter');
end
