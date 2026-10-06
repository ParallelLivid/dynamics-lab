function tests = test_maneuvers
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = earth(type)
p = struct('mu', 398600.4418, 'R', 6371, 'type', type, 'alt1', 300, 'alt2', 35786, 'altB', 100000, ...
    'inc1', 0, 'dInc', 0, 'phaseAngle', 30, 'phasingRevs', 1, 'burns', []);
end

function q = fly()
q = struct('mu', 398600.4418, 'R', 6371, 'sampleStep', 60, 'coastAfter', 1);
end

function testHohmannToGeo(testCase)
plan = dlab.sims.maneuvers.planManeuver(earth('hohmann'));
verifyEqual(testCase, plan.dv', [2.4277 1.4676], 'AbsTol', 1e-4);
verifyEqual(testCase, plan.total, 3.8952, 'AbsTol', 5e-4);
verifyEqual(testCase, plan.transferTime / 3600, 5.27, 'AbsTol', 0.005);
r = dlab.sims.maneuvers.propagateBurns(fly(), plan);
verifyEqual(testCase, r.final.a, plan.r2, 'RelTol', 1e-6);
verifyLessThan(testCase, r.final.e, 1e-6);
verifyEqual(testCase, r.burnLog(2).time - r.burnLog(1).time, plan.transferTime, 'RelTol', 1e-6, ...
    'The second burn is at the apoapsis, half an ellipse later.');
end

function testBiellipticCrossover(testCase)
% Independent reference: the published Hohmann/bi-elliptic crossover ratios 11.94 and 15.58.
% Hohmann wins below r₂/r₁ = 11.94; bi-elliptic (far r_b) wins above 15.58.
r1 = 6671;
for ratio = [5 11]
    p = earth('hohmann');
    [p.alt2, p.altB] = deal(ratio * r1 - 6371, 1e4 * r1);
    plan = dlab.sims.maneuvers.planManeuver(p);
    verifyLessThan(testCase, plan.alternatives.hohmann, plan.alternatives.bielliptic, sprintf('ratio %g', ratio));
end
for ratio = [16 30]
    p = earth('hohmann');
    [p.alt2, p.altB] = deal(ratio * r1 - 6371, 1.01 * ratio * r1);
    plan = dlab.sims.maneuvers.planManeuver(p);
    verifyLessThan(testCase, plan.alternatives.bielliptic, plan.alternatives.hohmann, sprintf('ratio %g', ratio));
end
end

function testBiellipticFlies(testCase)
p = earth('bielliptic');
[p.alt2, p.altB] = deal(20 * 6671 - 6371, 40 * 6671 - 6371);
plan = dlab.sims.maneuvers.planManeuver(p);
q = fly();
q.sampleStep = 600;
r = dlab.sims.maneuvers.propagateBurns(q, plan);
verifyEqual(testCase, numel(r.burnLog), 3);
verifyEqual(testCase, r.final.a, plan.r2, 'RelTol', 1e-6);
verifyLessThan(testCase, r.final.e, 1e-6);
end

function testPlaneChange(testCase)
p = earth('plane');
[p.alt1, p.dInc] = deal(35786, 28.5);
plan = dlab.sims.maneuvers.planManeuver(p);
v = sqrt(398600.4418 / 42157);
verifyEqual(testCase, plan.total, 2 * v * sind(14.25), 'RelTol', 1e-12);
verifyEqual(testCase, plan.total, 1.5137, 'AbsTol', 2e-4);
q = fly();
q.sampleStep = 600;
r = dlab.sims.maneuvers.propagateBurns(q, plan);
verifyEqual(testCase, r.final.i, 28.5, 'AbsTol', 1e-8);
end

function testCombinedPlaneChange(testCase)
p = earth('combined');
[p.inc1, p.dInc] = deal(28.5, -28.5);
plan = dlab.sims.maneuvers.planManeuver(p);
verifyLessThan(testCase, plan.total, plan.alternatives.separate);
verifyLessThan(testCase, abs(plan.split), 5, 'Most of the turn is done at the top.');
r = dlab.sims.maneuvers.propagateBurns(fly(), plan);
verifyEqual(testCase, r.final.i, 0, 'AbsTol', 1e-6);
verifyEqual(testCase, r.final.a, plan.r2, 'RelTol', 1e-6);
end

function testPhasingRendezvous(testCase)
p = earth('phasing');
p.alt1 = 35786;
plan = dlab.sims.maneuvers.planManeuver(p);
r = dlab.sims.maneuvers.propagateBurns(fly(), plan);
verifyLessThan(testCase, r.miss, 1);
verifyEqual(testCase, r.final.a, plan.r1, 'RelTol', 1e-6);
end

function testCustomBurns(testCase)
p = earth('custom');
p.burns = struct('at', {'time', 'apoapsis'}, 'value', {0, 1}, 'prograde', {100, 100}, 'normal', {0, 0}, ...
    'radial', {0, 0});
plan = dlab.sims.maneuvers.planManeuver(p);
verifyEqual(testCase, plan.total, 0.2, 'AbsTol', 1e-12);
r = dlab.sims.maneuvers.propagateBurns(fly(), plan);
verifyEqual(testCase, numel(r.burnLog), 2);
verifyLessThan(testCase, abs(r.burnLog(2).r * r.burnLog(2).v'), 1e-6 * norm(r.burnLog(2).r) * norm(r.burnLog(2).v), ...
    'The second burn is at an apsis.');
end

function testRejectsImpossiblePlans(testCase)
p = earth('phasing');
verifyError(testCase, @() dlab.sims.maneuvers.planManeuver(p), 'maneuvers:InvalidParameter');
p = earth('bielliptic');
p.altB = 1000;
verifyError(testCase, @() dlab.sims.maneuvers.planManeuver(p), 'maneuvers:InvalidParameter');
end

function testTransferToTheSameOrbit(testCase)
% No apsis on a circular transfer orbit: the second burn waits half a turn.
p = earth('hohmann');
p.alt2 = p.alt1;
plan = dlab.sims.maneuvers.planManeuver(p);
verifyEqual(testCase, plan.total, 0, 'AbsTol', 1e-12);
r = dlab.sims.maneuvers.propagateBurns(fly(), plan);
verifyEqual(testCase, r.burnLog(2).time, plan.transferTime, 'RelTol', 1e-12);
verifyEqual(testCase, r.final.a, plan.r1, 'RelTol', 1e-8);
p.type = 'combined';
p.dInc = 10;
r = dlab.sims.maneuvers.propagateBurns(fly(), dlab.sims.maneuvers.planManeuver(p));
verifyEqual(testCase, r.final.i, 10, 'AbsTol', 1e-6);
end

function testCancelStopsTheFlight(testCase)
q = fly();
q.progressFcn = @(~) true;
plan = dlab.sims.maneuvers.planManeuver(earth('hohmann'));
verifyError(testCase, @() dlab.sims.maneuvers.propagateBurns(q, plan), 'maneuvers:Cancelled');
end
