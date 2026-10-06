function tests = test_flyby
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));
end

function p = flyby(planet, vinf, alpha, altitude, pass)
% Engine inputs for a pass of PLANET.
d = dlab.sims.flyby.planetData(planet);
p = struct('mu', d.mu, 'R', d.radius, 'aOrbit', d.a, 'muSun', d.muSun, 'vinf', vinf, 'alpha', alpha, ...
    'altitude', altitude, 'pass', pass, 'durationFactor', 30);
end

function cases = encounters()
cases = {
    flyby('Jupiter', 10.7, -120, 277400, 'behind')     % Voyager-like
    flyby('Venus', 6.6, -77, 284, 'behind')            % Cassini-like
    flyby('Earth', 8.8, -100, 960, 'ahead')
    flyby('Jupiter', 6.6, -148, 4000, 'behind')        % turning angle 154°
    flyby('Mars', 4.2, 125, 300, 'ahead')
};
end

function testTurningAngleFromTheTrajectory(testCase)
% Independent reference: the hyperbola's turning angle 2 asin(1/e).
% δ = 2 asin(1 / (1 + r_p v∞² / μ)), from the integrated asymptotes.
list = encounters();
for k = 1:numel(list)
    p = list{k};
    r = dlab.sims.flyby.simulateFlyby(p);
    rp = p.R + p.altitude;
    expected = 2 * asin(1 / (1 + rp * p.vinf^2 / p.mu));
    verifyEqual(testCase, r.deltaAnalytic, expected, 'RelTol', 1e-14);
    verifyEqual(testCase, r.deltaNumeric, expected, 'AbsTol', 1e-6, sprintf('Case %d', k));
end
end

function testRawAngleTendsToTheAsymptotes(testCase)
% Without the asymptote correction, the angle between the end velocities
% falls short of δ, less so the farther out the run starts.
p = flyby('Jupiter', 10.7, -120, 277400, 'behind');
errors = zeros(1, 3);
factors = [5 30 1e6];
for k = 1:3
    p.durationFactor = factors(k);
    r = dlab.sims.flyby.simulateFlyby(p);
    errors(k) = r.deltaAnalytic - r.deltaRaw;
end
verifyGreaterThan(testCase, errors, 0);
verifyTrue(testCase, issorted(errors, 'descend'));
verifyEqual(testCase, r.T, r.tSoi, 'RelTol', 1e-12, 'A huge factor stops at the sphere of influence.');
end

function testThePlanetFrameConservesEnergy(testCase)
list = encounters();
for k = 1:numel(list)
    p = list{k};
    r = dlab.sims.flyby.simulateFlyby(p);
    verifyEqual(testCase, norm(r.vInfOut), p.vinf, 'RelTol', 1e-9, '|v∞,out| = |v∞,in|');
    energy = r.speed.^2 / 2 - p.mu ./ r.rMag;
    verifyEqual(testCase, energy, repmat(p.vinf^2 / 2, size(energy)), 'RelTol', 1e-8);
    verifyEqual(testCase, r.closest, p.R + p.altitude, 'RelTol', 1e-9, 'Closest approach at r_p.');
end
end

function testDeltaV(testCase)
% Δv = 2 v∞ sin(δ/2).
list = encounters();
for k = 1:numel(list)
    r = dlab.sims.flyby.simulateFlyby(list{k});
    verifyEqual(testCase, norm(r.dv), 2 * r.vinf * sin(r.deltaAnalytic / 2), 'RelTol', 1e-8);
    verifyEqual(testCase, r.dvAnalytic, 2 * r.vinf * sin(r.deltaAnalytic / 2), 'RelTol', 1e-14);
end
end

function testHeliocentricEnergyChange(testCase)
% The specific orbital energy changes by V_p · (v∞,out − v∞,in).
list = encounters();
for k = 1:numel(list)
    r = dlab.sims.flyby.simulateFlyby(list{k});
    expected = r.Vp * (r.vInfOut(1) - r.vInfIn(1));
    verifyEqual(testCase, r.energyChange, expected, 'AbsTol', 1e-8 * r.Vp * r.vinf);
    verifyEqual(testCase, r.energyChange, (r.after.speed^2 - r.before.speed^2) / 2, 'AbsTol', 1e-8 * r.Vp * r.vinf, ...
        'Both orbits start at the planet, so only the kinetic energy differs.');
end
end

function testBehindGainsAheadLoses(testCase)
% Either way is possible when δ/2 < |α| < 180° − δ/2 (here δ = 123°).
for alpha = [-115 -100 -90 -70 70 90 110]
    behind = dlab.sims.flyby.simulateFlyby(flyby('Jupiter', 8, alpha, 200000, 'behind'));
    ahead = dlab.sims.flyby.simulateFlyby(flyby('Jupiter', 8, alpha, 200000, 'ahead'));
    message = sprintf('alpha = %g', alpha);
    verifyGreaterThan(testCase, behind.after.speed, behind.before.speed, message);
    verifyLessThan(testCase, ahead.after.speed, ahead.before.speed, message);
    verifyTrue(testCase, behind.periapsisBehind, message);
    verifyFalse(testCase, ahead.periapsisBehind, message);
    verifyEqual(testCase, abs(behind.deltaNumeric - ahead.deltaNumeric), 0, 'AbsTol', 1e-6, 'Same turn, other way.');
end
end

function testHohmannArrivalAtJupiter(testCase)
% Earth to Jupiter by Hohmann: the spacecraft arrives at aphelion with
% V_J √(2 r_E / (r_E + r_J)) = 7.413 km/s, so v∞ = 5.643 km/s straight back.
earth = dlab.sims.flyby.planetData('Earth');
jupiter = dlab.sims.flyby.planetData('Jupiter');
arrival = jupiter.Vp * sqrt(2 * earth.a / (earth.a + jupiter.a));
verifyEqual(testCase, arrival, 7.413, 'AbsTol', 1e-3);
p = flyby('Jupiter', jupiter.Vp - arrival, 180, 400000, 'behind');
r = dlab.sims.flyby.simulateFlyby(p);
verifyEqual(testCase, p.vinf, 5.643, 'AbsTol', 1e-3);
verifyEqual(testCase, r.before.speed, arrival, 'RelTol', 1e-12);
verifyEqual(testCase, r.before.perihelion, earth.a, 'RelTol', 1e-10);
verifyEqual(testCase, r.before.aphelion, jupiter.a, 'RelTol', 1e-10);
verifyEqual(testCase, r.before.period / 2 / (365.25 * 86400), 2.732, 'AbsTol', 5e-3, 'The trip takes 2.73 years.');
end

function testSpheresOfInfluence(testCase)
% r_SOI = a (m/M)^(2/5): 925 000 km (Earth), 616 000 km (Venus), 577 000 km
% (Mars), 48.2 million km (Jupiter); Curtis, Orbital Mechanics for
% Engineering Students, Table A.2.
names = ["Earth" "Venus" "Mars" "Jupiter"];
expected = [925e3 616e3 577e3 48.2e6];
for k = 1:4
    d = dlab.sims.flyby.planetData(names(k));
    verifyEqual(testCase, d.rSoi, expected(k), 'RelTol', 3e-3, names(k));
end
end

function testCircularSpeedsMatchTheFactSheet(testCase)
for name = dlab.sims.flyby.planetData('names')
    d = dlab.sims.flyby.planetData(name);
    verifyEqual(testCase, d.Vp, d.meanSpeed, 'RelTol', 0.012, name);
end
earth = dlab.sims.flyby.planetData('Earth');
orbit = dlab.sims.flyby.helioOrbit([0 -earth.a], [earth.Vp 0], earth.muSun);
verifyLessThan(testCase, orbit.e, 1e-12);
verifyEqual(testCase, orbit.period / 86400, 365.25, 'AbsTol', 0.1, 'A circle at 1 AU takes a year.');
end

function testSpeedTimelineJoinsAtTheSphere(testCase)
r = dlab.sims.flyby.simulateFlyby(flyby('Jupiter', 10.7, -120, 277400, 'behind'));
passage = r.timeline;
verifyTrue(testCase, issorted(passage.t));
for edge = [-1 1] * r.tSoi
    rows = find(abs(passage.t - edge) < 1e-6 * r.tSoi);
    verifyGreaterThanOrEqual(testCase, numel(rows), 2);
    verifyEqual(testCase, max(passage.speed(rows)) - min(passage.speed(rows)), 0, 'AbsTol', 1e-9);
end
inside = abs(r.tRel) <= r.tSoi;
verifyEqual(testCase, r.speedHelio(inside), sqrt(sum(([r.Vp 0] + r.v(inside, :)).^2, 2)), 'RelTol', 1e-14);
end

function testRejectsBadInput(testCase)
p = flyby('Earth', 5, 0, 500, 'behind');
bad = {'vinf', -1; 'altitude', -10; 'pass', 'over'; 'durationFactor', 0; 'altitude', 2e6};
for k = 1:size(bad, 1)
    q = p;
    q.(bad{k, 1}) = bad{k, 2};
    verifyError(testCase, @() dlab.sims.flyby.simulateFlyby(q), 'flyby:InvalidParameter', bad{k, 1});
end
verifyError(testCase, @() dlab.sims.flyby.planetData('Pluto'), 'flyby:InvalidParameter');
end

function testCancelStopsTheRun(testCase)
p = flyby('Jupiter', 10.7, -120, 277400, 'behind');
p.progressFcn = @(~) true;
verifyError(testCase, @() dlab.sims.flyby.simulateFlyby(p), 'flyby:Cancelled');
end
